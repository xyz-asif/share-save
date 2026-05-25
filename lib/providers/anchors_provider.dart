import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../models/anchor_item_model.dart';
import '../models/anchor_model.dart';

class AnchorsNotifier extends AsyncNotifier<List<AnchorModel>> {
  @override
  Future<List<AnchorModel>> build() => AppDatabase.instance.getAnchors();

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
    ref.invalidateSelf();
    return anchor;
  }

  Future<void> remove(String id) async {
    await AppDatabase.instance.deleteAnchor(id);
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

/// Up to 3 preview items (images first) for a card thumbnail strip.
final anchorPreviewProvider =
    FutureProvider.family<List<AnchorItemModel>, String>((ref, anchorId) {
  return AppDatabase.instance.getPreviewItems(anchorId, limit: 4);
});
