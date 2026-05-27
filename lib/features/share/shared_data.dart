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
    var type = ItemTypeExt.fromString(typeStr);
    final text = map['text'] as String?;
    final rawUris = map['uris'];
    final uris = rawUris is List
        ? rawUris.whereType<String>().toList()
        : <String>[];

    // Dart-side safety net: if Android sent 'text' but the payload is a plain
    // URL (no spaces → it really is just a URL), promote it to 'link' so the
    // share sheet shows the link preview flow and saves it with the right type.
    if (type == ItemType.text && text != null) {
      final t = text.trim();
      if ((t.startsWith('http://') || t.startsWith('https://')) &&
          !t.contains(' ')) {
        type = ItemType.link;
      }
    }

    return SharedData(
      type: type,
      text: text,
      subject: map['subject'] as String?,
      uris: uris,
      mimeType: map['mimeType'] as String?,
    );
  }

  String get displayContent => text ?? uris.firstOrNull ?? '';
  bool get hasMultiple => uris.length > 1;
}
