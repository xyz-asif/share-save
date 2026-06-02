import 'dart:async';
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
  static Completer<Database>? _opening;

  AppDatabase._();
  static AppDatabase get instance => _instance ??= AppDatabase._();

  Future<Database> get db {
    if (_db != null) return Future.value(_db!);
    if (_opening != null) return _opening!.future;
    final c = Completer<Database>();
    _opening = c;
    _init().then((d) {
      _db = d;
      c.complete(d);
    }).catchError((e, st) {
      _opening = null;
      c.completeError(e, st);
    });
    return c.future;
  }

  Future<Database> _init() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'anchor.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, _) => _createAll(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _migrateV1toV2(db);
        if (oldVersion < 3) await _migrateV2toV3(db);
        if (oldVersion < 4) await _migrateV3toV4(db);
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
        width INTEGER,
        height INTEGER,
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        anchor_id TEXT PRIMARY KEY,
        synced_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _migrateV1toV2(Database db) async {
    Future<void> safeAlter(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {}
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

    await db.execute('''
      UPDATE anchor_items
      SET sync_status = 'pending'
      WHERE type IN ('image', 'video', 'audio', 'file')
        AND sync_status = 'na'
    ''');

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

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_sync ON anchor_items(sync_status)');
  }

  Future<void> _migrateV2toV3(Database db) async {
    Future<void> safeAlter(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {}
    }

    await safeAlter('ALTER TABLE anchor_items ADD COLUMN width INTEGER');
    await safeAlter('ALTER TABLE anchor_items ADD COLUMN height INTEGER');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        anchor_id TEXT PRIMARY KEY,
        synced_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _migrateV3toV4(Database db) async {
    // Items falsely marked synced (file was missing at upload time).
    // Reset to pending so they retry — if file still exists they
    // upload properly; if not, they correctly land in 'failed'.
    await db.execute('''
      UPDATE anchor_items
      SET sync_status = 'pending', retry_count = 0
      WHERE sync_status = 'synced' AND cloudinary_url IS NULL
    ''');
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
    await d.transaction((txn) async {
      await txn.delete('anchor_items', where: 'anchor_id = ?', whereArgs: [id]);
      await txn.delete('anchors', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Insert an anchor that already has an ID (e.g. restored from Firestore).
  Future<void> upsertAnchor(AnchorModel anchor) async {
    await (await db).insert(
      'anchors',
      anchor.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Insert an item that already has an ID (e.g. restored from Firestore).
  Future<void> upsertItem(AnchorItemModel item) async {
    await (await db).insert(
      'anchor_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Batch-upsert all anchors and their items in a single transaction.
  /// Network fetches should be done before calling this; all DB writes are atomic.
  Future<void> upsertAnchorsAndItems(
    List<AnchorModel> anchors,
    Map<String, List<AnchorItemModel>> itemsByAnchor,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      for (final a in anchors) {
        await txn.insert(
          'anchors',
          a.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final entry in itemsByAnchor.entries) {
        for (final item in entry.value) {
          await txn.insert(
            'anchor_items',
            item.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
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
    int? width,
    int? height,
  }) async {
    final values = <String, dynamic>{'sync_status': syncStatus.value};
    if (cloudinaryUrl != null) values['cloudinary_url'] = cloudinaryUrl;
    if (cloudinaryPublicId != null) {
      values['cloudinary_public_id'] = cloudinaryPublicId;
    }
    if (thumbnailUrl != null) values['thumbnail_url'] = thumbnailUrl;
    if (width != null) values['width'] = width;
    if (height != null) values['height'] = height;

    await (await db)
        .update('anchor_items', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Increment retry counter (called on upload failure).
  Future<void> incrementRetryCount(String id) async {
    await (await db).rawUpdate(
        'UPDATE anchor_items SET retry_count = retry_count + 1 WHERE id = ?',
        [id]);
  }

  // ── Sync metadata ─────────────────────────────────────────────────────────

  /// Mark that a Firestore restore has been performed for [anchorId].
  Future<void> markAnchorSynced(String anchorId) async {
    await (await db).insert(
      'sync_metadata',
      {
        'anchor_id': anchorId,
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns true if a Firestore restore has already been done for [anchorId].
  Future<bool> isAnchorSynced(String anchorId) async {
    final rows = await (await db).query(
      'sync_metadata',
      where: 'anchor_id = ?',
      whereArgs: [anchorId],
    );
    return rows.isNotEmpty;
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
