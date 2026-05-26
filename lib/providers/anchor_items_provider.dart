import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database.dart';
import '../models/anchor_item_model.dart';
import 'anchors_provider.dart';

class AnchorItemsNotifier
    extends FamilyAsyncNotifier<List<AnchorItemModel>, String> {
  @override
  Future<List<AnchorItemModel>> build(String anchorId) =>
      AppDatabase.instance.getItems(anchorId);

  Future<void> remove(String itemId) async {
    await AppDatabase.instance.deleteItem(itemId);
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
