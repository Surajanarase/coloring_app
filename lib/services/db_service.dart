// lib/services/db_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _db;
  static const int _dbVersion = 5; // bumped for bug fixes

  String? _currentUsername;
  void setCurrentUser(String username) {
    _currentUsername = username;
  }

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
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Clean upgrade - drop and recreate
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
    
    // Create indexes for faster queries
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paths_image ON paths(image_id, username)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paths_colored ON paths(image_id, username, is_colored)');
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

  /// Insert or update paths with their areas
  Future<void> insertPathsForImage(String imageId, Map<String, double> pathAreas) async {
    if (_currentUsername == null || pathAreas.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    
    for (final entry in pathAreas.entries) {
      // Check if path already exists
      final existing = await database.query(
        'paths',
        where: 'id = ? AND username = ?',
        whereArgs: [entry.key, _currentUsername],
        limit: 1,
      );
      
      if (existing.isEmpty) {
        // Insert new path
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
      } else {
        // Update existing path's area (preserve color state)
        batch.update(
          'paths',
          {'area': entry.value},
          where: 'id = ? AND username = ?',
          whereArgs: [entry.key, _currentUsername],
        );
      }
    }
    await batch.commit(noResult: true);

    // Update image total area
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

  /// Mark a path as colored with specific color
  Future<void> markPathColored(String pathId, String colorHex) async {
    if (_currentUsername == null) return;
    final database = await db;
    
    final updated = await database.update(
      'paths',
      {'is_colored': 1, 'color': colorHex},
      where: 'id = ? AND username = ?',
      whereArgs: [pathId, _currentUsername],
    );
    
    debugPrint('[DB] Marked path $pathId as colored ($colorHex) - updated: $updated rows');
  }

  /// Mark a path as uncolored (erased)
  Future<void> markPathUncolored(String pathId) async {
    if (_currentUsername == null) return;
    final database = await db;
    
    final updated = await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'id = ? AND username = ?',
      whereArgs: [pathId, _currentUsername],
    );
    
    debugPrint('[DB] Marked path $pathId as uncolored - updated: $updated rows');
  }

  /// Get dashboard rows with ACCURATE area-based progress
  Future<List<Map<String, dynamic>>> getDashboardRows() async {
    if (_currentUsername == null) return [];
    final database = await db;
    
    final rows = await database.rawQuery('''
      SELECT 
        i.id, 
        i.title, 
        i.total_paths,
        i.total_area,
        COALESCE(
          (SELECT SUM(p.area) 
           FROM paths p 
           WHERE p.image_id = i.id 
             AND p.username = i.username 
             AND p.is_colored = 1), 
          0
        ) AS colored_area
      FROM images i
      WHERE i.username = ?
      ORDER BY i.id
    ''', [_currentUsername]);
    
    // Debug output
    for (var row in rows) {
      final id = row['id'] as String;
      final totalArea = (row['total_area'] as num?)?.toDouble() ?? 0.0;
      final coloredArea = (row['colored_area'] as num?)?.toDouble() ?? 0.0;
      final percent = totalArea > 0 ? (coloredArea / totalArea * 100).round() : 0;
      debugPrint('[DB] $id: $percent% complete (colored: $coloredArea / total: $totalArea)');
    }
    
    return rows;
  }

  /// Get all colored paths for an image
  Future<List<Map<String, dynamic>>> getColoredPathsForImage(String imageId) async {
    if (_currentUsername == null) return [];
    final database = await db;
    return await database.rawQuery(
      'SELECT id, color FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
      [imageId, _currentUsername],
    );
  }

  /// ✅ FIXED: Reset all paths for an image to uncolored
  Future<void> resetImageProgress(String imageId) async {
    if (_currentUsername == null) return;
    final database = await db;
    
    final updated = await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'image_id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername],
    );
    
    debugPrint('[DB] Reset image $imageId - cleared $updated paths');
    
    // Verify reset
    final coloredCount = await database.rawQuery(
      'SELECT COUNT(*) as count FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
      [imageId, _currentUsername],
    );
    final remaining = Sqflite.firstIntValue(coloredCount) ?? 0;
    debugPrint('[DB] After reset: $remaining colored paths remaining (should be 0)');
  }

  // -----------------------
  // Helper methods
  // -----------------------

  /// Get count of colored paths for an image
  Future<int> getColoredCountForImage(String imageId) async {
    if (_currentUsername == null) return 0;
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
      [imageId, _currentUsername],
    ));
    return result ?? 0;
  }

  /// Get total path count for an image
  Future<int> getTotalPathsForImage(String imageId) async {
    if (_currentUsername == null) return 0;
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM paths WHERE image_id = ? AND username = ?',
      [imageId, _currentUsername],
    ));
    return result ?? 0;
  }

  // -----------------------
  // Debug
  // -----------------------

  Future<void> debugDumpImages() async {
    if (_currentUsername == null) return;
    final database = await db;
    final images = await database.query('images', where: 'username = ?', whereArgs: [_currentUsername]);
    
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('[DB DEBUG] Images for user: $_currentUsername (count: ${images.length})');
    debugPrint('═══════════════════════════════════════════════════════');
    
    for (var im in images) {
      final id = im['id'] as String;
      final title = im['title'] as String;
      final totalPaths = im['total_paths'] as int;
      final totalArea = (im['total_area'] as num?)?.toDouble() ?? 0.0;
      
      // Get colored area
      final coloredAreaRows = await database.rawQuery(
        'SELECT SUM(area) AS colored_area FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
        [id, _currentUsername]
      );
      final coloredArea = (coloredAreaRows.isNotEmpty ? (coloredAreaRows.first['colored_area'] as num?)?.toDouble() : null) ?? 0.0;
      
      // Get colored count
      final coloredCount = await getColoredCountForImage(id);
      
      final percent = totalArea > 0 ? (coloredArea / totalArea * 100).round() : 0;
      
      debugPrint('');
      debugPrint('Image: $title');
      debugPrint('  ID: $id');
      debugPrint('  Total paths: $totalPaths');
      debugPrint('  Colored paths: $coloredCount');
      debugPrint('  Total area: ${totalArea.toStringAsFixed(2)}');
      debugPrint('  Colored area: ${coloredArea.toStringAsFixed(2)}');
      debugPrint('  Progress: $percent%');
      debugPrint('───────────────────────────────────────────────────────');
    }
    
    debugPrint('═══════════════════════════════════════════════════════');
  }

  /// Clear all data for current user (useful for testing)
  Future<void> clearUserData() async {
    if (_currentUsername == null) return;
    final database = await db;
    
    await database.delete('paths', where: 'username = ?', whereArgs: [_currentUsername]);
    await database.delete('images', where: 'username = ?', whereArgs: [_currentUsername]);
    
    debugPrint('[DB] Cleared all data for user: $_currentUsername');
  }

  /// Close database connection
  Future<void> close() async {
    final database = _db;
    if (database != null) {
      await database.close();
      _db = null;
      debugPrint('[DB] Database closed');
    }
  }
}