import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _db;
  static const int _dbVersion = 4; // bumped version for per-user schema

  String? _currentUsername;
  void setCurrentUser(String username) {
    _currentUsername = username;
  }

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
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE images (
        id TEXT,
        username TEXT,
        title TEXT,
        total_paths INTEGER,
        total_area REAL DEFAULT 0,
        PRIMARY KEY (id, username)
      )
    ''');

    await db.execute('''
      CREATE TABLE paths (
        id TEXT,
        image_id TEXT,
        username TEXT,
        is_colored INTEGER DEFAULT 0,
        color TEXT,
        area REAL DEFAULT 0,
        PRIMARY KEY (id, username),
        FOREIGN KEY(image_id, username) REFERENCES images(id, username)
      )
    ''');
  }

  // -----------------------
  // User auth
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
    if (rows.isNotEmpty) {
      setCurrentUser(username);
      return true;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final database = await db;
    return database.query('users');
  }

  // -----------------------
  // Coloring app methods (per-user)
  // -----------------------

  Future<void> upsertImage(
    String id,
    String title,
    int totalPaths, {
    double totalArea = 0.0,
  }) async {
    if (_currentUsername == null) return;
    final database = await db;
    await database.insert(
      'images',
      {
        'id': id,
        'username': _currentUsername,
        'title': title,
        'total_paths': totalPaths,
        'total_area': totalArea
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertPathsForImage(String imageId, Map<String, double> pathAreas) async {
    if (_currentUsername == null || pathAreas.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final entry in pathAreas.entries) {
      batch.insert(
        'paths',
        {
          'id': entry.key,
          'image_id': imageId,
          'username': _currentUsername,
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
      {
        'total_paths': pathAreas.length,
        'total_area': totalArea,
      },
      where: 'id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername],
    );
  }

  Future<void> markPathColored(String pathId, String colorHex) async {
    if (_currentUsername == null) return;
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 1, 'color': colorHex},
      where: 'id = ? AND username = ?',
      whereArgs: [pathId, _currentUsername],
    );
  }

  Future<void> markPathUncolored(String pathId) async {
    if (_currentUsername == null) return;
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'id = ? AND username = ?',
      whereArgs: [pathId, _currentUsername],
    );
  }

  Future<List<Map<String, dynamic>>> getDashboardRows() async {
    if (_currentUsername == null) return [];
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT i.id, i.title, i.total_paths,
        COALESCE((SELECT SUM(area) FROM paths p WHERE p.image_id = i.id AND p.username = i.username), 0) AS total_area,
        COALESCE((SELECT SUM(area) FROM paths p WHERE p.image_id = i.id AND p.username = i.username AND p.is_colored = 1), 0) AS colored_area
      FROM images i
      WHERE i.username = ?
      ORDER BY i.id
    ''', [_currentUsername]);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getColoredPathsForImage(String imageId) async {
    if (_currentUsername == null) return [];
    final database = await db;
    return await database.rawQuery(
      'SELECT id, color FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
      [imageId, _currentUsername],
    );
  }

  Future<void> resetImageProgress(String imageId) async {
    if (_currentUsername == null) return;
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'image_id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername],
    );
  }

  // -----------------------
  // Debug
  // -----------------------

  Future<void> debugDumpImages() async {
    if (_currentUsername == null) return;
    final database = await db;
    final images = await database.query('images', where: 'username = ?', whereArgs: [_currentUsername]);
    debugPrint('[DbService] images count for $_currentUsername = ${images.length}');
    for (var im in images) {
      final id = im['id'] as String;
      final totalAreaRows = await database.rawQuery(
          'SELECT SUM(area) AS total_area FROM paths WHERE image_id = ? AND username = ?',
          [id, _currentUsername]);
      final coloredAreaRows = await database.rawQuery(
          'SELECT SUM(area) AS colored_area FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
          [id, _currentUsername]);
      final totalArea =
          (totalAreaRows.isNotEmpty ? (totalAreaRows.first['total_area'] as num?)?.toDouble() : null) ?? 0.0;
      final coloredArea =
          (coloredAreaRows.isNotEmpty ? (coloredAreaRows.first['colored_area'] as num?)?.toDouble() : null) ?? 0.0;
      debugPrint('[DbService] $id total_area=$totalArea colored_area=$coloredArea');
    }
  }

  // Legacy helpers
  Future<int> getColoredCountForImage(String imageId) async {
    if (_currentUsername == null) return 0;
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
      [imageId, _currentUsername],
    ));
    return result ?? 0;
  }

  Future<int> getTotalPathsForImage(String imageId) async {
    if (_currentUsername == null) return 0;
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT total_paths FROM images WHERE id = ? AND username = ?',
      [imageId, _currentUsername],
    ));
    return result ?? 0;
  }
}
