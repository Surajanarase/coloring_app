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
        await db.execute('''
          CREATE TABLE images (
            id TEXT PRIMARY KEY,
            title TEXT,
            total_paths INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE paths (
            id TEXT PRIMARY KEY,
            image_id TEXT,
            is_colored INTEGER DEFAULT 0,
            color TEXT,
            FOREIGN KEY(image_id) REFERENCES images(id)
          )
        ''');
      },
    );
  }

  Future<void> upsertImage(String id, String title, int totalPaths) async {
    final database = await db;
    await database.insert(
      'images',
      {'id': id, 'title': title, 'total_paths': totalPaths},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertPathsForImage(String imageId, List<String> pathIds) async {
    if (pathIds.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final pid in pathIds) {
      batch.insert(
        'paths',
        {'id': pid, 'image_id': imageId, 'is_colored': 0, 'color': null},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
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

  Future<List<Map<String, dynamic>>> getDashboardRows() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT i.id, i.title, i.total_paths,
        (SELECT COUNT(*) FROM paths p WHERE p.image_id = i.id AND p.is_colored = 1) AS colored
      FROM images i
      ORDER BY i.title
    ''');
    return rows;
  }

  /// NEW: get all colored paths with their color
  Future<List<Map<String, dynamic>>> getColoredPathsForImage(
      String imageId) async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT id, color FROM paths WHERE image_id = ? AND is_colored = 1',
      [imageId],
    );
    return rows;
  }

    /// Reset all path colors for an image (set to uncolored)
  Future<void> resetImageProgress(String imageId) async {
    final database = await db;
    await database.update(
      'paths',
      {'is_colored': 0, 'color': null},
      where: 'image_id = ?',
      whereArgs: [imageId],
    );
  }

}
