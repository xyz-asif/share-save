import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/cloudinary_service.dart';
import '../../core/link_preview_service.dart';
import '../../core/theme.dart';
import '../../models/anchor_item_model.dart';
import '../../models/anchor_model.dart';
import '../../providers/anchor_items_provider.dart';
import '../../providers/anchors_provider.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class AnchorDetailScreen extends ConsumerStatefulWidget {
  final AnchorModel anchor;
  const AnchorDetailScreen({super.key, required this.anchor});

  @override
  ConsumerState<AnchorDetailScreen> createState() => _AnchorDetailScreenState();
}

class _AnchorDetailScreenState extends ConsumerState<AnchorDetailScreen>
    with SingleTickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  late final AnimationController _animCtrl;
  late final Animation<double> _appBarFade;
  late final Animation<Offset> _appBarSlide;
  String? _jigglingItemId;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    Future.delayed(const Duration(milliseconds: 330), () {
      if (mounted) _animCtrl.forward();
    });
    _appBarFade = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _appBarSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    ));
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.anchor;
    final itemsAsync = ref.watch(anchorItemsProvider(anchor.id));

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: _buildFab(anchor),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: () =>
            ref.read(anchorItemsProvider(anchor.id).notifier).refresh(),
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            _buildAppBar(anchor),
            itemsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(
                  child: Text('$e',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14.sp)),
                ),
              ),
              data: (items) => items.isEmpty
                  ? _buildEmpty(anchor)
                  : _buildGrid(items, anchor),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(AnchorModel anchor) {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      toolbarHeight: 56.h,
      automaticallyImplyLeading: false,
      leadingWidth: 60.w,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: Container(
            width: 36.r,
            height: 36.r,
            margin: EdgeInsets.only(left: 16.w),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Color(0x0C000000),
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.textPrimary, size: 14.sp),
          ),
        ),
      ),
      title: FadeTransition(
        opacity: _appBarFade,
        child: SlideTransition(
          position: _appBarSlide,
          child: Text(
            anchor.name,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      actions: [
        GestureDetector(
          onTap: () => _confirmDeleteAnchor(context),
          child: Container(
            width: 36.r,
            height: 36.r,
            margin: EdgeInsets.only(right: 16.w),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.delete_outline_rounded,
                color: AppColors.danger, size: 17.sp),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(1.h),
        child: Container(height: 1.h, color: AppColors.divider),
      ),
    );
  }

  // ── Empty ───────────────────────────────────────────────────────────────────

  Widget _buildEmpty(AnchorModel anchor) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76.r,
              height: 76.r,
              decoration: BoxDecoration(
                color: anchor.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: anchor.color.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Icon(Icons.inbox_rounded, size: 34.sp, color: anchor.color),
            ),
            SizedBox(height: 16.h),
            Text('Nothing saved yet',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            Text('Share content here from any app',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13.sp)),
          ],
        ),
      ),
    );
  }

  // ── Grid ────────────────────────────────────────────────────────────────────

  Widget _buildGrid(List<AnchorItemModel> items, AnchorModel anchor) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 100.h),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10.h,
        crossAxisSpacing: 10.w,
        childCount: items.length,
        itemBuilder: (ctx, i) {
          final start = (i * 0.07).clamp(0.0, 0.65);
          final end = (start + 0.35).clamp(0.0, 1.0);
          final anim = CurvedAnimation(
            parent: _animCtrl,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(anim),
              child: _ItemCard(
                key: ValueKey(items[i].id),
                item: items[i],
                anchorColor: anchor.color,
                isJiggling: _jigglingItemId == items[i].id,
                onTap: () => _openItem(ctx, items[i]),
                onLongPress: () => _onItemLongPress(items[i], anchor),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _openItem(BuildContext context, AnchorItemModel item) async {
    HapticFeedback.selectionClick();
    switch (item.type) {
      case ItemType.link:
        final uri = Uri.tryParse(item.content);
        if (uri != null) {
          try {
            final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open link')),
              );
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open link')),
              );
            }
          }
        }
      case ItemType.image:
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => _ImagePreviewScreen(item: item),
            transitionDuration: const Duration(milliseconds: 280),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      case ItemType.text:
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24.r))),
          builder: (_) => _TextPreviewSheet(item: item),
        );
      case ItemType.video:
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => _VideoPlayerScreen(item: item),
            transitionDuration: const Duration(milliseconds: 280),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      case ItemType.audio:
        if (!context.mounted) return;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _AudioPlayerSheet(item: item),
        );
      case ItemType.file:
        if (!context.mounted) return;
        final isPdf = (item.mimeType?.contains('pdf') ?? false) ||
            (item.originalFilename?.toLowerCase().endsWith('.pdf') ?? false) ||
            item.content.toLowerCase().endsWith('.pdf');
        if (isPdf) {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => _PdfViewerScreen(item: item),
              transitionDuration: const Duration(milliseconds: 280),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
            ),
          );
        } else {
          showModalBottomSheet(
            context: context,
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24.r))),
            builder: (_) => _FilePreviewSheet(item: item),
          );
        }
    }
  }

  Future<void> _onItemLongPress(AnchorItemModel item, AnchorModel anchor) async {
    HapticFeedback.mediumImpact();
    setState(() => _jigglingItemId = item.id);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeleteItemSheet(),
    );
    setState(() => _jigglingItemId = null);
    if (confirmed == true) {
      ref.read(anchorItemsProvider(anchor.id).notifier).remove(item.id);
    }
  }

  Future<void> _confirmDeleteAnchor(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final anchor = widget.anchor;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeleteAnchorSheet(anchor: anchor),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(anchorsProvider.notifier).remove(anchor.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  Widget _buildFab(AnchorModel anchor) {
    return FloatingActionButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AddItemSheet(
            anchorId: anchor.id,
            anchorColor: anchor.color,
          ),
        );
      },
      backgroundColor: anchor.color,
      foregroundColor: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: const Icon(Icons.add_rounded, size: 26),
    );
  }
}

