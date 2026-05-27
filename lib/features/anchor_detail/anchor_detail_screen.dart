import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_view/photo_view.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/cloudinary_service.dart';
import '../../core/link_preview_service.dart';
import '../../core/sync_service.dart';
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
    // Kick off any pending Cloudinary uploads for items in this anchor
    Future.microtask(
        () => ref.read(cloudinarySyncProvider.notifier).syncPending());
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
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
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
      case ItemType.audio:
        // Use OpenFilex for local/content-URI paths — it handles Android
        // FileProvider so we never get a FileUriExposedException.
        // If the local file is gone but we have a CDN URL, stream from there.
        try {
          final path = item.content;
          if (!path.startsWith('http')) {
            await OpenFilex.open(path);
          } else if (item.cloudinaryUrl != null) {
            await launchUrl(Uri.parse(item.cloudinaryUrl!),
                mode: LaunchMode.externalApplication);
          } else {
            await launchUrl(Uri.parse(path),
                mode: LaunchMode.externalApplication);
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cannot open this file')),
            );
          }
        }
      case ItemType.file:
        if (!context.mounted) return;
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

/// Renders an image card whose height adapts to the image's actual aspect
/// ratio so the full picture is always visible — no cropping.
///
/// Flutter's [ImageStream] is used to read the decoded pixel dimensions once
/// (from the in-memory cache when available, or after the first network
/// download).  Until the ratio is known a 1:1 placeholder is shown; once
/// detected the [AspectRatio] snaps to the real value and [SliverMasonryGrid]
/// re-lays out the column naturally.
class _ImageContent extends StatefulWidget {
  final AnchorItemModel item;
  const _ImageContent({required this.item});

  @override
  State<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends State<_ImageContent> {
  double? _ratio;           // null → still detecting
  ImageStream? _stream;
  late ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _resolveRatio();
  }

  @override
  void didUpdateWidget(_ImageContent old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _stream?.removeListener(_listener);
      _ratio = null;
      _resolveRatio();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _resolveRatio() {
    final item = widget.item;

    // Pick the same provider that the visible image widget will use, so the
    // ImageStream is already warm whenever CachedNetworkImage has the image.
    final ImageProvider provider;
    if (item.cloudinaryPublicId != null) {
      provider = CachedNetworkImageProvider(
        CloudinaryService.instance.thumbnailUrl(item.cloudinaryPublicId!, item.type),
      );
    } else if (item.thumbnailUrl != null) {
      provider = CachedNetworkImageProvider(item.thumbnailUrl!);
    } else if (item.cloudinaryUrl != null) {
      provider = CachedNetworkImageProvider(item.cloudinaryUrl!);
    } else if (!item.content.startsWith('http')) {
      provider = FileImage(File(item.content));
    } else {
      provider = CachedNetworkImageProvider(item.content);
    }

    _listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (h > 0 && mounted) setState(() => _ratio = w / h);
        _stream?.removeListener(_listener);
      },
      onError: (_, __) {
        // Fall back to a square card on any decode error.
        if (mounted) setState(() => _ratio = 1.0);
        _stream?.removeListener(_listener);
      },
    );

    _stream = provider.resolve(const ImageConfiguration());
    _stream!.addListener(_listener);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    // Use detected ratio; show 1:1 square as placeholder while detecting.
    final ratio = _ratio ?? 1.0;

    final thumbUrl = item.cloudinaryPublicId != null
        ? CloudinaryService.instance.thumbnailUrl(item.cloudinaryPublicId!, item.type)
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
      imageWidget = Image.file(
        File(item.content),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _BrokenImage(height: 80.h),
      );
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
    // Prefer CDN full-resolution URL when the item has been synced.
    final displayUrl = item.cloudinaryUrl ?? item.content;
    final isNet = displayUrl.startsWith('http');
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
        imageProvider: isNet
            ? CachedNetworkImageProvider(displayUrl)
            : FileImage(File(displayUrl)) as ImageProvider,
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
