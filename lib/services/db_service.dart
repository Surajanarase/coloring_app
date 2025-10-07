import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _db;

  // bumped to 3 to apply schema change (paths.area, images.total_area)
  static const int _dbVersion = 3;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'coloring_app.db');
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // development-friendly upgrade: drop and recreate schema.
        // NOTE: this will remove existing user coloring progress.
        try {
          await db.execute('DROP TABLE IF EXISTS paths');
          await db.execute('DROP TABLE IF EXISTS images');
          await db.execute('DROP TABLE IF EXISTS users');
        } catch (_) {}
        await _createSchema(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    // users table for username/password auth
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT
      )
    ''');

    // images table: added total_area (REAL)
    await db.execute('''
      CREATE TABLE images (
        id TEXT PRIMARY KEY,
        title TEXT,
        total_paths INTEGER,
        total_area REAL DEFAULT 0
      )
    ''');

    // paths table: added area (REAL)
    await db.execute('''
      CREATE TABLE paths (
        id TEXT PRIMARY KEY,
        image_id TEXT,
        is_colored INTEGER DEFAULT 0,
        color TEXT,
        area REAL DEFAULT 0,
        FOREIGN KEY(image_id) REFERENCES images(id)
      )
    ''');
  }

  // -----------------------
  // User methods (auth)
  // -----------------------

  Future<String> createUser(String username, String password) async {
    final database = await db;
    try {
      await database.insert(
        'users',
        {'username': username, 'password': password},
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return 'ok';
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return 'exists';
      }
      return 'db_error';
    } catch (_) {
      return 'unknown_error';
    }
  }

  Future<bool> authenticateUser(String username, String password) async {
    final database = await db;
    final rows = await database.query(
      'users',
      columns: ['id'],
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final database = await db;
    return database.query('users');
  }

  // -----------------------
  // Coloring app methods (area-aware)
  // -----------------------

  /// Upsert image. Pass totalArea (optional) if known.
  Future<void> upsertImage(String id, String title, int totalPaths, {double totalArea = 0.0}) async {
    final database = await db;
    await database.insert(
      'images',
      {'id': id, 'title': title, 'total_paths': totalPaths, 'total_area': totalArea},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert paths with area mapping: { pathId: area, ... }
  Future<void> insertPathsForImage(String imageId, Map<String, double> pathAreas) async {
    if (pathAreas.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final entry in pathAreas.entries) {
      batch.insert(
        'paths',
        {
          'id': entry.key,
          'image_id': imageId,
          'is_colored': 0,
          'color': null,
          'area': entry.value
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);

    final totalArea = pathAreas.values.fold<double>(0.0, (a, b) => a + b);
    await database.update(
      'images',
      {'total_paths': pathAreas.length, 'total_area': totalArea},
      where: 'id = ?',
      whereArgs: [imageId],
    );
  }

  Future<void> markPathColored(String pathId, String colorHex) async {
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 1, 'color': colorHex},
      where: 'id = ?',
      whereArgs: [pathId],
    );
  }

  Future<void> markPathUncolored(String pathId) async {
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'id = ?',
      whereArgs: [pathId],
    );
  }

  /// Return dashboard rows with area sums:
  /// each row includes id, title, total_paths, total_area, colored_area
  Future<List<Map<String, dynamic>>> getDashboardRows() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT i.id, i.title, i.total_paths,
        COALESCE((SELECT SUM(area) FROM paths p WHERE p.image_id = i.id), 0) AS total_area,
        COALESCE((SELECT SUM(area) FROM paths p WHERE p.image_id = i.id AND p.is_colored = 1), 0) AS colored_area
      FROM images i
      ORDER BY i.id
    ''');
    return rows;
  }

  Future<List<Map<String, dynamic>>> getColoredPathsForImage(String imageId) async {
    final database = await db;
    return await database.rawQuery(
      'SELECT id, color FROM paths WHERE image_id = ? AND is_colored = 1',
      [imageId],
    );
  }

  Future<void> resetImageProgress(String imageId) async {
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'image_id = ?',
      whereArgs: [imageId],
    );
  }

  // -----------------------
  // Debug / helpers
  // -----------------------

  Future<void> debugDumpImages() async {
    final database = await db;
    final images = await database.query('images');
    debugPrint('[DbService] images count = ${images.length}');
    for (var i = 0; i < images.length; i++) {
      final im = images[i];
      final totalAreaRows = await database.rawQuery('SELECT SUM(area) AS total_area FROM paths WHERE image_id = ?', [im['id']]);
      final coloredAreaRows = await database.rawQuery('SELECT SUM(area) AS colored_area FROM paths WHERE image_id = ? AND is_colored = 1', [im['id']]);
      final totalArea = (totalAreaRows.isNotEmpty ? (totalAreaRows.first['total_area'] as num?)?.toDouble() : null) ?? 0.0;
      final coloredArea = (coloredAreaRows.isNotEmpty ? (coloredAreaRows.first['colored_area'] as num?)?.toDouble() : null) ?? 0.0;
      final total = im['total_paths'] ?? 0;
      debugPrint('[DbService] image[$i] id=${im['id']} title=${im['title']} colored_area=${coloredArea.toStringAsFixed(2)} total_area=${totalArea.toStringAsFixed(2)} total_paths=$total');
    }
  }

  // legacy helpers (still available)
  Future<int> getColoredCountForImage(String imageId) async {
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM paths WHERE image_id = ? AND is_colored = 1',
      [imageId],
    ));
    return result ?? 0;
  }

  Future<int> getTotalPathsForImage(String imageId) async {
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT total_paths FROM images WHERE id = ?',
      [imageId],
    ));
    return result ?? 0;
  }
}
