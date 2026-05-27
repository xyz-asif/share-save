import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/anchor_model.dart';
import '../models/anchor_item_model.dart';

/// Syncs anchors and their items to Firestore so they survive reinstalls.
///
/// Firestore structure:
///   users/{uid}/anchors/{anchorId}           → anchor metadata
///   users/{uid}/anchors/{anchorId}/items/{itemId} → item data
class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Collection helpers ────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _anchorsCol(String uid) =>
      _db.collection('users').doc(uid).collection('anchors');

  CollectionReference<Map<String, dynamic>> _itemsCol(
          String uid, String anchorId) =>
      _anchorsCol(uid).doc(anchorId).collection('items');

  // ── Anchors ───────────────────────────────────────────────────────────────

  /// Upsert an anchor to Firestore (create or overwrite).
  Future<void> saveAnchor(String uid, AnchorModel anchor) async {
    await _anchorsCol(uid).doc(anchor.id).set(_anchorToFirestore(anchor));
  }

  /// Delete an anchor and all its items from Firestore.
  Future<void> deleteAnchor(String uid, String anchorId) async {
    // Delete all items first (Firestore doesn't cascade).
    final itemsSnap = await _itemsCol(uid, anchorId).get();
    final batch = _db.batch();
    for (final doc in itemsSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_anchorsCol(uid).doc(anchorId));
    await batch.commit();
  }

  /// Fetch all anchors for a user from Firestore.
  Future<List<AnchorModel>> getAnchors(String uid) async {
    final snap = await _anchorsCol(uid).orderBy('created_at').get();
    return snap.docs
        .map((d) => _anchorFromFirestore(d.id, d.data()))
        .toList();
  }

  // ── Items ─────────────────────────────────────────────────────────────────

  /// Upsert an item to Firestore.
  Future<void> saveItem(String uid, AnchorItemModel item) async {
    await _itemsCol(uid, item.anchorId)
        .doc(item.id)
        .set(_itemToFirestore(item));
  }

  /// Delete a single item from Firestore.
  Future<void> deleteItem(
      String uid, String anchorId, String itemId) async {
    await _itemsCol(uid, anchorId).doc(itemId).delete();
  }

  /// Fetch all items for an anchor from Firestore.
  Future<List<AnchorItemModel>> getItems(
      String uid, String anchorId) async {
    final snap = await _itemsCol(uid, anchorId).orderBy('created_at').get();
    return snap.docs
        .map((d) => _itemFromFirestore(d.id, d.data()))
        .toList();
  }

  // ── Serialisation helpers ─────────────────────────────────────────────────

  Map<String, dynamic> _anchorToFirestore(AnchorModel a) => {
        'name': a.name,
        'description': a.description,
        'color_value': a.colorValue,
        'created_at': a.createdAt.millisecondsSinceEpoch,
      };

  AnchorModel _anchorFromFirestore(String id, Map<String, dynamic> d) =>
      AnchorModel(
        id: id,
        name: d['name'] as String,
        description: d['description'] as String?,
        colorValue: d['color_value'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(d['created_at'] as int),
      );

  Map<String, dynamic> _itemToFirestore(AnchorItemModel i) => {
        'anchor_id': i.anchorId,
        'type': i.type.value,
        'title': i.title,
        'description': i.description,
        // For media, prefer cloudinaryUrl so restored items display correctly.
        // Local file paths won't be valid after reinstall.
        'content': i.cloudinaryUrl ?? i.content,
        'original_filename': i.originalFilename,
        'mime_type': i.mimeType,
        'created_at': i.createdAt.millisecondsSinceEpoch,
        'sync_status': i.syncStatus.value,
        'cloudinary_url': i.cloudinaryUrl,
        'cloudinary_public_id': i.cloudinaryPublicId,
        'thumbnail_url': i.thumbnailUrl,
        'retry_count': i.retryCount,
        // thumbnailPath is a local device path — intentionally omitted.
      };

  AnchorItemModel _itemFromFirestore(String id, Map<String, dynamic> d) =>
      AnchorItemModel(
        id: id,
        anchorId: d['anchor_id'] as String,
        type: ItemTypeExt.fromString(d['type'] as String),
        title: d['title'] as String?,
        description: d['description'] as String?,
        content: d['content'] as String,
        originalFilename: d['original_filename'] as String?,
        mimeType: d['mime_type'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(d['created_at'] as int),
        syncStatus:
            SyncStatusExt.fromString(d['sync_status'] as String? ?? 'na'),
        cloudinaryUrl: d['cloudinary_url'] as String?,
        cloudinaryPublicId: d['cloudinary_public_id'] as String?,
        thumbnailUrl: d['thumbnail_url'] as String?,
        retryCount: d['retry_count'] as int? ?? 0,
        // thumbnailPath left null — not stored in Firestore.
      );
}
