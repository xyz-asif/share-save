import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../core/firestore_service.dart';
import '../models/anchor_item_model.dart';
import '../models/anchor_model.dart';

class AnchorsNotifier extends AsyncNotifier<List<AnchorModel>> {
  bool _restoreInFlight = false;
  bool _disposed = false;
  bool _disposeHookInstalled = false;

  @override
  Future<List<AnchorModel>> build() async {
    if (!_disposeHookInstalled) {
      _disposeHookInstalled = true;
      ref.onDispose(() => _disposed = true);
    }

    final localAnchors = await AppDatabase.instance.getAnchors();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null && localAnchors.isEmpty && !_restoreInFlight) {
      _restoreInFlight = true;
      _syncFromFirestoreAndRefresh(uid).whenComplete(() {
        _restoreInFlight = false;
      });
    }

    return localAnchors;
  }

  Future<void> _syncFromFirestoreAndRefresh(String uid) async {
    await _syncFromFirestore(uid);
    if (_disposed) return;
    final restored = await AppDatabase.instance.getAnchors();
    if (_disposed) return;
    if (restored.isNotEmpty) {
      state = AsyncData(restored);
    }
  }

  /// Fetch all anchors + items from Firestore and batch-write in one transaction.
  Future<void> _syncFromFirestore(String uid) async {
    try {
      final remoteAnchors = await FirestoreService.instance.getAnchors(uid);

      // Fetch items for all anchors in parallel (network — no DB contention here).
      final itemsByAnchor = <String, List<AnchorItemModel>>{};
      await Future.wait(remoteAnchors.map((anchor) async {
        final items = await FirestoreService.instance.getItems(uid, anchor.id);
        itemsByAnchor[anchor.id] = items;
      }));

      // Single transaction for all writes — 10–50× faster than per-item inserts.
      await AppDatabase.instance
          .upsertAnchorsAndItems(remoteAnchors, itemsByAnchor);
    } catch (_) {
      // Non-fatal — local data (empty) is still shown.
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
      unawaited(
        FirestoreService.instance.saveAnchor(uid, anchor).catchError((e) {
          debugPrint('Firestore saveAnchor failed: $e');
        }),
      );
    }

    state = AsyncData([anchor, ...(state.valueOrNull ?? [])]);
    return anchor;
  }

  Future<void> remove(String id) async {
    await AppDatabase.instance.deleteAnchor(id);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      unawaited(
        FirestoreService.instance.deleteAnchor(uid, id).catchError((e) {
          debugPrint('Firestore deleteAnchor failed: $e');
        }),
      );
    }

    state = AsyncData(
      (state.valueOrNull ?? []).where((a) => a.id != id).toList(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
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
