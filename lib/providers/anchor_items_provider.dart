import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../core/firestore_service.dart';
import '../core/sync_service.dart';
import '../models/anchor_item_model.dart';
import 'anchors_provider.dart';

class AnchorItemsNotifier
    extends FamilyAsyncNotifier<List<AnchorItemModel>, String> {
  bool _restoreInFlight = false;
  bool _disposed = false;
  bool _disposeHookInstalled = false;

  @override
  Future<List<AnchorItemModel>> build(String anchorId) async {
    if (!_disposeHookInstalled) {
      _disposeHookInstalled = true;
      ref.onDispose(() => _disposed = true);
    }

    final localItems = await AppDatabase.instance.getItems(anchorId);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null && localItems.isEmpty && !_restoreInFlight) {
      final alreadySynced =
          await AppDatabase.instance.isAnchorSynced(anchorId);
      if (!alreadySynced) {
        _restoreInFlight = true;
        _syncItemsAndRefresh(uid, anchorId).whenComplete(() {
          _restoreInFlight = false;
        });
      }
    }

    return localItems;
  }

  Future<void> _syncItemsAndRefresh(String uid, String anchorId) async {
    await _syncItemsFromFirestore(uid, anchorId);
    if (_disposed) return;
    final items = await AppDatabase.instance.getItems(anchorId);
    if (_disposed) return;
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
      await AppDatabase.instance.markAnchorSynced(anchorId);
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
      unawaited(
        FirestoreService.instance.saveItem(uid, item).catchError((e) {
          debugPrint('Firestore saveItem failed: $e');
        }),
      );
    }

    state = AsyncData([item, ...(state.valueOrNull ?? [])]);
    ref.invalidate(anchorPreviewProvider(arg));

    if (item.needsSync) {
      unawaited(
        ref.read(cloudinarySyncProvider.notifier).syncPending().catchError((e) {
          debugPrint('syncPending after addItem failed: $e');
        }),
      );
    }

    return item;
  }

  Future<void> remove(String itemId) async {
    final item = await AppDatabase.instance.getItemById(itemId);
    await AppDatabase.instance.deleteItem(itemId);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && item != null) {
      unawaited(
        FirestoreService.instance
            .deleteItem(uid, item.anchorId, itemId)
            .catchError((e) {
          debugPrint('Firestore deleteItem failed: $e');
        }),
      );
    }

    state = AsyncData(
      (state.valueOrNull ?? []).where((i) => i.id != itemId).toList(),
    );
    ref.invalidate(anchorPreviewProvider(arg));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }
}

final anchorItemsProvider = AsyncNotifierProvider.family<AnchorItemsNotifier,
    List<AnchorItemModel>, String>(AnchorItemsNotifier.new);
