import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/anchor_model.dart';
import '../models/anchor_item_model.dart';

class AppDatabase {
  static AppDatabase? _instance;
  static Database? _db;

  AppDatabase._();
  static AppDatabase get instance => _instance ??= AppDatabase._();

  Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'anchor.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE anchors (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            color_value INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE anchor_items (
            id TEXT PRIMARY KEY,
            anchor_id TEXT NOT NULL,
            type TEXT NOT NULL,
            title TEXT,
            description TEXT,
            content TEXT NOT NULL,
            thumbnail_path TEXT,
            original_filename TEXT,
            mime_type TEXT,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (anchor_id) REFERENCES anchors(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_items_anchor ON anchor_items(anchor_id)');
      },
    );
  }

  // --- Anchors ---

  Future<List<AnchorModel>> getAnchors() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT a.*, COUNT(i.id) as item_count
      FROM anchors a
      LEFT JOIN anchor_items i ON i.anchor_id = a.id
      GROUP BY a.id
      ORDER BY a.created_at DESC
    ''');
    return rows.map(AnchorModel.fromMap).toList();
  }

  Future<AnchorModel> createAnchor({
    required String name,
    String? description,
    required int colorValue,
  }) async {
    final anchor = AnchorModel(
      id: const Uuid().v4(),
      name: name,
      description: description,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    await (await db).insert('anchors', anchor.toMap());
    return anchor;
  }

  Future<void> deleteAnchor(String id) async {
    final d = await db;
    await d.delete('anchor_items', where: 'anchor_id = ?', whereArgs: [id]);
    await d.delete('anchors', where: 'id = ?', whereArgs: [id]);
  }

  // --- Items ---

  Future<List<AnchorItemModel>> getItems(String anchorId) async {
    final rows = await (await db).query(
      'anchor_items',
      where: 'anchor_id = ?',
      whereArgs: [anchorId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AnchorItemModel.fromMap).toList();
  }

  /// Returns up to [limit] preview items — images first, then others by recency.
  Future<List<AnchorItemModel>> getPreviewItems(String anchorId,
      {int limit = 3}) async {
    final rows = await (await db).rawQuery('''
      SELECT * FROM anchor_items
      WHERE anchor_id = ?
      ORDER BY created_at DESC
      LIMIT ?
    ''', [anchorId, limit]);
    return rows.map(AnchorItemModel.fromMap).toList();
  }

  Future<AnchorItemModel> createItem({
    required String anchorId,
    required ItemType type,
    String? title,
    String? description,
    required String content,
    String? thumbnailPath,
    String? originalFilename,
    String? mimeType,
  }) async {
    final item = AnchorItemModel(
      id: const Uuid().v4(),
      anchorId: anchorId,
      type: type,
      title: title,
      description: description,
      content: content,
      thumbnailPath: thumbnailPath,
      originalFilename: originalFilename,
      mimeType: mimeType,
      createdAt: DateTime.now(),
    );
    await (await db).insert('anchor_items', item.toMap());
    return item;
  }

  Future<void> deleteItem(String id) async {
    final item = await getItemById(id);
    if (item != null && item.isLocal) {
      final file = File(item.content);
      if (await file.exists()) await file.delete();
      if (item.thumbnailPath != null) {
        final thumb = File(item.thumbnailPath!);
        if (await thumb.exists()) await thumb.delete();
      }
    }
    await (await db).delete('anchor_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<AnchorItemModel?> getItemById(String id) async {
    final rows = await (await db).query('anchor_items', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return AnchorItemModel.fromMap(rows.first);
  }

  /// Copy a content URI into our private files directory and return the new path.
  Future<String> copyUriToStorage(String uri, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = join(dir.path, 'anchors', filename);
    await Directory(join(dir.path, 'anchors')).create(recursive: true);
    final src = File(Uri.parse(uri).toFilePath(windows: false));
    if (await src.exists()) {
      await src.copy(dest);
    }
    return dest;
  }
}
