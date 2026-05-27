import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anchor_item_model.dart';
import '../providers/anchor_items_provider.dart';
import '../providers/anchors_provider.dart';
import 'cloudinary_service.dart';
import 'connectivity_provider.dart';
import 'database.dart';
import 'firestore_service.dart';

// ── Summary ───────────────────────────────────────────────────────────────────

class SyncSummary {
  final int pending;
  final int uploading;
  final int failed;

  const SyncSummary({
    this.pending = 0,
    this.uploading = 0,
    this.failed = 0,
  });

  static const empty = SyncSummary();

  bool get isIdle => pending == 0 && uploading == 0;

  SyncSummary copyWith({int? pending, int? uploading, int? failed}) =>
      SyncSummary(
        pending: pending ?? this.pending,
        uploading: uploading ?? this.uploading,
        failed: failed ?? this.failed,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CloudinarySyncNotifier extends AsyncNotifier<SyncSummary> {
  bool _running = false;

  @override
  Future<SyncSummary> build() async {
    // When connectivity is restored, kick off a sync pass
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final wasOnline = prev?.valueOrNull ?? false;
      final isOnline = next.valueOrNull ?? false;
      if (isOnline && !wasOnline) syncPending();
    });

    // Also attempt sync immediately on initialisation
    Future.microtask(syncPending);

    return _computeSummary();
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Called externally after a new item is added so it gets uploaded ASAP.
  Future<void> syncPending() async {
    if (_running) return;

    final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
    if (!isOnline) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _running = true;
    try {
      final items = await AppDatabase.instance.getPendingItems();
      if (items.isEmpty) {
        state = const AsyncData(SyncSummary.empty);
        return;
      }

      state = AsyncData(SyncSummary(pending: items.length));

      for (final item in items) {
        await _uploadItem(item, user.uid);
      }

      state = AsyncData(await _computeSummary());
    } finally {
      _running = false;
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _uploadItem(AnchorItemModel item, String uid) async {
    // Mark as uploading so the UI can show a spinner
    await AppDatabase.instance.updateItemSync(
      item.id,
      syncStatus: SyncStatus.uploading,
    );
    _refreshItemsUi(item.anchorId);

    try {
      final file = File(item.content);

      // If the local file is missing, nothing to upload
      if (!await file.exists()) {
        await AppDatabase.instance.updateItemSync(
          item.id,
          syncStatus: SyncStatus.synced,
        );
        _refreshItemsUi(item.anchorId);
        return;
      }

      final result = await CloudinaryService.instance.upload(
        file,
        item.type,
        uid,
        item.id,
      );

      final thumbUrl =
          CloudinaryService.instance.thumbnailUrl(result.publicId, item.type);

      await AppDatabase.instance.updateItemSync(
        item.id,
        syncStatus: SyncStatus.synced,
        cloudinaryUrl: result.secureUrl,
        cloudinaryPublicId: result.publicId,
        thumbnailUrl: thumbUrl,
      );

      // Update Firestore with the CDN URLs so the image survives reinstalls.
      final synced = await AppDatabase.instance.getItemById(item.id);
      if (synced != null) {
        FirestoreService.instance.saveItem(uid, synced);
      }
    } catch (_) {
      await AppDatabase.instance.incrementRetryCount(item.id);
      // If we've hit the retry cap, mark failed; else leave as pending for
      // the next sync pass.
      final updated = await AppDatabase.instance.getItemById(item.id);
      if (updated != null && updated.retryCount >= 3) {
        await AppDatabase.instance.updateItemSync(
          item.id,
          syncStatus: SyncStatus.failed,
        );
      } else {
        await AppDatabase.instance.updateItemSync(
          item.id,
          syncStatus: SyncStatus.pending,
        );
      }
    }

    _refreshItemsUi(item.anchorId);
  }

  void _refreshItemsUi(String anchorId) {
    // Invalidate the items provider so any open detail screen refreshes
    ref.invalidate(anchorItemsProvider(anchorId));
    // Also refresh the home screen preview strip (picks up new thumbnailUrl)
    ref.invalidate(anchorPreviewProvider(anchorId));
  }

  Future<SyncSummary> _computeSummary() async {
    final pending = await AppDatabase.instance.getPendingItems();
    return SyncSummary(pending: pending.length);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final cloudinarySyncProvider =
    AsyncNotifierProvider<CloudinarySyncNotifier, SyncSummary>(
  CloudinarySyncNotifier.new,
);
