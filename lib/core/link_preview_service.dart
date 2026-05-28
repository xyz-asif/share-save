import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'cloudinary_service.dart';
import 'database.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

/// Auto-dispose so unused previews don't stay in memory.
final linkPreviewProvider =
    FutureProvider.autoDispose.family<LinkPreviewData?, String>((ref, url) {
  return LinkPreviewService.instance.getPreview(url);
});

// ── Top-level isolate entry point ─────────────────────────────────────────────

// Must be top-level for compute().
LinkPreviewData _parseInIsolate(({String html, String url}) input) {
  return LinkPreviewService._parseStatic(input.html, input.url);
}

// ── Service ───────────────────────────────────────────────────────────────────

class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  static const _cacheTtl = Duration(days: 7);

  Future<LinkPreviewData?> getPreview(String url) async {
    final cached = await AppDatabase.instance.getLinkPreview(url);
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached;
    }

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (compatible; AnchorBot/1.0; +https://anchors.app)',
              'Accept': 'text/html',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return cached;

      // Cap at 500 KB to bound regex backtracking time.
      final body = response.body.length > 500 * 1024
          ? response.body.substring(0, 500 * 1024)
          : response.body;

      // Parse on a background isolate — heavy regex on large pages blocks the UI.
      final data = await compute(_parseInIsolate, (html: body, url: url));

      await AppDatabase.instance.saveLinkPreview(data);
      return data;
    } catch (_) {
      return cached;
    }
  }

  // ── OG / meta tag parser ────────────────────────────────────────────────

  static LinkPreviewData _parseStatic(String html, String url) {
    String? ogProperty(String property) {
      final re = RegExp(
        r'''(?:property|name)=["\']''' +
            RegExp.escape(property) +
            r'''["\'][^>]*?content=["\'](.*?)["\']|''' +
            r'''content=["\'](.*?)["\'][^>]*?(?:property|name)=["\']''' +
            RegExp.escape(property) +
            r'''["\']''',
        caseSensitive: false,
        dotAll: true,
      );
      final m = re.firstMatch(html);
      return (m?.group(1) ?? m?.group(2))?.trim().nullIfEmpty;
    }

    String? htmlTitle() {
      final m = RegExp(r'<title[^>]*>(.*?)</title>',
              caseSensitive: false, dotAll: true)
          .firstMatch(html);
      return _decodeHtml(m?.group(1)?.trim())?.nullIfEmpty;
    }

    final rawImageUrl = ogProperty('og:image') ?? ogProperty('twitter:image');
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';

    return LinkPreviewData(
      url: url,
      title: _decodeHtml(
          ogProperty('og:title') ?? ogProperty('twitter:title') ?? htmlTitle()),
      description: _decodeHtml(
          ogProperty('og:description') ?? ogProperty('description')),
      imageUrl: rawImageUrl,
      siteName: ogProperty('og:site_name') ?? host,
      fetchedAt: DateTime.now(),
    );
  }

  static String? _decodeHtml(String? s) {
    if (s == null) return null;
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }
}

// ── Extension helpers ─────────────────────────────────────────────────────────

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

extension LinkPreviewDataExt on LinkPreviewData {
  String? get cdnImageUrl {
    final raw = imageUrl;
    if (raw == null || raw.isEmpty) return null;
    return CloudinaryService.instance.fetchImageUrl(raw);
  }
}
