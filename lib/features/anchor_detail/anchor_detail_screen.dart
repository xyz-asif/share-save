import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../models/anchor_item_model.dart';
import '../../models/anchor_model.dart';
import '../../providers/anchor_items_provider.dart';
import '../../providers/anchors_provider.dart';

class AnchorDetailScreen extends ConsumerWidget {
  final AnchorModel anchor;
  const AnchorDetailScreen({super.key, required this.anchor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(anchorItemsProvider(anchor.id));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: () =>
            ref.read(anchorItemsProvider(anchor.id).notifier).refresh(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            _buildAppBar(context, ref),
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
                      style: const TextStyle(
                          color: AppColors.textSecondary)),
                ),
              ),
              data: (items) => items.isEmpty
                  ? _buildEmpty()
                  : _buildGrid(context, ref, items),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(BuildContext context, WidgetRef ref) {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 88,
      leading: IconButton(
        icon: Container(
          width: 34, height: 34,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 8,
                  offset: Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textPrimary, size: 16),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        title: Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: anchor.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.anchor_rounded, color: anchor.color, size: 15),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                anchor.name,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      actions: [
        GestureDetector(
          onTap: () => _confirmDeleteAnchor(context, ref),
          child: Container(
            width: 34, height: 34,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: AppColors.danger, size: 18),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  // ── Empty ────────────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: anchor.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.inbox_rounded, size: 36, color: anchor.color),
            ),
            const SizedBox(height: 16),
            const Text('Nothing saved yet',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Share content here from any app',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── Grid ─────────────────────────────────────────────────────────────────────

  Widget _buildGrid(
      BuildContext context, WidgetRef ref, List<AnchorItemModel> items) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 100),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childCount: items.length,
        itemBuilder: (ctx, i) => _SwipableItemCard(
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
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: anim,
              child: child,
            ),
          ),
        );
      case ItemType.text:
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
          builder: (_) => _TextPreviewSheet(item: item),
        );
      case ItemType.video:
      case ItemType.audio:
      case ItemType.file:
        launchUrl(Uri.file(item.content),
            mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmDeleteAnchor(
      BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
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

// ─── Swipable card wrapper ────────────────────────────────────────────────────

class _SwipableItemCard extends StatelessWidget {
  final AnchorItemModel item;
  final Color anchorColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SwipableItemCard({
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
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: AppColors.danger),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Remove item?',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 8,
                  offset: Offset(0, 2))
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: switch (item.type) {
            ItemType.image => _ImageCard(item: item),
            ItemType.link  => _LinkCard(item: item, accentColor: anchorColor),
            ItemType.text  => _TextCard(item: item),
            ItemType.video => _FileCard(item: item, icon: Icons.videocam_rounded,        color: const Color(0xFFFF9500)),
            ItemType.audio => _FileCard(item: item, icon: Icons.audiotrack_rounded,      color: const Color(0xFFE91E8C)),
            ItemType.file  => _FileCard(item: item, icon: Icons.insert_drive_file_rounded, color: AppColors.textTertiary),
          },
        ),
      ),
    );
  }
}

// ─── Delete anchor sheet ──────────────────────────────────────────────────────

class _DeleteAnchorSheet extends StatelessWidget {
  final AnchorModel anchor;
  const _DeleteAnchorSheet({required this.anchor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 24, offset: Offset(0, -4))
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.delete_rounded,
                color: AppColors.danger, size: 26),
          ),
          const SizedBox(height: 16),
          const Text('Delete Anchor?',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            '"${anchor.name}" and all its saved content will be permanently removed.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Cancel',
                    style:
                        TextStyle(color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Delete',
                    style:
                        TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Item card variants ───────────────────────────────────────────────────────

class _ImageCard extends StatelessWidget {
  final AnchorItemModel item;
  const _ImageCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isNet = item.content.startsWith('http');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: isNet
              ? CachedNetworkImage(
                  imageUrl: item.content,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.bg),
                  errorWidget: (_, __, ___) => const _BrokenImage())
              : Image.file(File(item.content),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _BrokenImage()),
        ),
        if (item.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Text(item.title!,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.bg,
        child: const Center(
          child: Icon(Icons.broken_image_rounded,
              color: AppColors.textTertiary),
        ),
      );
}

class _LinkCard extends StatelessWidget {
  final AnchorItemModel item;
  final Color accentColor;
  const _LinkCard({required this.item, required this.accentColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.link_rounded, color: accentColor, size: 18),
            ),
            const SizedBox(height: 10),
            if (item.title != null)
              Text(item.title!,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(item.content,
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (item.description != null) ...[
              const SizedBox(height: 6),
              Text(item.description!,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      );
}

class _TextCard extends StatelessWidget {
  final AnchorItemModel item;
  const _TextCard({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.text_fields_rounded,
                  color: Color(0xFF00BCD4), size: 15),
              SizedBox(width: 5),
              Text('Text',
                  style: TextStyle(
                      color: Color(0xFF00BCD4),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            if (item.title != null)
              Text(item.title!,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(item.content,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5),
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

class _FileCard extends StatelessWidget {
  final AnchorItemModel item;
  final IconData icon;
  final Color color;
  const _FileCard(
      {required this.item, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              item.title ?? item.originalFilename ?? 'Untitled',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.mimeType != null) ...[
              const SizedBox(height: 4),
              Text(item.mimeType!,
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      );
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
            style: const TextStyle(color: Colors.white, fontSize: 16)),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            if (item.title != null) ...[
              Text(item.title!,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                child: Text(item.content,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
