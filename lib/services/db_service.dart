// lib/services/db_service.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _db;

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
      version: 1,
      onCreate: (db, version) async {
        // users table for username/password auth
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE,
            password TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE images (
            id TEXT PRIMARY KEY,
            title TEXT,
            total_paths INTEGER
          )
        ''');

        // paths are now per-user (user_id). Unique constraint on (id, user_id).
        await db.execute('''
          CREATE TABLE paths (
            id TEXT,
            image_id TEXT,
            user_id INTEGER,
            is_colored INTEGER DEFAULT 0,
            color TEXT,
            PRIMARY KEY (id, user_id),
            FOREIGN KEY(image_id) REFERENCES images(id),
            FOREIGN KEY(user_id) REFERENCES users(id)
          )
        ''');
      },
    );
  }

  // -----------------------
  // User methods (auth)
  // -----------------------

  /// Create a new user. Returns new user id on success, -1 if username exists, or -2 on other DB errors.
  Future<int> createUser(String username, String password) async {
    final database = await db;
    try {
      final id = await database.insert(
        'users',
        {'username': username, 'password': password},
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      debugPrint('User created with id: $id, username: $username');
      return id;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        debugPrint('Attempt to create existing username: $username');
        return -1; // username exists
      }
      debugPrint('DB exception in createUser: $e');
      return -2; // other db error
    } catch (e) {
      debugPrint('Unknown exception in createUser: $e');
      return -2;
    }
  }

  /// Authenticate user and return their id if successful, otherwise null.
  Future<int?> authenticateUser(String username, String password) async {
    final database = await db;
    final rows = await database.query(
      'users',
      columns: ['id'],
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  /// Debug: list all users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final database = await db;
    return database.query('users');
  }

  // -----------------------
  // Image & paths methods (per-user)
  // -----------------------

  /// Upsert image metadata (global)
  Future<void> upsertImage(String id, String title, int totalPaths) async {
    final database = await db;
    await database.insert(
      'images',
      {'id': id, 'title': title, 'total_paths': totalPaths},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Ensure path rows exist for a given image and user.
  /// Inserts rows (id, image_id, user_id) for each path id if they don't exist for that user.
  Future<void> ensurePathsForUser(String imageId, List<String> pathIds, int userId) async {
    if (pathIds.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final pid in pathIds) {
      batch.insert(
        'paths',
        {'id': pid, 'image_id': imageId, 'user_id': userId, 'is_colored': 0, 'color': null},
        conflictAlgorithm: ConflictAlgorithm.ignore, // ignore if exists for that user
      );
    }
    await batch.commit(noResult: true);
  }

  /// Mark a path as colored for a specific user
  Future<void> markPathColored(String pathId, String colorHex, int userId) async {
    final database = await db;
    final updated = await database.update(
      'paths',
      {'is_colored': 1, 'color': colorHex},
      where: 'id = ? AND user_id = ?',
      whereArgs: [pathId, userId],
    );

    // If row didn't exist (edge case), insert one for this user
    if (updated == 0) {
      await database.insert('paths', {
        'id': pathId,
        'image_id': null,
        'user_id': userId,
        'is_colored': 1,
        'color': colorHex
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Mark a path uncolored for a specific user
  Future<void> markPathUncolored(String pathId, int userId) async {
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'id = ? AND user_id = ?',
      whereArgs: [pathId, userId],
    );
  }

  /// Count colored paths for an image for a specific user
  Future<int> getColoredCountForImage(String imageId, int userId) async {
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM paths WHERE image_id = ? AND user_id = ? AND is_colored = 1',
      [imageId, userId],
    ));
    return result ?? 0;
  }

  /// Get total paths count for an image (global metadata)
  Future<int> getTotalPathsForImage(String imageId) async {
    final database = await db;
    final result = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT total_paths FROM images WHERE id = ?',
      [imageId],
    ));
    return result ?? 0;
  }

  /// Dashboard rows for a given user: each image + colored count for that user
  Future<List<Map<String, dynamic>>> getDashboardRowsForUser(int userId) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT i.id, i.title, i.total_paths,
        COALESCE( (SELECT COUNT(*) FROM paths p WHERE p.image_id = i.id AND p.user_id = ? AND p.is_colored = 1), 0) AS colored
      FROM images i
      ORDER BY i.title
    ''', [userId]);
    return rows;
  }

  /// Get colored paths (id + color) for an image for a specific user
  Future<List<Map<String, dynamic>>> getColoredPathsForImage(String imageId, int userId) async {
    final database = await db;
    final rows = await database.query(
      'paths',
      columns: ['id', 'color'],
      where: 'image_id = ? AND user_id = ? AND is_colored = 1',
      whereArgs: [imageId, userId],
    );
    return rows;
  }

  /// Reset image progress for a specific user
  Future<void> resetImageProgress(String imageId, int userId) async {
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'image_id = ? AND user_id = ?',
      whereArgs: [imageId, userId],
    );
  }
}