// ─── Item card ────────────────────────────────────────────────────────────────

class _ItemCard extends StatefulWidget {
  final AnchorItemModel item;
  final Color anchorColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isJiggling;

  const _ItemCard({
    super.key,
    required this.item,
    required this.anchorColor,
    required this.onTap,
    required this.onLongPress,
    required this.isJiggling,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _jiggleCtrl;
  late final Animation<double> _jiggleAnim;

  @override
  void initState() {
    super.initState();
    _jiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _jiggleAnim = Tween<double>(begin: -0.04, end: 0.04).animate(
      CurvedAnimation(parent: _jiggleCtrl, curve: Curves.easeInOut),
    );
  }

  /// True when [content] is a bare URL with no surrounding text.
  static bool _looksLikeUrl(String content) {
    final t = content.trim();
    return (t.startsWith('http://') || t.startsWith('https://')) &&
        !t.contains(' ');
  }

  @override
  void didUpdateWidget(_ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isJiggling && !oldWidget.isJiggling) {
      _jiggleCtrl.repeat(reverse: true);
    } else if (!widget.isJiggling && oldWidget.isJiggling) {
      _jiggleCtrl.stop();
      _jiggleCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _jiggleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _jiggleAnim,
      builder: (context, child) => Transform.rotate(
        angle: widget.isJiggling ? _jiggleAnim.value : 0,
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x07000000),
                  blurRadius: 8,
                  offset: Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: switch (widget.item.type) {
            ItemType.image => _ImageContent(item: widget.item),
            ItemType.link => _LinkContent(item: widget.item, accentColor: widget.anchorColor),
            // Items saved before link-detection was added may be typed as 'text'
            // even though their content is a URL.  Detect that at render time so
            // they get the link-preview card without any DB migration.
            ItemType.text when _looksLikeUrl(widget.item.content) =>
              _LinkContent(item: widget.item, accentColor: widget.anchorColor),
            ItemType.text => _TextContent(item: widget.item, accentColor: widget.anchorColor),
            ItemType.video => _MediaContent(
                item: widget.item,
                icon: Icons.videocam_rounded,
                color: const Color(0xFFFF9500)),
            ItemType.audio => _MediaContent(
                item: widget.item,
                icon: Icons.audiotrack_rounded,
                color: const Color(0xFFE91E8C)),
            ItemType.file => _MediaContent(
                item: widget.item,
                icon: Icons.insert_drive_file_rounded,
                color: widget.anchorColor,
                accentColor: widget.anchorColor),
          },
        ),
      ),
    );
  }
}

// ─── Card content variants ────────────────────────────────────────────────────

