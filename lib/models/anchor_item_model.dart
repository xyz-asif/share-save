enum ItemType { link, image, video, audio, file, text }

extension ItemTypeExt on ItemType {
  String get value => name;
  static ItemType fromString(String s) =>
      ItemType.values.firstWhere((e) => e.name == s, orElse: () => ItemType.file);
}

/// Tracks whether a media item has been uploaded to Cloudinary.
/// Links and text are always [na] — they don't get uploaded.
enum SyncStatus { na, pending, uploading, synced, failed }

extension SyncStatusExt on SyncStatus {
  String get value => name;
  static SyncStatus fromString(String s) =>
      SyncStatus.values.firstWhere((e) => e.name == s,
          orElse: () => SyncStatus.pending);
}

class AnchorItemModel {
  final String id;
  final String anchorId;
  final ItemType type;
  final String? title;
  final String? description;

  /// For links/text: the URL or text content (unchanged).
  /// For media: local file path until synced, then kept as local cache.
  final String content;

  /// Local thumbnail file path (generated at save time for video, etc.).
  final String? thumbnailPath;
  final String? originalFilename;
  final String? mimeType;
  final DateTime createdAt;

  // ── Cloudinary fields ─────────────────────────────────────────
  final SyncStatus syncStatus;

  /// Full CDN URL of the uploaded asset (null until synced).
  final String? cloudinaryUrl;

  /// Cloudinary public_id, used to build transformation URLs.
  final String? cloudinaryPublicId;

  /// CDN thumbnail URL (resized/poster-frame). Preferred for card display.
  final String? thumbnailUrl;

  /// Number of upload attempts (capped at 3, then marked failed).
  final int retryCount;

  /// Image pixel dimensions — stored at upload/save time to avoid stream resolving.
  final int? width;
  final int? height;

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
    this.syncStatus = SyncStatus.na,
    this.cloudinaryUrl,
    this.cloudinaryPublicId,
    this.thumbnailUrl,
    this.retryCount = 0,
    this.width,
    this.height,
  });

  // ── Convenience getters ───────────────────────────────────────

  /// True for media types that live on disk and can be uploaded.
  bool get isLocal =>
      type == ItemType.image ||
      type == ItemType.video ||
      type == ItemType.audio ||
      type == ItemType.file;

  bool get isSynced => syncStatus == SyncStatus.synced;
  bool get needsSync =>
      syncStatus == SyncStatus.pending || syncStatus == SyncStatus.failed;

  /// Best URL for full-resolution display: CDN first, then local/original.
  String get displayUrl => cloudinaryUrl ?? content;

  /// Best thumbnail: CDN thumb → local thumbnail path → null.
  String? get displayThumbnail => thumbnailUrl ?? thumbnailPath;

  /// Stored aspect ratio (width / height). Null if dimensions unknown.
  double? get aspectRatio =>
      (width != null && height != null && height! > 0)
          ? width! / height!
          : null;

  // ── Serialisation ─────────────────────────────────────────────

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
        'sync_status': syncStatus.value,
        'cloudinary_url': cloudinaryUrl,
        'cloudinary_public_id': cloudinaryPublicId,
        'thumbnail_url': thumbnailUrl,
        'retry_count': retryCount,
        'width': width,
        'height': height,
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
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        syncStatus: SyncStatusExt.fromString(
            map['sync_status'] as String? ?? 'pending'),
        cloudinaryUrl: map['cloudinary_url'] as String?,
        cloudinaryPublicId: map['cloudinary_public_id'] as String?,
        thumbnailUrl: map['thumbnail_url'] as String?,
        retryCount: map['retry_count'] as int? ?? 0,
        width: map['width'] as int?,
        height: map['height'] as int?,
      );

  AnchorItemModel copyWith({
    SyncStatus? syncStatus,
    String? cloudinaryUrl,
    String? cloudinaryPublicId,
    String? thumbnailUrl,
    int? retryCount,
    int? width,
    int? height,
  }) =>
      AnchorItemModel(
        id: id,
        anchorId: anchorId,
        type: type,
        title: title,
        description: description,
        content: content,
        thumbnailPath: thumbnailPath,
        originalFilename: originalFilename,
        mimeType: mimeType,
        createdAt: createdAt,
        syncStatus: syncStatus ?? this.syncStatus,
        cloudinaryUrl: cloudinaryUrl ?? this.cloudinaryUrl,
        cloudinaryPublicId: cloudinaryPublicId ?? this.cloudinaryPublicId,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        retryCount: retryCount ?? this.retryCount,
        width: width ?? this.width,
        height: height ?? this.height,
      );
}
