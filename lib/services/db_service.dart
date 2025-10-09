// lib/services/db_service.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _db;
  static const int _dbVersion = 7;
  String? _currentUsername;

  void setCurrentUser(String username) => _currentUsername = username;

  Future<Database> get db async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'coloring_app.db');
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async => await _createSchema(db),
      onUpgrade: (db, oldV, newV) async {
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

    await db.execute('CREATE INDEX IF NOT EXISTS idx_paths_image ON paths(image_id, username)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paths_colored ON paths(image_id, username, is_colored)');
  }

  // -------------------------------------------------------------------
  //  USER AUTH
  // -------------------------------------------------------------------
  Future<String> createUser(String username, String password) async {
    final database = await db;
    try {
      await database.insert('users', {'username': username, 'password': password},
          conflictAlgorithm: ConflictAlgorithm.abort);
      return 'ok';
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) return 'exists';
      return 'db_error';
    } catch (_) {
      return 'unknown_error';
    }
  }

  Future<bool> authenticateUser(String username, String password) async {
    final database = await db;
    final rows = await database.query('users',
        columns: ['id'],
        where: 'username = ? AND password = ?',
        whereArgs: [username, password],
        limit: 1);
    if (rows.isNotEmpty) {
      setCurrentUser(username);
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------
  //  IMAGE + PATH LOGIC (PER-USER)
  // -------------------------------------------------------------------
  Future<void> upsertImage(String id, String title, int totalPaths,
      {double totalArea = 0.0}) async {
    if (_currentUsername == null) return;
    final database = await db;

    final existing = await database.query('images',
        where: 'id = ? AND username = ?',
        whereArgs: [id, _currentUsername],
        limit: 1);

    if (existing.isNotEmpty) {
      final ex = existing.first;
      final existingTotalArea = (ex['total_area'] as num?)?.toDouble() ?? 0.0;
      final areaToStore = (existingTotalArea > 0) ? existingTotalArea : totalArea;
      await database.update(
        'images',
        {
          'title': title,
          'total_paths': totalPaths,
          'total_area': areaToStore,
        },
        where: 'id = ? AND username = ?',
        whereArgs: [id, _currentUsername],
      );
    } else {
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
  }

  /// Insert or update path areas and automatically correct total_area if needed
  Future<void> insertPathsForImage(
      String imageId, Map<String, double> pathAreas) async {
    if (_currentUsername == null || pathAreas.isEmpty) return;
    final database = await db;

    final Map<String, double> normalized = {};
    for (final e in pathAreas.entries) {
      normalized[e.key] = (e.value.isFinite && e.value > 0) ? e.value : 0.0;
    }

    final areas = normalized.values.toList()..sort();
    final count = areas.length;
    final totalArea = areas.fold(0.0, (a, b) => a + b);
    final avg = count > 0 ? totalArea / count : 0.0;
    final median = count > 0
        ? (count.isOdd
            ? areas[count ~/ 2]
            : (areas[count ~/ 2 - 1] + areas[count ~/ 2]) / 2)
        : 0.0;
    final maxA = count > 0 ? areas.last : 0.0;
    final hasOutlier = (count > 0) &&
        ((avg > 0 && maxA / (avg + 1e-9) > 20) ||
            (totalArea > 0 && maxA / (totalArea + 1e-9) > 0.5));

    double effectiveTotal = totalArea;
    if (hasOutlier) {
      final medianT = median * 10;
      final avgT = avg * 20;
      final threshold = math.max(medianT, avgT);
      final filtered = normalized.values.where((v) => v <= threshold).toList();
      final filteredTotal = filtered.fold(0.0, (a, b) => a + b);
      if (filteredTotal > 0) effectiveTotal = filteredTotal;
      debugPrint('[DB] Outlier fix for $imageId → using $effectiveTotal');
    }

    // Update paths
    final batch = database.batch();
    for (final e in normalized.entries) {
      batch.insert(
        'paths',
        {
          'id': e.key,
          'image_id': imageId,
          'username': _currentUsername,
          'area': e.value,
          'is_colored': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.update(
        'paths',
        {'area': e.value},
        where: 'id = ? AND username = ?',
        whereArgs: [e.key, _currentUsername],
      );
    }
    await batch.commit(noResult: true);

    // Update or insert image row with smart replacement logic
    final existing = await database.query(
      'images',
      where: 'id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final ex = existing.first;
      final oldArea = (ex['total_area'] as num?)?.toDouble() ?? 0.0;
      double areaToSet = oldArea;

      if (effectiveTotal > 0) {
        final ratio = oldArea / effectiveTotal;
        if (oldArea <= 0 || ratio > 1.4) {
          areaToSet = effectiveTotal;
          debugPrint(
              '[DB] Replaced total_area for $imageId (old=$oldArea new=$effectiveTotal)');
        }
      }

      await database.update(
        'images',
        {'total_paths': normalized.length, 'total_area': areaToSet},
        where: 'id = ? AND username = ?',
        whereArgs: [imageId, _currentUsername],
      );
    } else {
      await database.insert(
        'images',
        {
          'id': imageId,
          'username': _currentUsername,
          'title': imageId.split('/').last,
          'total_paths': normalized.length,
          'total_area': effectiveTotal
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // -------------------------------------------------------------------
  //  COLORING PROGRESS
  // -------------------------------------------------------------------
  Future<void> markPathColored(String pathId, String colorHex,
      {String? imageId}) async {
    if (_currentUsername == null) return;
    final database = await db;
    final where = imageId != null
        ? 'id = ? AND image_id = ? AND username = ?'
        : 'id = ? AND username = ?';
    final args = imageId != null
        ? [pathId, imageId, _currentUsername]
        : [pathId, _currentUsername];

    await database.update('paths', {'is_colored': 1, 'color': colorHex},
        where: where, whereArgs: args);
  }

  Future<void> markPathUncolored(String pathId, {String? imageId}) async {
    if (_currentUsername == null) return;
    final database = await db;
    final where = imageId != null
        ? 'id = ? AND image_id = ? AND username = ?'
        : 'id = ? AND username = ?';
    final args = imageId != null
        ? [pathId, imageId, _currentUsername]
        : [pathId, _currentUsername];
    await database.update('paths', {'is_colored': 0, 'color': null},
        where: where, whereArgs: args);
  }

  /// ✅ Added back: getColoredPathsForImage (used in colouring_page.dart)
  Future<List<Map<String, dynamic>>> getColoredPathsForImage(
      String imageId) async {
    if (_currentUsername == null) return [];
    final database = await db;
    return await database.rawQuery(
      'SELECT id, color FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
      [imageId, _currentUsername],
    );
  }

  /// ✅ Added back: resetImageProgress (used in colouring_page.dart)
  Future<void> resetImageProgress(String imageId) async {
    if (_currentUsername == null) return;
    final database = await db;
    await database.update('paths', {'is_colored': 0, 'color': null},
        where: 'image_id = ? AND username = ?',
        whereArgs: [imageId, _currentUsername]);
    debugPrint('[DB] Reset progress for $imageId');
  }

  /// Accurate area-based dashboard rows
  Future<List<Map<String, dynamic>>> getDashboardRows() async {
    if (_currentUsername == null) return [];
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT 
        i.id, i.title, i.total_paths, i.total_area,
        COALESCE(SUM(p.area), 0) AS sum_area,
        COALESCE(SUM(CASE WHEN p.is_colored = 1 THEN p.area ELSE 0 END), 0) AS colored_area
      FROM images i
      LEFT JOIN paths p ON p.image_id = i.id AND p.username = i.username
      WHERE i.username = ?
      GROUP BY i.id, i.title, i.total_paths, i.total_area
      ORDER BY i.id
    ''', [_currentUsername]);

    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final total = ((r['total_area'] as num?)?.toDouble() ?? 0).clamp(0, 1e10);
      final colored = ((r['colored_area'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, total);
      out.add({
        'id': r['id'],
        'title': r['title'],
        'total_paths': r['total_paths'],
        'total_area': total,
        'colored_area': colored,
      });
    }
    return out;
  }

  // -------------------------------------------------------------------
  //  DEBUG + UTIL
  // -------------------------------------------------------------------
  Future<void> debugDumpImages() async {
    if (_currentUsername == null) return;
    final database = await db;
    final imgs =
        await database.query('images', where: 'username = ?', whereArgs: [_currentUsername]);

    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('[DB DEBUG] Images for user: $_currentUsername (${imgs.length})');
    debugPrint('═══════════════════════════════════════════════════════');
    for (var im in imgs) {
      final id = im['id'];
      final totalArea = (im['total_area'] as num?)?.toDouble() ?? 0.0;
      final coloredAreaRows = await database.rawQuery(
        'SELECT SUM(area) AS ca FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
        [id, _currentUsername],
      );
      final colored = (coloredAreaRows.first['ca'] as num?)?.toDouble() ?? 0.0;
      final pct = totalArea > 0 ? (colored / totalArea * 100).clamp(0, 100) : 0;
      debugPrint(
          'Image: $id  → totalArea=$totalArea colored=$colored progress=${pct.toStringAsFixed(1)}%');
    }
  }

  Future<void> clearUserData() async {
    if (_currentUsername == null) return;
    final database = await db;
    await database.delete('paths', where: 'username = ?', whereArgs: [_currentUsername]);
    await database.delete('images', where: 'username = ?', whereArgs: [_currentUsername]);
    debugPrint('[DB] Cleared all data for $_currentUsername');
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