/// Renders an image card using the stored aspect ratio (width/height from DB).
/// Never resolves an ImageStream — avoids 20× concurrent decodes on the UI isolate.
/// Falls back to a 1:1 square when dimensions are not yet stored (old items or
/// local files before first Cloudinary upload).
class _ImageContent extends StatelessWidget {
  final AnchorItemModel item;
  const _ImageContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final ratio = item.aspectRatio ?? 1.0;

    final thumbUrl = item.cloudinaryPublicId != null
        ? CloudinaryService.instance.thumbnailUrl(
            item.cloudinaryPublicId!,
            item.type,
            mimeType: item.mimeType,
          )
        : item.thumbnailUrl;
    final cdnUrl = item.cloudinaryUrl;
    final isLocalFile = !item.content.startsWith('http');

    Widget imageWidget;
    if (thumbUrl != null) {
      imageWidget = CachedNetworkImage(
        imageUrl: thumbUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(color: AppColors.bg),
        errorWidget: (_, __, ___) => _BrokenImage(height: 60.h),
      );
    } else if (cdnUrl != null) {
      imageWidget = CachedNetworkImage(
        imageUrl: cdnUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(color: AppColors.bg),
        errorWidget: (_, __, ___) => _BrokenImage(height: 60.h),
      );
    } else if (isLocalFile) {
      final file = File(item.content);
      if (!file.existsSync()) {
        imageWidget = _BrokenImage(height: 80.h);
      } else {
        imageWidget = Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          cacheWidth: 600,
          errorBuilder: (_, __, ___) => _BrokenImage(height: 80.h),
        );
      }
    } else {
      imageWidget = CachedNetworkImage(
        imageUrl: item.content,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(color: AppColors.bg),
        errorWidget: (_, __, ___) => _BrokenImage(height: 60.h),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(aspectRatio: ratio, child: imageWidget),
            if (item.syncStatus != SyncStatus.synced &&
                item.syncStatus != SyncStatus.na)
              Positioned(
                top: 6,
                right: 6,
                child: _SyncBadge(status: item.syncStatus),
              ),
          ],
        ),
        if (item.title != null)
          Padding(
            padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 10.h),
            child: Text(
              item.title!,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _LinkContent extends ConsumerWidget {
  final AnchorItemModel item;
  final Color accentColor;
  const _LinkContent({required this.item, required this.accentColor});

  String get _domain {
    try {
      return Uri.parse(item.content).host.replaceFirst('www.', '');
    } catch (_) {
      return item.content;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewAsync = ref.watch(linkPreviewProvider(item.content));
    final preview = previewAsync.valueOrNull;

    final title = item.title ?? preview?.title;
    final description = item.description ?? preview?.description;
    // Prefer Cloudinary Fetch CDN; fall back to raw OG URL if CDN unavailable
    final ogCdnImage = preview?.cdnImageUrl;
    final ogRawImage = preview?.imageUrl;
    final ogImageUrl = ogCdnImage ?? ogRawImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // OG image — CDN preferred, raw URL as fallback
        if (ogImageUrl != null)
          AspectRatio(
            aspectRatio: 1.91,
            child: CachedNetworkImage(
              imageUrl: ogImageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => Container(color: AppColors.bg),
              errorWidget: (_, __, ___) {
                // CDN failed → retry with raw URL
                if (ogImageUrl == ogCdnImage && ogRawImage != null) {
                  return Image.network(
                    ogRawImage,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        Container(height: 3.h, color: accentColor),
        Padding(
          padding: EdgeInsets.all(10.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 18.r,
                  height: 18.r,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5.r),
                  ),
                  child: Icon(Icons.link_rounded,
                      color: accentColor, size: 10.sp),
                ),
                SizedBox(width: 5.w),
                Expanded(
                  child: Text(
                    preview?.siteName ?? _domain,
                    style: TextStyle(
                        color: accentColor,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Loading indicator while fetching OG data
                if (previewAsync.isLoading)
                  SizedBox(
                    width: 8.r,
                    height: 8.r,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.2,
                      color: accentColor.withValues(alpha: 0.5),
                    ),
                  ),
              ]),
              if (title != null) ...[
                SizedBox(height: 6.h),
                Text(
                  title,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (description != null) ...[
                SizedBox(height: 4.h),
                Text(
                  description,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.sp,
                      height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              SizedBox(height: 5.h),
              Text(
                item.content,
                style:
                    TextStyle(color: AppColors.textTertiary, fontSize: 9.sp),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextContent extends StatelessWidget {
  final AnchorItemModel item;
  final Color accentColor;
  const _TextContent({required this.item, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3.w, color: accentColor),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(10.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TEXT',
                    style: TextStyle(
                        color: accentColor,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8),
                  ),
                  if (item.title != null) ...[
                    SizedBox(height: 5.h),
                    Text(
                      item.title!,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  SizedBox(height: 4.h),
                  Text(
                    item.content,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.sp,
                        height: 1.45),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaContent extends StatelessWidget {
  final AnchorItemModel item;
  final IconData icon;
  final Color color;
  final Color? accentColor;
  const _MediaContent(
      {required this.item,
      required this.icon,
      required this.color,
      this.accentColor});

  @override
  Widget build(BuildContext context) {
    // Video with a Cloudinary poster frame → show thumbnail card
    final thumbUrl = item.thumbnailUrl;
    if (item.type == ItemType.video && thumbUrl != null) {
      return _VideoPosterCard(item: item, thumbUrl: thumbUrl, color: color);
    }

    // Default: icon + title card
    final content = Padding(
      padding: EdgeInsets.all(12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32.r,
                height: 32.r,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(icon, color: color, size: 17.sp),
              ),
              const Spacer(),
              if (item.syncStatus != SyncStatus.synced &&
                  item.syncStatus != SyncStatus.na)
                _SyncBadge(status: item.syncStatus),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            item.title ?? item.originalFilename ?? 'Untitled',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                height: 1.3),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.mimeType != null) ...[
            SizedBox(height: 3.h),
            Text(
              item.mimeType!,
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 9.sp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    if (accentColor == null) return content;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3.w, color: accentColor),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Video card with a Cloudinary-generated poster frame + play overlay.
class _VideoPosterCard extends StatelessWidget {
  final AnchorItemModel item;
  final String thumbUrl;
  final Color color;
  const _VideoPosterCard(
      {required this.item, required this.thumbUrl, required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Poster frame
        AspectRatio(
          aspectRatio: 16 / 9,
          child: CachedNetworkImage(
            imageUrl: thumbUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, __) => Container(color: Colors.black87),
            errorWidget: (_, __, ___) => Container(
              color: Colors.black87,
              child: Icon(Icons.videocam_rounded,
                  color: Colors.white54, size: 28.sp),
            ),
          ),
        ),
        // Gradient scrim
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                stops: const [0.45, 1.0],
              ),
            ),
          ),
        ),
        // Play button
        Positioned.fill(
          child: Center(
            child: Container(
              width: 36.r,
              height: 36.r,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8), width: 1.5),
              ),
              child: Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 20.sp),
            ),
          ),
        ),
        // Title at the bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8.w, 0, 8.w, 8.h),
            child: Text(
              item.title ?? item.originalFilename ?? 'Video',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4)
                  ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Sync badge
        if (item.syncStatus != SyncStatus.synced &&
            item.syncStatus != SyncStatus.na)
          Positioned(
            top: 6,
            right: 6,
            child: _SyncBadge(status: item.syncStatus),
          ),
      ],
    );
  }
}

// ── Sync status badge ─────────────────────────────────────────────────────────

class _SyncBadge extends StatelessWidget {
  final SyncStatus status;
  const _SyncBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, label, tint) = switch (status) {
      SyncStatus.uploading => (null, 'Syncing', Colors.white70),
      SyncStatus.failed => (Icons.warning_amber_rounded, 'Failed', Colors.orange),
      _ => (Icons.cloud_upload_outlined, 'Local', Colors.white70),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == SyncStatus.uploading)
            SizedBox(
              width: 8.r,
              height: 8.r,
              child: const CircularProgressIndicator(
                  color: Colors.white70, strokeWidth: 1.5),
            )
          else if (icon != null)
            Icon(icon, color: tint, size: 9.sp),
          SizedBox(width: 3.w),
          Text(label,
              style: TextStyle(
                  color: tint,
                  fontSize: 8.sp,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  final double height;
  const _BrokenImage({required this.height});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        color: AppColors.bg,
        child: Icon(Icons.broken_image_rounded,
            color: AppColors.textTertiary, size: 22.sp),
      );
}

// ─── Delete sheets ────────────────────────────────────────────────────────────

class _DeleteItemSheet extends StatelessWidget {
  const _DeleteItemSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 32.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x10000000), blurRadius: 24, offset: Offset(0, -4))
        ],
      ),
      padding: EdgeInsets.all(24.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52.r,
            height: 52.r,
            decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(Icons.delete_rounded,
                color: AppColors.danger, size: 24.sp),
          ),
          SizedBox(height: 14.h),
          Text('Remove item?',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 6.h),
          Text(
            'This item will be permanently removed.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.sp,
                height: 1.5),
          ),
          SizedBox(height: 20.h),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: EdgeInsets.symmetric(vertical: 13.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                ),
                child: Text('Cancel',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14.sp)),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: EdgeInsets.symmetric(vertical: 13.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                ),
                child: Text('Remove',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14.sp)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DeleteAnchorSheet extends StatelessWidget {
  final AnchorModel anchor;
  const _DeleteAnchorSheet({required this.anchor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 32.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 24, offset: Offset(0, -4))
        ],
      ),
      padding: EdgeInsets.all(24.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56.r,
            height: 56.r,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.delete_rounded,
                color: AppColors.danger, size: 26.sp),
          ),
          SizedBox(height: 16.h),
          Text('Delete Anchor?',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 8.h),
          Text(
            '"${anchor.name}" and all its saved content will be permanently removed.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14.sp,
                height: 1.5),
          ),
          SizedBox(height: 24.h),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r)),
                ),
                child: Text('Cancel',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14.sp)),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r)),
                ),
                child: Text('Delete',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14.sp)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Preview screens ──────────────────────────────────────────────────────────

