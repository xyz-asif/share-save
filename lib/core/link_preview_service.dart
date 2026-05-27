import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'cloudinary_service.dart';
import 'database.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

/// Auto-dispose so unused previews don't stay in memory.
/// Returns null while loading or if scraping fails.
final linkPreviewProvider =
    FutureProvider.autoDispose.family<LinkPreviewData?, String>((ref, url) {
  return LinkPreviewService.instance.getPreview(url);
});

// ── Service ───────────────────────────────────────────────────────────────────

class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  // Re-fetch if cached data is older than this
  static const _cacheTtl = Duration(days: 7);

  Future<LinkPreviewData?> getPreview(String url) async {
    // 1. Return from DB cache if still fresh
    final cached = await AppDatabase.instance.getLinkPreview(url);
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached;
    }

    // 2. Fetch + parse
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

      final data = _parse(response.body, url);

      // 3. Persist to cache (replace stale entry)
      await AppDatabase.instance.saveLinkPreview(data);
      return data;
    } catch (_) {
      // Network / parse error — return stale cache rather than nothing
      return cached;
    }
  }

  // ── OG / meta tag parser ────────────────────────────────────────────────

  LinkPreviewData _parse(String html, String url) {
    // Match <meta property="og:*" content="..."> in either attribute order
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

    // Fallback: <title> tag
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

  // ── HTML entity decoder (handles &amp; &quot; etc.) ─────────────────────

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

// ── Extension helper ──────────────────────────────────────────────────────────

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

// ── Convenience extension on LinkPreviewData ──────────────────────────────────

extension LinkPreviewDataExt on LinkPreviewData {
  /// OG image delivered through the Cloudinary Fetch CDN.
  /// Returns null if there's no OG image.
  String? get cdnImageUrl {
    final raw = imageUrl;
    if (raw == null || raw.isEmpty) return null;
    return CloudinaryService.instance.fetchImageUrl(raw);
  }
}
