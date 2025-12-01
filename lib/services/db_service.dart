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
  static const int _dbVersion = 10; // Bumped for critical fixes
  String? _currentUsername;

  void setCurrentUser(String username) {
    _currentUsername = username;
    debugPrint('[DB] Current user set to: $username');
  }

  Future<Database> get db async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'coloring_app.db');
    debugPrint('[DB] Initializing database at: $path');
    
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        debugPrint('[DB] Creating new database schema...');
        await _createSchema(db);
      },
      onUpgrade: (db, oldV, newV) async {
        debugPrint('[DB] Upgrading database from v$oldV to v$newV');
        await _createSchema(db);
        await _ensureUserColumns(db);
        await _ensureImageColumns(db);
      },
      onOpen: (db) async {
        debugPrint('[DB] Database opened');
        await _ensureUserColumns(db);
        await _ensureImageColumns(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        fullname TEXT,
        age INTEGER,
        gender TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS images (
        id TEXT,
        username TEXT,
        title TEXT,
        total_paths INTEGER,
        total_area REAL DEFAULT 0,
        display_percent REAL DEFAULT 0,
        PRIMARY KEY (id, username)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS paths (
        id TEXT,
        image_id TEXT,
        username TEXT,
        is_colored INTEGER DEFAULT 0,
        color TEXT,
        area REAL DEFAULT 0,
        PRIMARY KEY (id, image_id, username),
        FOREIGN KEY(image_id, username) REFERENCES images(id, username)
      )
    ''');

    // Enhanced indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paths_image ON paths(image_id, username)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paths_colored ON paths(image_id, username, is_colored)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_paths_lookup ON paths(id, image_id, username)');
    
    debugPrint('[DB] Schema created with indexes');
  }

  Future<void> _ensureUserColumns(Database db) async {
    try {
      final info = await db.rawQuery("PRAGMA table_info('users')");
      final existing = <String>{};
      for (final row in info) {
        final name = row['name']?.toString();
        if (name != null) existing.add(name);
      }

      final batch = db.batch();
      var hasAlter = false;
      
      if (!existing.contains('fullname')) {
        batch.execute("ALTER TABLE users ADD COLUMN fullname TEXT");
        hasAlter = true;
      }
      if (!existing.contains('age')) {
        batch.execute("ALTER TABLE users ADD COLUMN age INTEGER");
        hasAlter = true;
      }
      if (!existing.contains('gender')) {
        batch.execute("ALTER TABLE users ADD COLUMN gender TEXT");
        hasAlter = true;
      }

      if (hasAlter) {
        await batch.commit(noResult: true);
        debugPrint('[DB] User columns migration complete');
      }
    } catch (e) {
      debugPrint('[DB] _ensureUserColumns failed: $e');
    }
  }

  Future<void> _ensureImageColumns(Database db) async {
    try {
      final info = await db.rawQuery("PRAGMA table_info('images')");
      final existing = <String>{};
      for (final row in info) {
        final name = row['name']?.toString();
        if (name != null) existing.add(name);
      }

      final batch = db.batch();
      var hasAlter = false;
      
      if (!existing.contains('display_percent')) {
        batch.execute("ALTER TABLE images ADD COLUMN display_percent REAL DEFAULT 0");
        hasAlter = true;
      }

      if (hasAlter) {
        await batch.commit(noResult: true);
        debugPrint('[DB] Image columns migration complete');
      }
    } catch (e) {
      debugPrint('[DB] _ensureImageColumns failed: $e');
    }
  }

  // ============ USER AUTH ============
  
  Future<String> createUser(
    String username, 
    String password,
    {String? fullname, int? age, String? gender}
  ) async {
    final database = await db;
    try {
      await database.insert('users', {
        'username': username,
        'password': password,
        'fullname': fullname,
        'age': age,
        'gender': gender,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      debugPrint('[DB] User created: $username');
      return 'ok';
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        debugPrint('[DB] User already exists: $username');
        return 'exists';
      }
      debugPrint('[DB] Database error creating user: $e');
      return 'db_error';
    } catch (e) {
      debugPrint('[DB] Unknown error creating user: $e');
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
      limit: 1
    );
    
    if (rows.isNotEmpty) {
      setCurrentUser(username);
      debugPrint('[DB] User authenticated: $username');
      return true;
    }
    
    debugPrint('[DB] Authentication failed for: $username');
    return false;
  }

  Future<void> deleteUser(String username) async {
    final database = await db;
    
    try {
      debugPrint('[DB] Deleting user: $username');
      
      // Delete all user's coloring data first (foreign key constraint)
      await database.delete(
        'paths',
        where: 'username = ?',
        whereArgs: [username],
      );
      debugPrint('[DB] Deleted paths for user: $username');
      
      await database.delete(
        'images',
        where: 'username = ?',
        whereArgs: [username],
      );
      debugPrint('[DB] Deleted images for user: $username');
      
      // Finally delete the user account
      final deletedRows = await database.delete(
        'users',
        where: 'username = ?',
        whereArgs: [username],
      );
      
      if (deletedRows > 0) {
        debugPrint('[DB] ✓ User deleted successfully: $username');
        
        // Clear current user if they deleted their own account
        if (_currentUsername == username) {
          _currentUsername = null;
        }
      } else {
        debugPrint('[DB] ✗ User not found: $username');
      }
    } catch (e) {
      debugPrint('[DB] Error deleting user: $e');
      rethrow;
    }
  }

  // ============ IMAGE + PATH LOGIC ============

  Future<void> upsertImage(
    String id, 
    String title, 
    int totalPaths,
    {double totalArea = 0.0}
  ) async {
    if (_currentUsername == null) {
      debugPrint('[DB] ERROR: No current user set for upsertImage');
      return;
    }
    
    final database = await db;

    final existing = await database.query(
      'images',
      where: 'id = ? AND username = ?',
      whereArgs: [id, _currentUsername],
      limit: 1
    );

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
      
      debugPrint('[DB] Updated image: $id (area: $areaToStore)');
    } else {
      await database.insert(
        'images',
        {
          'id': id,
          'username': _currentUsername,
          'title': title,
          'total_paths': totalPaths,
          'total_area': totalArea,
          'display_percent': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      debugPrint('[DB] Inserted new image: $id (area: $totalArea)');
    }
  }

  Future<void> insertPathsForImage(
    String imageId, 
    Map<String, double> pathAreas
  ) async {
    if (_currentUsername == null || pathAreas.isEmpty) {
      debugPrint('[DB] ERROR: Cannot insert paths - no user or empty areas');
      return;
    }
    
    final database = await db;

    // Normalize areas
    final Map<String, double> normalized = {};
    for (final e in pathAreas.entries) {
      normalized[e.key] = (e.value.isFinite && e.value > 0) ? e.value : 0.0;
    }

    // Calculate outlier threshold
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
      if (filteredTotal > 0) {
        effectiveTotal = filteredTotal;
        debugPrint('[DB] Detected outlier, using filtered total: $effectiveTotal (was: $totalArea)');
      }
    }

    // Batch insert/update paths
    final batch = database.batch();
    for (final e in normalized.entries) {
      // Try insert first
      batch.insert(
        'paths',
        {
          'id': e.key,
          'image_id': imageId,
          'username': _currentUsername,
          'area': e.value,
          'is_colored': 0,
          'color': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      
      // Update area if already exists (IMPORTANT: include image_id in WHERE)
      batch.update(
        'paths',
        {'area': e.value},
        where: 'id = ? AND image_id = ? AND username = ?',
        whereArgs: [e.key, imageId, _currentUsername],
      );
    }
    await batch.commit(noResult: true);
    
    debugPrint('[DB] Inserted/updated ${normalized.length} paths for $imageId');

    // Update image total area
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
        }
      }

      await database.update(
        'images',
        {'total_paths': normalized.length, 'total_area': areaToSet},
        where: 'id = ? AND username = ?',
        whereArgs: [imageId, _currentUsername],
      );
      
      debugPrint('[DB] Updated image $imageId total_area to: $areaToSet');
    } else {
      await database.insert(
        'images',
        {
          'id': imageId,
          'username': _currentUsername,
          'title': imageId.split('/').last,
          'total_paths': normalized.length,
          'total_area': effectiveTotal,
          'display_percent': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      debugPrint('[DB] Inserted new image $imageId with area: $effectiveTotal');
    }
  }

  Future<void> markPathColored(
    String pathId, 
    String colorHex,
    {String? imageId}
  ) async {
    if (_currentUsername == null) {
      debugPrint('[DB] ERROR: No current user for markPathColored');
      return;
    }
    
    // Validate color
    if (colorHex.isEmpty || colorHex == 'none' || colorHex == 'transparent') {
      debugPrint('[DB] WARNING: Invalid color for path $pathId: $colorHex');
      return;
    }
    
    final database = await db;
    final where = imageId != null
        ? 'id = ? AND image_id = ? AND username = ?'
        : 'id = ? AND username = ?';
    final args = imageId != null
        ? [pathId, imageId, _currentUsername]
        : [pathId, _currentUsername];

    final updated = await database.update(
      'paths', 
      {'is_colored': 1, 'color': colorHex},
      where: where, 
      whereArgs: args
    );
    
    if (updated > 0) {
      debugPrint('[DB] ✓ Marked path $pathId as colored: $colorHex');
    } else {
      debugPrint('[DB] ✗ Failed to mark path $pathId (not found)');
    }
  }

  Future<void> markPathUncolored(String pathId, {String? imageId}) async {
    if (_currentUsername == null) {
      debugPrint('[DB] ERROR: No current user for markPathUncolored');
      return;
    }
    
    final database = await db;
    final where = imageId != null
        ? 'id = ? AND image_id = ? AND username = ?'
        : 'id = ? AND username = ?';
    final args = imageId != null
        ? [pathId, imageId, _currentUsername]
        : [pathId, _currentUsername];

    final updated = await database.update(
      'paths', 
      {'is_colored': 0, 'color': null},
      where: where, 
      whereArgs: args
    );
    
    if (updated > 0) {
      debugPrint('[DB] ✓ Marked path $pathId as uncolored');
    } else {
      debugPrint('[DB] ✗ Failed to uncolor path $pathId (not found)');
    }
  }

  Future<List<Map<String, dynamic>>> getColoredPathsForImage(
    String imageId
  ) async {
    if (_currentUsername == null) return [];
    
    final database = await db;
    final results = await database.rawQuery(
      '''SELECT id, color FROM paths 
         WHERE image_id = ? 
         AND username = ? 
         AND is_colored = 1 
         AND color IS NOT NULL 
         AND color != ""
         AND color != "none"''',
      [imageId, _currentUsername],
    );
    
    debugPrint('[DB] Found ${results.length} colored paths for $imageId');
    return results;
  }

  /// Return all path rows for the given image and current user.
  /// Used by the UI to determine which path IDs were inserted (i.e. passed area filtering).
  Future<List<Map<String, dynamic>>> getPathsForImage(String imageId) async {
    if (_currentUsername == null) {
      debugPrint('[DB] ERROR: No current user for getPathsForImage');
      return [];
    }

    final database = await db;
    final rows = await database.query(
      'paths',
      columns: ['id', 'image_id', 'area', 'is_colored', 'color'],
      where: 'image_id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername],
    );

    debugPrint('[DB] getPathsForImage($imageId) -> ${rows.length} rows');
    return rows;
  }

  Future<void> resetImageProgress(String imageId) async {
    if (_currentUsername == null) {
      debugPrint('[DB] ERROR: No current user for resetImageProgress');
      return;
    }
    
    final database = await db;
    
    debugPrint('[DB] Resetting progress for $imageId...');
    
    // Reset all paths
    final pathsUpdated = await database.update(
      'paths', 
      {'is_colored': 0, 'color': null},
      where: 'image_id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername]
    );
    
    // Clear display percent
    await database.update(
      'images', 
      {'display_percent': 0},
      where: 'id = ? AND username = ?', 
      whereArgs: [imageId, _currentUsername]
    );
    
    // Verify reset
    final verification = await database.rawQuery(
      '''SELECT COUNT(*) as colored_count 
         FROM paths 
         WHERE image_id = ? 
         AND username = ? 
         AND is_colored = 1''',
      [imageId, _currentUsername]
    );
    
    final coloredCount = verification.first['colored_count'] as int;
    
    if (coloredCount == 0) {
      debugPrint('[DB] ✓ Reset complete: $pathsUpdated paths cleared, verification passed');
    } else {
      debugPrint('[DB] ✗ WARNING: Reset incomplete - $coloredCount paths still marked colored!');
    }
  }

  Future<void> updateImageDisplayPercent(String imageId, double percent) async {
    if (_currentUsername == null) return;
    
    final database = await db;
    await database.update(
      'images',
      {'display_percent': percent},
      where: 'id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername],
    );
    
    debugPrint('[DB] Updated display_percent for $imageId: $percent%');
  }

  Future<double> getImageDisplayPercent(String imageId) async {
    if (_currentUsername == null) return 0.0;
    
    final database = await db;
    final result = await database.query(
      'images',
      columns: ['display_percent'],
      where: 'id = ? AND username = ?',
      whereArgs: [imageId, _currentUsername],
      limit: 1,
    );
    
    if (result.isNotEmpty) {
      final v = (result.first['display_percent'] as num?)?.toDouble() ?? 0.0;
      return v.clamp(0.0, 100.0);
    }
    return 0.0;
  }

    Future<List<Map<String, dynamic>>> getDashboardRows() async {
    if (_currentUsername == null) {
      debugPrint('[DB] ERROR: No current user for getDashboardRows');
      return [];
    }
    
    final database = await db;
    
    final rows = await database.rawQuery('''
      SELECT 
        i.id, 
        i.title, 
        i.total_paths, 
        i.total_area,
        COALESCE(SUM(p.area), 0) AS colored_area,
        COALESCE(i.display_percent, 0) AS display_percent
      FROM images i
      LEFT JOIN paths p 
        ON p.image_id = i.id 
       AND p.username = i.username
       AND p.is_colored = 1
      WHERE i.username = ?
      GROUP BY i.id, i.title, i.total_paths, i.total_area, i.display_percent
      ORDER BY i.id
    ''', [_currentUsername]);

    final out = <Map<String, dynamic>>[];

    for (final r in rows) {
      final total = ((r['total_area'] as num?)?.toDouble() ?? 0).clamp(0, 1e10);
      final colored = ((r['colored_area'] as num?)?.toDouble() ?? 0).clamp(0.0, total);
      double displayPct = ((r['display_percent'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 100.0);

      // 🔒 New 60% rule for *display* everywhere:
      // if colored_area >= 60% of total_area => treat as 100% complete
      if (total > 0 && colored >= 0.6 * total) {
        displayPct = 100.0;
      }

      out.add({
        'id': r['id'],
        'title': r['title'],
        'total_paths': r['total_paths'],
        'total_area': total,
        'colored_area': colored,
        'display_percent': displayPct,
      });
    }
    
    debugPrint('[DB] Retrieved ${out.length} dashboard rows');
    return out;
  }


  // ============ DEBUG ============

  Future<void> debugDumpImages() async {
    if (_currentUsername == null) return;
    
    final database = await db;
    final imgs = await database.query(
      'images', 
      where: 'username = ?', 
      whereArgs: [_currentUsername]
    );

    debugPrint('╔════════════════════════════════════════════════════════════╗');
    debugPrint('║ DB DEBUG - Images for user: $_currentUsername (${imgs.length})');
    debugPrint('╠════════════════════════════════════════════════════════════╣');
    
    for (var im in imgs) {
      final id = im['id'];
      final totalArea = (im['total_area'] as num?)?.toDouble() ?? 0.0;
      final displayPct = (im['display_percent'] as num?)?.toDouble() ?? 0.0;
      
      final coloredAreaRows = await database.rawQuery(
        'SELECT SUM(area) AS ca FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
        [id, _currentUsername],
      );
      final colored = (coloredAreaRows.first['ca'] as num?)?.toDouble() ?? 0.0;
      
      final coloredCountRows = await database.rawQuery(
        'SELECT COUNT(*) AS cnt FROM paths WHERE image_id = ? AND username = ? AND is_colored = 1',
        [id, _currentUsername],
      );
      final coloredCount = (coloredCountRows.first['cnt'] as int?) ?? 0;
      
      final pct = totalArea > 0 ? (colored / totalArea * 100).clamp(0, 100) : 0;
      
      debugPrint('║ $id');
      debugPrint('║   Total Area: ${totalArea.toStringAsFixed(2)}');
      debugPrint('║   Colored Area: ${colored.toStringAsFixed(2)}');
      debugPrint('║   Colored Paths: $coloredCount');
      debugPrint('║   Raw Progress: ${pct.toStringAsFixed(1)}%');
      debugPrint('║   Display Percent: ${displayPct.toStringAsFixed(1)}%');
      debugPrint('╠════════════════════════════════════════════════════════════╣');
    }
    
    debugPrint('╚════════════════════════════════════════════════════════════╝');
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
      debugPrint('[DB] Database closed');
    }
  }
    // ===================== QUIZ RESULTS =====================

  Future<void> saveQuizResult({
    required String quizId,
    required int score,
    required int totalQuestions,
  }) async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return;

    final database = await db;
    await _ensureQuizTable(database);

    final percent =
        totalQuestions > 0 ? (score * 100.0 / totalQuestions) : 0.0;

    await database.insert(
      'quiz_results',
      {
        'username': _currentUsername,
        'quiz_id': quizId,
        'score': score,
        'total_questions': totalQuestions,
        'percent': percent,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getQuizResultsForUser() async {
    if (_currentUsername == null || _currentUsername!.isEmpty) return [];

    final database = await db;
    await _ensureQuizTable(database);

    return database.query(
      'quiz_results',
      where: 'username = ?',
      whereArgs: [_currentUsername],
    );
  }

  Future<void> _ensureQuizTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS quiz_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        quiz_id TEXT NOT NULL,
        score INTEGER NOT NULL,
        total_questions INTEGER NOT NULL,
        percent REAL NOT NULL,
        completed_at INTEGER NOT NULL,
        UNIQUE (username, quiz_id)
      )
    ''');
  }
}

