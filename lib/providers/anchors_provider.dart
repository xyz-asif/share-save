import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../core/firestore_service.dart';
import '../models/anchor_item_model.dart';
import '../models/anchor_model.dart';

class AnchorsNotifier extends AsyncNotifier<List<AnchorModel>> {
  @override
  Future<List<AnchorModel>> build() async {
    final localAnchors = await AppDatabase.instance.getAnchors();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null && localAnchors.isEmpty) {
      // Fresh install / reinstall — local DB is empty.
      // Run Firestore restore in the background so build() returns immediately.
      // Awaiting it here caused a 40-second UI freeze: Firestore reads are slow
      // on devices where GMS has connectivity issues (confirmed in logcat), and
      // the sequential loop made it N anchors × ~8s = 40s with the UI stuck.
      _syncFromFirestoreAndRefresh(uid);
    }

    // Return immediately — shows empty state briefly, then anchors appear
    // once the background sync writes to the DB and updates state directly.
    return localAnchors;
  }

  /// Background Firestore restore: syncs data, then pushes the result into
  /// state directly (no ref.invalidateSelf — that caused an infinite loop).
  Future<void> _syncFromFirestoreAndRefresh(String uid) async {
    await _syncFromFirestore(uid);
    final restored = await AppDatabase.instance.getAnchors();
    if (restored.isNotEmpty) {
      state = AsyncData(restored);
    }
  }

  /// Pull anchors and their items from Firestore into the local DB.
  ///
  /// Key fix: all per-anchor item fetches run in parallel via Future.wait.
  /// Previously they ran sequentially (for + await), which multiplied the
  /// network latency by the number of anchors.
  Future<void> _syncFromFirestore(String uid) async {
    try {
      final remoteAnchors = await FirestoreService.instance.getAnchors(uid);

      // Write anchors to local DB first (items reference them via FK).
      for (final anchor in remoteAnchors) {
        await AppDatabase.instance.upsertAnchor(anchor);
      }

      // Fetch items for ALL anchors simultaneously instead of one-by-one.
      // Before: N anchors × ~8s/call = 40s.  After: max(8s) ≈ 8s regardless of N.
      await Future.wait(
        remoteAnchors.map((anchor) async {
          final remoteItems =
              await FirestoreService.instance.getItems(uid, anchor.id);
          for (final item in remoteItems) {
            await AppDatabase.instance.upsertItem(item);
          }
        }),
      );
    } catch (_) {
      // Network failures are non-fatal; local data (empty) is still shown.
    }
  }

  Future<AnchorModel> add({
    required String name,
    String? description,
    required int colorValue,
  }) async {
    final anchor = await AppDatabase.instance.createAnchor(
      name: name,
      description: description,
      colorValue: colorValue,
    );

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService.instance.saveAnchor(uid, anchor);
    }

    state = AsyncData([anchor, ...(state.valueOrNull ?? [])]);
    return anchor;
  }

  Future<void> remove(String id) async {
    await AppDatabase.instance.deleteAnchor(id);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService.instance.deleteAnchor(uid, id);
    }

    state = AsyncData(
      (state.valueOrNull ?? []).where((a) => a.id != id).toList(),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final anchorsProvider =
    AsyncNotifierProvider<AnchorsNotifier, List<AnchorModel>>(
        AnchorsNotifier.new);

/// Up to 4 preview items for a card thumbnail strip.
final anchorPreviewProvider =
    FutureProvider.family<List<AnchorItemModel>, String>((ref, anchorId) {
  return AppDatabase.instance.getPreviewItems(anchorId, limit: 4);
});