class _ImagePreviewScreen extends StatelessWidget {
  final AnchorItemModel item;
  const _ImagePreviewScreen({required this.item});

  @override
  Widget build(BuildContext context) {
    final displayUrl = item.cloudinaryUrl ?? item.content;
    final isNet = displayUrl.startsWith('http');

    if (!isNet && !File(displayUrl).existsSync()) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('Image not found',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final ImageProvider imageProvider = isNet
        ? CachedNetworkImageProvider(displayUrl)
        : FileImage(File(displayUrl));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(item.title ?? 'Image',
            style: TextStyle(color: Colors.white, fontSize: 16.sp)),
      ),
      body: PhotoView(
        imageProvider: imageProvider,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        heroAttributes: PhotoViewHeroAttributes(tag: item.id),
      ),
    );
  }
}

class _FilePreviewSheet extends StatefulWidget {
  final AnchorItemModel item;
  const _FilePreviewSheet({required this.item});

  @override
  State<_FilePreviewSheet> createState() => _FilePreviewSheetState();
}

class _FilePreviewSheetState extends State<_FilePreviewSheet> {
  String? _fileSize;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    final file = File(widget.item.content);
    if (await file.exists()) {
      final bytes = await file.length();
      if (mounted) setState(() => _fileSize = _fmt(bytes));
    }
  }

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get _ext {
    final name = widget.item.originalFilename ?? widget.item.title ?? '';
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toUpperCase() : 'FILE';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final filename = item.originalFilename ?? item.title ?? 'Document';

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 40.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2.r)),
            ),
          ),
          SizedBox(height: 28.h),
          Container(
            width: 80.r,
            height: 80.r,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.20), width: 1.2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.insert_drive_file_rounded,
                    color: AppColors.accent, size: 30.sp),
                SizedBox(height: 2.h),
                Text(
                  _ext,
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            filename,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                height: 1.3),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 6.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.mimeType != null) ...[
                Text(item.mimeType!,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.sp)),
                if (_fileSize != null)
                  Text('  ·  ',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 12.sp)),
              ],
              if (_fileSize != null)
                Text(_fileSize!,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.sp)),
            ],
          ),
          SizedBox(height: 32.h),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await OpenFilex.open(item.content);
              },
              icon: Icon(Icons.open_in_new_rounded, size: 16.sp),
              label: Text('Open',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14.sp)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPreviewSheet extends StatelessWidget {
  final AnchorItemModel item;
  const _TextPreviewSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 20.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2.r)),
              ),
            ),
            SizedBox(height: 16.h),
            if (item.title != null) ...[
              Text(item.title!,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: 12.h),
            ],
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                child: Text(item.content,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14.sp,
                        height: 1.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Item Sheet ────────────────────────────────────────────────────────────

class _AddItemSheet extends ConsumerStatefulWidget {
  final String anchorId;
  final Color anchorColor;

  const _AddItemSheet({required this.anchorId, required this.anchorColor});

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  ItemType? _inputMode;
  final _contentCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _contentCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles(ItemType type) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fileType = switch (type) {
        ItemType.image => FileType.image,
        ItemType.video => FileType.video,
        ItemType.audio => FileType.audio,
        _ => FileType.any,
      };

      final result = await FilePicker.platform.pickFiles(
        type: fileType,
        allowMultiple: true,
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;
      Navigator.pop(context);

      final notifier =
          ref.read(anchorItemsProvider(widget.anchorId).notifier);
      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;
        await notifier.addItem(
          type: type,
          content: path,
          originalFilename: f.name,
          mimeType: lookupMimeType(path),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveText() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty || _inputMode == null || _busy) return;
    setState(() => _busy = true);
    try {
      final title = _titleCtrl.text.trim();
      await ref
          .read(anchorItemsProvider(widget.anchorId).notifier)
          .addItem(
            type: _inputMode!,
            title: title.isEmpty ? null : title,
            content: content,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 16.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000),
              blurRadius: 24,
              offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, bottom + 20.h),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _inputMode != null ? _buildTextInput() : _buildTypeGrid(),
      ),
    );
  }

  Widget _buildTypeGrid() {
    return Column(
      key: const ValueKey('grid'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetHandle(),
        Text(
          'Add Item',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 20.h),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12.h,
          crossAxisSpacing: 12.w,
          childAspectRatio: 1.05,
          children: [
            _TypeTile(
              icon: Icons.image_rounded,
              label: 'Photo',
              color: const Color(0xFF4CAF50),
              onTap: _busy ? null : () => _pickFiles(ItemType.image),
            ),
            _TypeTile(
              icon: Icons.videocam_rounded,
              label: 'Video',
              color: const Color(0xFFFF9500),
              onTap: _busy ? null : () => _pickFiles(ItemType.video),
            ),
            _TypeTile(
              icon: Icons.audiotrack_rounded,
              label: 'Audio',
              color: const Color(0xFFE91E8C),
              onTap: _busy ? null : () => _pickFiles(ItemType.audio),
            ),
            _TypeTile(
              icon: Icons.insert_drive_file_rounded,
              label: 'Document',
              color: AppColors.accent,
              onTap: _busy ? null : () => _pickFiles(ItemType.file),
            ),
            _TypeTile(
              icon: Icons.text_fields_rounded,
              label: 'Text',
              color: const Color(0xFF00BCD4),
              onTap: _busy
                  ? null
                  : () => setState(() => _inputMode = ItemType.text),
            ),
            _TypeTile(
              icon: Icons.link_rounded,
              label: 'Link',
              color: widget.anchorColor,
              onTap: _busy
                  ? null
                  : () => setState(() => _inputMode = ItemType.link),
            ),
          ],
        ),
        SizedBox(height: 4.h),
      ],
    );
  }

  Widget _buildTextInput() {
    final isLink = _inputMode == ItemType.link;
    return Column(
      key: const ValueKey('input'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetHandle(),
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _inputMode = null;
                _contentCtrl.clear();
                _titleCtrl.clear();
              }),
              child: Container(
                width: 32.r,
                height: 32.r,
                margin: EdgeInsets.only(right: 10.w),
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_back_ios_rounded,
                    color: AppColors.textSecondary, size: 14.sp),
              ),
            ),
            Text(
              isLink ? 'Add Link' : 'Add Text',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        TextField(
          controller: _titleCtrl,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15.sp),
          decoration: const InputDecoration(hintText: 'Title (optional)'),
          textCapitalization: TextCapitalization.sentences,
        ),
        SizedBox(height: 10.h),
        TextField(
          controller: _contentCtrl,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15.sp),
          decoration: InputDecoration(
            hintText: isLink ? 'https://' : 'Enter text…',
          ),
          keyboardType:
              isLink ? TextInputType.url : TextInputType.multiline,
          textCapitalization:
              isLink ? TextCapitalization.none : TextCapitalization.sentences,
          maxLines: isLink ? 1 : 4,
          autofocus: true,
        ),
        SizedBox(height: 20.h),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (!_busy && _contentCtrl.text.trim().isNotEmpty)
                ? _saveText
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor:
                  AppColors.accent.withValues(alpha: 0.25),
              padding: EdgeInsets.symmetric(vertical: 14.h),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r)),
            ),
            child: _busy
                ? SizedBox(
                    width: 20.r,
                    height: 20.r,
                    child: const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text('Save',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15.sp)),
          ),
        ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Center(
          child: Container(
            width: 36.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
        ),
      );
}

