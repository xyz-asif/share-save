enum ItemType { link, image, video, audio, file, text }

extension ItemTypeExt on ItemType {
  String get value => name;
  static ItemType fromString(String s) =>
      ItemType.values.firstWhere((e) => e.name == s, orElse: () => ItemType.file);
}

class AnchorItemModel {
  final String id;
  final String anchorId;
  final ItemType type;
  final String? title;
  final String? description;
  final String content; // URL or local file path
  final String? thumbnailPath;
  final String? originalFilename;
  final String? mimeType;
  final DateTime createdAt;

  AnchorItemModel({
    required this.id,
    required this.anchorId,
    required this.type,
    this.title,
    this.description,
    required this.content,
    this.thumbnailPath,
    this.originalFilename,
    this.mimeType,
    required this.createdAt,
  });

  bool get isLocal =>
      type == ItemType.image || type == ItemType.video ||
      type == ItemType.audio || type == ItemType.file;

  Map<String, dynamic> toMap() => {
    'id': id,
    'anchor_id': anchorId,
    'type': type.value,
    'title': title,
    'description': description,
    'content': content,
    'thumbnail_path': thumbnailPath,
    'original_filename': originalFilename,
    'mime_type': mimeType,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory AnchorItemModel.fromMap(Map<String, dynamic> map) => AnchorItemModel(
    id: map['id'] as String,
    anchorId: map['anchor_id'] as String,
    type: ItemTypeExt.fromString(map['type'] as String),
    title: map['title'] as String?,
    description: map['description'] as String?,
    content: map['content'] as String,
    thumbnailPath: map['thumbnail_path'] as String?,
    originalFilename: map['original_filename'] as String?,
    mimeType: map['mime_type'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );
}
