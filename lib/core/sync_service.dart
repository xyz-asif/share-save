import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  // Max concurrent Cloudinary uploads — keeps memory + bandwidth sane on mobile.
  static const _maxConcurrent = 3;

  @override
  Future<SyncSummary> build() async {
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final wasOnline = prev?.valueOrNull ?? false;
      final isOnline = next.valueOrNull ?? false;
      if (isOnline && !wasOnline) syncPending();
    });

    Future.microtask(syncPending);

    return _computeSummary();
  }

  // ── Public API ───────────────────────────────────────────────────────────

  Future<void> syncPending() async {
    if (_running) return;

    final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
    if (!isOnline) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _running = true;
    final touchedAnchors = <String>{};
    try {
      final items = await AppDatabase.instance.getPendingItems();
      if (items.isEmpty) {
        state = const AsyncData(SyncSummary.empty);
        return;
      }

      state = AsyncData(SyncSummary(pending: items.length));

      // Upload in parallel batches — faster than sequential, bounded to
      // avoid saturating mobile connections or OOM on large queues.
      for (var i = 0; i < items.length; i += _maxConcurrent) {
        final batch = items.skip(i).take(_maxConcurrent).toList();
        await Future.wait(batch.map((item) async {
          await _uploadItem(item, user.uid);
          touchedAnchors.add(item.anchorId);
        }));
        // Emit progress after each batch so the UI stays responsive.
        state = AsyncData(await _computeSummary());
      }

      state = AsyncData(await _computeSummary());
    } finally {
      _running = false;
      for (final anchorId in touchedAnchors) {
        ref.invalidate(anchorItemsProvider(anchorId));
        ref.invalidate(anchorPreviewProvider(anchorId));
      }
    }
  }

  /// Reset all permanently-failed items to pending and re-run the upload loop.
  Future<void> retryFailed() async {
    await AppDatabase.instance.resetFailedItems();
    state = AsyncData(await _computeSummary());
    await syncPending();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _uploadItem(AnchorItemModel item, String uid) async {
    await AppDatabase.instance.updateItemSync(
      item.id,
      syncStatus: SyncStatus.uploading,
    );

    try {
      final file = File(item.content);

      if (!await file.exists()) {
        await AppDatabase.instance.updateItemSync(
          item.id,
          syncStatus: SyncStatus.failed,
        );
        return;
      }

      final result = await CloudinaryService.instance.upload(
        file,
        item.type,
        uid,
        item.id,
      );

      final thumbUrl = CloudinaryService.instance
          .thumbnailUrl(result.publicId, item.type, mimeType: item.mimeType);

      await AppDatabase.instance.updateItemSync(
        item.id,
        syncStatus: SyncStatus.synced,
        cloudinaryUrl: result.secureUrl,
        cloudinaryPublicId: result.publicId,
        thumbnailUrl: thumbUrl,
        width: result.width,
        height: result.height,
      );

      final synced = await AppDatabase.instance.getItemById(item.id);
      if (synced != null) {
        unawaited(
          FirestoreService.instance.saveItem(uid, synced).catchError((e) {
            debugPrint('Firestore saveItem failed: $e');
          }),
        );
      }
    } catch (_) {
      await AppDatabase.instance.incrementRetryCount(item.id);
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
  }

  Future<SyncSummary> _computeSummary() async {
    final counts = await AppDatabase.instance.getSyncCounts();
    return SyncSummary(
      pending: counts['pending'] ?? 0,
      uploading: counts['uploading'] ?? 0,
      failed: counts['failed'] ?? 0,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final cloudinarySyncProvider =
    AsyncNotifierProvider<CloudinarySyncNotifier, SyncSummary>(
  CloudinarySyncNotifier.new,
);
