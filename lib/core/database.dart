import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/anchor_model.dart';
import '../models/anchor_item_model.dart';

// ── Link preview cache model ──────────────────────────────────────────────────

class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl; // raw OG image URL
  final String? siteName;
  final DateTime fetchedAt;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    required this.fetchedAt,
  });

  Map<String, dynamic> toMap() => {
        'url': url,
        'title': title,
        'description': description,
        'image_url': imageUrl,
        'site_name': siteName,
        'fetched_at': fetchedAt.millisecondsSinceEpoch,
      };

  factory LinkPreviewData.fromMap(Map<String, dynamic> m) => LinkPreviewData(
        url: m['url'] as String,
        title: m['title'] as String?,
        description: m['description'] as String?,
        imageUrl: m['image_url'] as String?,
        siteName: m['site_name'] as String?,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(m['fetched_at'] as int),
      );
}

// ── Database ──────────────────────────────────────────────────────────────────

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
      version: 2,
      onCreate: (db, _) => _createAll(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _migrateV1toV2(db);
      },
    );
  }

  Future<void> _createAll(Database db) async {
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
        sync_status TEXT NOT NULL DEFAULT 'na',
        cloudinary_url TEXT,
        cloudinary_public_id TEXT,
        thumbnail_url TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (anchor_id) REFERENCES anchors(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_items_anchor ON anchor_items(anchor_id)');
    await db.execute(
        'CREATE INDEX idx_items_sync ON anchor_items(sync_status)');
    await db.execute('''
      CREATE TABLE link_previews (
        url TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        image_url TEXT,
        site_name TEXT,
        fetched_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _migrateV1toV2(Database db) async {
    // SQLite has no ADD COLUMN IF NOT EXISTS, so we swallow duplicate-column
    // errors. This makes the migration safe to re-run if a previous attempt was
    // interrupted (sqflite rolls back the version bump on failure, so the
    // migration can fire again on the next cold start).
    Future<void> safeAlter(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already exists — skip.
      }
    }

    await safeAlter(
        "ALTER TABLE anchor_items ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'na'");
    await safeAlter(
        'ALTER TABLE anchor_items ADD COLUMN cloudinary_url TEXT');
    await safeAlter(
        'ALTER TABLE anchor_items ADD COLUMN cloudinary_public_id TEXT');
    await safeAlter(
        'ALTER TABLE anchor_items ADD COLUMN thumbnail_url TEXT');
    await safeAlter(
        'ALTER TABLE anchor_items ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0');

    // Only mark items that haven't been touched yet (sync_status still 'na').
    await db.execute('''
      UPDATE anchor_items
      SET sync_status = 'pending'
      WHERE type IN ('image', 'video', 'audio', 'file')
        AND sync_status = 'na'
    ''');

    // Create link preview cache — safe even if the table already exists.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS link_previews (
        url TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        image_url TEXT,
        site_name TEXT,
        fetched_at INTEGER NOT NULL
      )
    ''');

    // Secondary index for quick pending lookup.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_sync ON anchor_items(sync_status)');
  }

  // ── Anchors ───────────────────────────────────────────────────────────────

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

  // ── Items ─────────────────────────────────────────────────────────────────

  Future<List<AnchorItemModel>> getItems(String anchorId) async {
    final rows = await (await db).query(
      'anchor_items',
      where: 'anchor_id = ?',
      whereArgs: [anchorId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AnchorItemModel.fromMap).toList();
  }

  /// Up to [limit] preview items for home screen anchor cards.
  Future<List<AnchorItemModel>> getPreviewItems(String anchorId,
      {int limit = 4}) async {
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
    // Media items go into the upload queue; links/text don't need Cloudinary.
    final syncStatus = (type == ItemType.image ||
            type == ItemType.video ||
            type == ItemType.audio ||
            type == ItemType.file)
        ? SyncStatus.pending
        : SyncStatus.na;

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
      syncStatus: syncStatus,
    );
    await (await db).insert('anchor_items', item.toMap());
    return item;
  }

  Future<void> deleteItem(String id) async {
    final item = await getItemById(id);
    if (item != null && item.isLocal) {
      // Delete local file
      final file = File(item.content);
      if (await file.exists()) await file.delete();
      // Delete local thumbnail if present
      if (item.thumbnailPath != null) {
        final thumb = File(item.thumbnailPath!);
        if (await thumb.exists()) await thumb.delete();
      }
      // Note: Cloudinary asset is NOT deleted here (requires API secret / backend).
    }
    await (await db).delete('anchor_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<AnchorItemModel?> getItemById(String id) async {
    final rows = await (await db)
        .query('anchor_items', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return AnchorItemModel.fromMap(rows.first);
  }

  /// Copy a content URI into our private files directory and return the new path.
  Future<String> copyUriToStorage(String uri, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = join(dir.path, 'anchors', filename);
    await Directory(join(dir.path, 'anchors')).create(recursive: true);
    final src = File(Uri.parse(uri).toFilePath(windows: false));
    if (await src.exists()) await src.copy(dest);
    return dest;
  }

  // ── Cloudinary sync helpers ───────────────────────────────────────────────

  /// All items that still need to be uploaded (pending or failed with retries left).
  Future<List<AnchorItemModel>> getPendingItems() async {
    final rows = await (await db).rawQuery('''
      SELECT * FROM anchor_items
      WHERE sync_status IN ('pending', 'failed')
        AND retry_count < 3
      ORDER BY created_at ASC
    ''');
    return rows.map(AnchorItemModel.fromMap).toList();
  }

  /// Update sync state after an upload attempt.
  Future<void> updateItemSync(
    String id, {
    required SyncStatus syncStatus,
    String? cloudinaryUrl,
    String? cloudinaryPublicId,
    String? thumbnailUrl,
  }) async {
    final values = <String, dynamic>{'sync_status': syncStatus.value};
    if (cloudinaryUrl != null) values['cloudinary_url'] = cloudinaryUrl;
    if (cloudinaryPublicId != null) {
      values['cloudinary_public_id'] = cloudinaryPublicId;
    }
    if (thumbnailUrl != null) values['thumbnail_url'] = thumbnailUrl;

    await (await db)
        .update('anchor_items', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Increment retry counter (called on upload failure).
  Future<void> incrementRetryCount(String id) async {
    await (await db).rawUpdate(
        'UPDATE anchor_items SET retry_count = retry_count + 1 WHERE id = ?',
        [id]);
  }

  // ── Link preview cache ────────────────────────────────────────────────────

  Future<LinkPreviewData?> getLinkPreview(String url) async {
    final rows = await (await db).query(
      'link_previews',
      where: 'url = ?',
      whereArgs: [url],
    );
    if (rows.isEmpty) return null;
    return LinkPreviewData.fromMap(rows.first);
  }

  Future<void> saveLinkPreview(LinkPreviewData data) async {
    await (await db).insert(
      'link_previews',
      data.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