class _TypeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _TypeTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40.r,
                height: 40.r,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(icon, color: color, size: 20.sp),
              ),
              SizedBox(height: 6.h),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Video Player Screen ──────────────────────────────────────────────────────

class _VideoPlayerScreen extends StatefulWidget {
  final AnchorItemModel item;
  const _VideoPlayerScreen({required this.item});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final url = widget.item.cloudinaryUrl ?? widget.item.content;
      VideoPlayerController ctrl;
      if (url.startsWith('http')) {
        ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      } else {
        final file = File(url);
        if (!file.existsSync()) {
          if (mounted) setState(() => _error = 'File not found');
          return;
        }
        ctrl = VideoPlayerController.file(file);
      }
      _videoCtrl = ctrl;
      await ctrl.initialize();

      _chewieCtrl = ChewieController(
        videoPlayerController: ctrl,
        autoPlay: true,
        looping: false,
        aspectRatio: ctrl.value.aspectRatio,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.white,
          handleColor: Colors.white,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
        placeholder: Container(color: Colors.black),
        errorBuilder: (_, msg) => Center(
          child: Text(msg, style: const TextStyle(color: Colors.white70)),
        ),
      );

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Cannot play video');
    }
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.close_rounded, color: Colors.white),
        ),
        title: Text(
          widget.item.title ?? widget.item.originalFilename ?? 'Video',
          style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_rounded,
                      color: Colors.white38, size: 48.sp),
                  SizedBox(height: 12.h),
                  Text(_error!,
                      style: TextStyle(
                          color: Colors.white54, fontSize: 14.sp)),
                ],
              ),
            )
          : !_initialized
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Center(child: Chewie(controller: _chewieCtrl!)),
    );
  }
}

