import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/anchor_item_model.dart';

// ── Result ────────────────────────────────────────────────────────────────────

class CloudinaryResult {
  final String publicId;
  final String secureUrl;
  final String resourceType;

  const CloudinaryResult({
    required this.publicId,
    required this.secureUrl,
    required this.resourceType,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class CloudinaryService {
  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  static const _cloudName = 'dxxbsstzr';
  static const _uploadPreset = 'tdwy09v9';
  static const _baseApi = 'https://api.cloudinary.com/v1_1/$_cloudName';
  static const _baseCdn = 'https://res.cloudinary.com/$_cloudName';

  // ── Upload ──────────────────────────────────────────────────────────────

  /// Upload a local [file] to Cloudinary.
  ///
  /// [uid]    – Firebase UID (used as folder prefix).
  /// [itemId] – The item's UUID (used as the public_id leaf).
  Future<CloudinaryResult> upload(
    File file,
    ItemType type,
    String uid,
    String itemId,
  ) async {
    final resourceType = _resourceType(type);
    final publicId = 'anchors/$uid/$itemId';
    final uri = Uri.parse('$_baseApi/$resourceType/upload');

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['public_id'] = publicId
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send().timeout(const Duration(minutes: 5));
    final body = json.decode(await streamed.stream.bytesToString())
        as Map<String, dynamic>;

    if (streamed.statusCode != 200) {
      final msg = (body['error'] as Map?)?['message'] ?? 'Upload failed';
      throw Exception('Cloudinary: $msg');
    }

    return CloudinaryResult(
      publicId: body['public_id'] as String,
      secureUrl: body['secure_url'] as String,
      resourceType: resourceType,
    );
  }

  // ── URL builders ────────────────────────────────────────────────────────

  /// Card thumbnail URL — square crop so it works with any card aspect ratio
  /// (portrait detail cards OR landscape home-screen preview slots).
  /// Uses c_fill + g_auto so Cloudinary keeps the region of interest centred.
  String thumbnailUrl(String publicId, ItemType type) {
    switch (type) {
      case ItemType.image:
        return '$_baseCdn/image/upload'
            '/c_fill,w_400,h_400,g_auto,f_auto,q_auto'
            '/$publicId';

      case ItemType.video:
        // Poster frame at 1 second in, square crop
        return '$_baseCdn/video/upload'
            '/so_1.0,c_fill,w_400,h_400,f_jpg,q_auto'
            '/$publicId.jpg';

      default:
        // PDF / raw: try page-1 image preview, square
        return '$_baseCdn/image/upload'
            '/pg_1,c_fill,w_400,h_400,f_jpg,q_auto'
            '/$publicId.jpg';
    }
  }

  /// Full CDN URL for the uploaded asset (no transformations).
  /// Images get auto-format and quality for best delivery.
  String fullUrl(String publicId, ItemType type) {
    if (type == ItemType.image) {
      return '$_baseCdn/image/upload/f_auto,q_auto/$publicId';
    }
    if (type == ItemType.video) {
      return '$_baseCdn/video/upload/$publicId';
    }
    return '$_baseCdn/raw/upload/$publicId';
  }

  /// Deliver a remote OG image through the Cloudinary Fetch CDN.
  /// This gives us CDN caching, auto-format, and resizing on any external URL.
  String fetchImageUrl(String remoteUrl) {
    final encoded = Uri.encodeComponent(remoteUrl);
    return '$_baseCdn/image/fetch'
        '/c_fill,w_480,h_252,f_auto,q_auto'
        '/$encoded';
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _resourceType(ItemType type) => switch (type) {
        ItemType.image => 'image',
        ItemType.video => 'video',
        _ => 'raw',
      };
}
