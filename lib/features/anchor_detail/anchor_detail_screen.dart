import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
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

class _AnchorDetailScreenState extends ConsumerState<AnchorDetailScreen> {
  final _scrollCtrl = ScrollController();
  bool _titleVisible = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    final visible = _scrollCtrl.offset > 80.h;
    if (visible != _titleVisible) setState(() => _titleVisible = visible);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.anchor;
    final itemsAsync = ref.watch(anchorItemsProvider(anchor.id));
    final count = itemsAsync.valueOrNull?.length ?? anchor.itemCount;

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
            _buildHero(anchor, count),
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
      title: AnimatedOpacity(
        opacity: _titleVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22.r,
            height: 22.r,
            decoration: BoxDecoration(
              color: anchor.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child:
                Icon(Icons.anchor_rounded, color: anchor.color, size: 12.sp),
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              anchor.name,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 1.h,
          color: _titleVisible ? AppColors.divider : Colors.transparent,
        ),
      ),
    );
  }

  // ── Hero ────────────────────────────────────────────────────────────────────

  SliverToBoxAdapter _buildHero(AnchorModel anchor, int count) {
    return SliverToBoxAdapter(
      child: Container(
        padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 28.h),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              anchor.color.withValues(alpha: 0.14),
              anchor.color.withValues(alpha: 0.0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56.r,
              height: 56.r,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [anchor.color, anchor.color.withValues(alpha: 0.72)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(17.r),
                boxShadow: [
                  BoxShadow(
                      color: anchor.color.withValues(alpha: 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 5)),
                ],
              ),
              child:
                  Icon(Icons.anchor_rounded, color: Colors.white, size: 27.sp),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anchor.name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    count == 0
                        ? 'Nothing saved yet'
                        : '$count item${count == 1 ? '' : 's'} saved',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13.sp),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 100.h),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 8.h,
        crossAxisSpacing: 8.w,
        childCount: items.length,
        itemBuilder: (ctx, i) => _ItemCard(
          key: ValueKey(items[i].id),
          item: items[i],
          anchorColor: anchor.color,
          onTap: () => _openItem(ctx, items[i]),
          onDelete: () => ref
              .read(anchorItemsProvider(anchor.id).notifier)
              .remove(items[i].id),
        ),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _openItem(BuildContext context, AnchorItemModel item) {
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
      case ItemType.file:
        launchUrl(Uri.file(item.content),
            mode: LaunchMode.externalApplication);
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

class _ItemCard extends StatelessWidget {
  final AnchorItemModel item;
  final Color anchorColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ItemCard({
    super.key,
    required this.item,
    required this.anchorColor,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 18.w),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child:
            Icon(Icons.delete_rounded, color: AppColors.danger, size: 20.sp),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => const _DeleteItemSheet(),
        );
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
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
          child: switch (item.type) {
            ItemType.image => _ImageContent(item: item),
            ItemType.link =>
              _LinkContent(item: item, accentColor: anchorColor),
            ItemType.text =>
              _TextContent(item: item, accentColor: anchorColor),
            ItemType.video => _MediaContent(
                item: item,
                icon: Icons.videocam_rounded,
                color: const Color(0xFFFF9500)),
            ItemType.audio => _MediaContent(
                item: item,
                icon: Icons.audiotrack_rounded,
                color: const Color(0xFFE91E8C)),
            ItemType.file => _MediaContent(
                item: item,
                icon: Icons.insert_drive_file_rounded,
                color: AppColors.textTertiary),
          },
        ),
      ),
    );
  }
}

// ─── Card content variants ────────────────────────────────────────────────────

class _ImageContent extends StatelessWidget {
  final AnchorItemModel item;
  const _ImageContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final isNet = item.content.startsWith('http');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isNet
            ? CachedNetworkImage(
                imageUrl: item.content,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) =>
                    Container(height: 80.h, color: AppColors.bg),
                errorWidget: (_, __, ___) => _BrokenImage(height: 60.h),
              )
            : Image.file(
                File(item.content),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _BrokenImage(height: 80.h),
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

class _LinkContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    _domain,
                    style: TextStyle(
                        color: accentColor,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              if (item.title != null) ...[
                SizedBox(height: 6.h),
                Text(
                  item.title!,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (item.description != null) ...[
                SizedBox(height: 4.h),
                Text(
                  item.description!,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.sp,
                      height: 1.4),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              SizedBox(height: 5.h),
              Text(
                item.content,
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 9.sp),
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
  const _MediaContent(
      {required this.item, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 9.sp),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
    final isNet = item.content.startsWith('http');
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
            ? CachedNetworkImageProvider(item.content)
            : FileImage(File(item.content)) as ImageProvider,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        heroAttributes: PhotoViewHeroAttributes(tag: item.id),
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