// ─── Audio Player Sheet ───────────────────────────────────────────────────────

class _AudioPlayerSheet extends StatefulWidget {
  final AnchorItemModel item;
  const _AudioPlayerSheet({required this.item});

  @override
  State<_AudioPlayerSheet> createState() => _AudioPlayerSheetState();
}

class _AudioPlayerSheetState extends State<_AudioPlayerSheet> {
  static const _audioColor = Color(0xFFE91E8C);

  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = true;
  bool _playing = false;
  bool _completed = false;
  String? _error;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _subs.add(_player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.durationStream.listen((d) {
      if (d != null && mounted) setState(() => _duration = d);
    }));
    _subs.add(_player.playingStream.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
    _subs.add(_player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        setState(() => _completed = true);
      }
    }));
    _init();
  }

  Future<void> _init() async {
    try {
      final url = widget.item.cloudinaryUrl ?? widget.item.content;
      if (url.startsWith('http')) {
        await _player.setUrl(url);
      } else {
        final file = File(url);
        if (!file.existsSync()) throw Exception('File not found');
        await _player.setFilePath(url);
      }
      if (mounted) {
        setState(() => _loading = false);
        await _player.play();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Cannot play audio';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28.r),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x18000000),
              blurRadius: 32,
              offset: Offset(0, -6)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, bottom + 24.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          // Album art
          Container(
            width: 120.r,
            height: 120.r,
            decoration: BoxDecoration(
              color: _audioColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(
                  color: _audioColor.withValues(alpha: 0.2), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: _audioColor.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Icon(Icons.audiotrack_rounded,
                color: _audioColor, size: 48.sp),
          ),
          SizedBox(height: 20.h),
          Text(
            widget.item.title ??
                widget.item.originalFilename ??
                'Audio',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.item.mimeType != null) ...[
            SizedBox(height: 4.h),
            Text(
              widget.item.mimeType!,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.sp),
            ),
          ],
          SizedBox(height: 28.h),
          if (_error != null) ...[
            Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 32.sp),
            SizedBox(height: 8.h),
            Text(_error!,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13.sp)),
          ] else if (_loading)
            const CircularProgressIndicator(
                color: _audioColor, strokeWidth: 2)
          else ...[
            // Seek bar
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3.h,
                thumbShape:
                    RoundSliderThumbShape(enabledThumbRadius: 6.r),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: _audioColor,
                inactiveTrackColor: AppColors.border,
                thumbColor: _audioColor,
              ),
              child: Slider(
                value: _duration.inMilliseconds > 0
                    ? (_position.inMilliseconds /
                            _duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0,
                onChanged: (v) {
                  _completed = false;
                  _player.seek(Duration(
                      milliseconds:
                          (v * _duration.inMilliseconds).round()));
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_position),
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.sp)),
                  Text(_fmt(_duration),
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.sp)),
                ],
              ),
            ),
            SizedBox(height: 20.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlBtn(
                  icon: Icons.replay_10_rounded,
                  size: 28.sp,
                  onTap: () => _player.seek(
                      _position - const Duration(seconds: 10)),
                ),
                SizedBox(width: 24.w),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (_completed) {
                      _player.seek(Duration.zero);
                      setState(() => _completed = false);
                      _player.play();
                    } else if (_playing) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  },
                  child: Container(
                    width: 64.r,
                    height: 64.r,
                    decoration: const BoxDecoration(
                      color: _audioColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _completed
                          ? Icons.replay_rounded
                          : _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30.sp,
                    ),
                  ),
                ),
                SizedBox(width: 24.w),
                _ControlBtn(
                  icon: Icons.forward_10_rounded,
                  size: 28.sp,
                  onTap: () => _player.seek(
                      _position + const Duration(seconds: 10)),
                ),
              ],
            ),
          ],
          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _ControlBtn(
      {required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 44.r,
          height: 44.r,
          decoration: const BoxDecoration(
            color: AppColors.bg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: size),
        ),
      );
}

