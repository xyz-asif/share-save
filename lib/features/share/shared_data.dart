import '../../models/anchor_item_model.dart';

class SharedData {
  final ItemType type;
  final String? text;
  final String? subject;
  final List<String> uris;
  final String? mimeType;

  SharedData({
    required this.type,
    this.text,
    this.subject,
    this.uris = const [],
    this.mimeType,
  });

  factory SharedData.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'file';
    final type = ItemTypeExt.fromString(typeStr);
    final rawUris = map['uris'];
    final uris = rawUris is List
        ? rawUris.whereType<String>().toList()
        : <String>[];
    return SharedData(
      type: type,
      text: map['text'] as String?,
      subject: map['subject'] as String?,
      uris: uris,
      mimeType: map['mimeType'] as String?,
    );
  }

  String get displayContent => text ?? uris.firstOrNull ?? '';
  bool get hasMultiple => uris.length > 1;
}
