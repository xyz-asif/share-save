import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../core/firestore_service.dart';
import '../models/anchor_item_model.dart';
import 'anchors_provider.dart';

class AnchorItemsNotifier
    extends FamilyAsyncNotifier<List<AnchorItemModel>, String> {
  @override
  Future<List<AnchorItemModel>> build(String anchorId) async {
    final localItems = await AppDatabase.instance.getItems(anchorId);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && localItems.isEmpty) {
      // Run Firestore restore in the background — same reason as AnchorsNotifier:
      // awaiting it would freeze the detail screen while network calls resolve.
      _syncItemsAndRefresh(uid, anchorId);
    }

    return localItems;
  }

  Future<void> _syncItemsAndRefresh(String uid, String anchorId) async {
    await _syncItemsFromFirestore(uid, anchorId);
    final items = await AppDatabase.instance.getItems(anchorId);
    if (items.isNotEmpty) {
      state = AsyncData(items);
    }
  }

  Future<void> _syncItemsFromFirestore(String uid, String anchorId) async {
    try {
      final remoteItems =
          await FirestoreService.instance.getItems(uid, anchorId);
      for (final item in remoteItems) {
        await AppDatabase.instance.upsertItem(item);
      }
    } catch (_) {
      // Non-fatal — local data (if any) is still shown.
    }
  }

  /// Add a new item to both local DB and Firestore.
  Future<AnchorItemModel> addItem({
    required ItemType type,
    String? title,
    String? description,
    required String content,
    String? thumbnailPath,
    String? originalFilename,
    String? mimeType,
  }) async {
    final item = await AppDatabase.instance.createItem(
      anchorId: arg,
      type: type,
      title: title,
      description: description,
      content: content,
      thumbnailPath: thumbnailPath,
      originalFilename: originalFilename,
      mimeType: mimeType,
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService.instance.saveItem(uid, item);
    }

    // Update state in-place — no ref.invalidateSelf() to avoid sync loop.
    state = AsyncData([item, ...(state.valueOrNull ?? [])]);
    ref.invalidate(anchorPreviewProvider(arg));
    return item;
  }

  Future<void> remove(String itemId) async {
    final item = await AppDatabase.instance.getItemById(itemId);
    await AppDatabase.instance.deleteItem(itemId);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && item != null) {
      FirestoreService.instance.deleteItem(uid, item.anchorId, itemId);
    }

    state = AsyncData(
      (state.valueOrNull ?? []).where((i) => i.id != itemId).toList(),
    );
    ref.invalidate(anchorPreviewProvider(arg));
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final anchorItemsProvider = AsyncNotifierProvider.family<AnchorItemsNotifier,
    List<AnchorItemModel>, String>(AnchorItemsNotifier.new);