// ─── PDF Viewer Screen ────────────────────────────────────────────────────────

class _PdfViewerScreen extends StatefulWidget {
  final AnchorItemModel item;
  const _PdfViewerScreen({required this.item});

  @override
  State<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<_PdfViewerScreen> {
  String? _localPath;
  bool _loading = true;
  String? _error;
  int _pageCount = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final url = widget.item.cloudinaryUrl ?? widget.item.content;
      if (url.startsWith('http')) {
        final dir = await getTemporaryDirectory();
        final name = widget.item.originalFilename ??
            Uri.parse(url).pathSegments.last.split('?').first;
        final dest = '${dir.path}/${name.isEmpty ? 'document.pdf' : name}';
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode != 200) {
          throw Exception('Download failed (${resp.statusCode})');
        }
        await File(dest).writeAsBytes(resp.bodyBytes);
        _localPath = dest;
      } else {
        if (!File(url).existsSync()) throw Exception('File not found');
        _localPath = url;
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Icon(Icons.close_rounded,
              color: AppColors.textPrimary, size: 22.sp),
        ),
        title: Text(
          widget.item.originalFilename ??
              widget.item.title ??
              'Document',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pageCount > 0)
            Padding(
              padding: EdgeInsets.only(right: 16.w),
              child: Center(
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${_currentPage + 1} / $_pageCount',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.sp),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.h),
          child: Container(height: 1.h, color: AppColors.divider),
        ),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2),
                  SizedBox(height: 14.h),
                  Text(
                    widget.item.cloudinaryUrl != null
                        ? 'Downloading…'
                        : 'Opening…',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13.sp),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.r),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined,
                            color: AppColors.textTertiary, size: 48.sp),
                        SizedBox(height: 14.h),
                        Text('Cannot open document',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600)),
                        SizedBox(height: 6.h),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13.sp,
                                height: 1.5)),
                        SizedBox(height: 24.h),
                        FilledButton.icon(
                          onPressed: () async {
                            final path =
                                widget.item.content;
                            if (!path.startsWith('http')) {
                              await OpenFilex.open(path);
                            } else {
                              await launchUrl(
                                  Uri.parse(
                                      widget.item.cloudinaryUrl ??
                                          path),
                                  mode: LaunchMode
                                      .externalApplication);
                            }
                          },
                          icon: Icon(Icons.open_in_new_rounded,
                              size: 16.sp),
                          label: const Text('Open externally'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12.r)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : PDFView(
                  filePath: _localPath!,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  pageSnap: true,
                  fitEachPage: true,
                  onRender: (pages) {
                    if (mounted) {
                      setState(() => _pageCount = pages ?? 0);
                    }
                  },
                  onPageChanged: (page, _) {
                    if (mounted) {
                      setState(() => _currentPage = page ?? 0);
                    }
                  },
                  onError: (_) {
                    if (mounted) {
                      setState(
                          () => _error = 'Cannot render this PDF');
                    }
                  },
                  onPageError: (_, __) {},
                ),
    );
  }
}
