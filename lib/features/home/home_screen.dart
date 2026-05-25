import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../models/anchor_item_model.dart';
import '../../models/anchor_model.dart';
import '../../providers/anchors_provider.dart';
import '../anchor_detail/anchor_detail_screen.dart';
import '../create_anchor/create_anchor_sheet.dart';

// ─── Screen ──────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchorsAsync = ref.watch(anchorsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createAnchor(context, ref),
        backgroundColor: AppColors.accent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.read(anchorsProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            const _SliverHeader(),
            anchorsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2)),
              ),
              error: (e, _) => SliverFillRemaining(
                child: _ErrorState(message: '$e'),
              ),
              data: (anchors) => anchors.isEmpty
                  ? const SliverFillRemaining(child: _EmptyState())
                  : _AnchorList(anchors: anchors),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createAnchor(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final anchor = await showModalBottomSheet<AnchorModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateAnchorSheet(),
    );
    if (anchor != null) ref.invalidate(anchorsProvider);
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _SliverHeader extends StatelessWidget {
  const _SliverHeader();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accentSoft],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.35),
                blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.anchor_rounded, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        const Text('Anchor',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            )),
      ]),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }
}

// ─── List ─────────────────────────────────────────────────────────────────────

class _AnchorList extends StatelessWidget {
  final List<AnchorModel> anchors;
  const _AnchorList({required this.anchors});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _AnchorCard(anchor: anchors[i]),
          ),
          childCount: anchors.length,
        ),
      ),
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _AnchorCard extends ConsumerStatefulWidget {
  final AnchorModel anchor;
  const _AnchorCard({required this.anchor});

  @override
  ConsumerState<_AnchorCard> createState() => _AnchorCardState();
}

class _AnchorCardState extends ConsumerState<_AnchorCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  void _onTap() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(_anchorRoute(widget.anchor));
  }

  @override
  Widget build(BuildContext context) {
    final previewAsync = ref.watch(anchorPreviewProvider(widget.anchor.id));
    final items = previewAsync.valueOrNull ?? [];

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); _onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: widget.anchor.color.withValues(alpha: 0.12),
            border: Border.all(
              color: widget.anchor.color.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.anchor.color.withValues(alpha: 0.18),
                blurRadius: 24, offset: const Offset(0, 10)),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ColorFill(color: widget.anchor.color),
                if (items.isNotEmpty)
                  _PreviewBackground(items: items, color: widget.anchor.color),
                Positioned(
                  left: 0, right: 0, bottom: 0, height: 96,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        color: widget.anchor.color.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 18),
                        child: _CardInfo(anchor: widget.anchor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Card sub-widgets ─────────────────────────────────────────────────────────

class _PreviewBackground extends StatelessWidget {
  final List<AnchorItemModel> items;
  final Color color;
  const _PreviewBackground({required this.items, required this.color});

  static const _angles = [-5.0, 4.0, -4.5, 5.5]; // degrees per slot

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final totalW = constraints.maxWidth;
      final count = items.length.clamp(1, 4);
      final slots = items.take(count).toList();

      if (count == 1) {
        return Padding(
          padding: EdgeInsets.fromLTRB(totalW * 0.15, 10, totalW * 0.15, 0),
          child: _styledSlot(slots[0], 0),
        );
      }

      // Horizontal padding keeps edge items inside the card's rounded border
      const double hPad = 12.0;
      final double availW = totalW - 2 * hPad;
      final double itemW = availW / count + 28;
      final double step = (availW - itemW) / (count - 1);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < slots.length; i++)
            Positioned(
              left: hPad + step * i,
              top: 10,
              bottom: 0,
              width: itemW,
              child: _styledSlot(slots[i], i),
            ),
        ],
      );
    });
  }

  Widget _styledSlot(AnchorItemModel item, int index) {
    return Transform.rotate(
      angle: _angles[index % _angles.length] * math.pi / 180,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10, offset: const Offset(2, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: switch (item.type) {
            ItemType.image => _Thumb(path: item.content),
            ItemType.link  => _LinkCell(url: item.content, color: color),
            _              => _TypeCell(type: item.type, color: color),
          },
        ),
      ),
    );
  }
}

class _LinkCell extends StatelessWidget {
  final String url;
  final Color color;
  const _LinkCell({required this.url, required this.color});

  String get _domain {
    try { return Uri.parse(url).host.replaceFirst('www.', ''); }
    catch (_) { return url; }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.80), color.withValues(alpha: 0.60)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link_rounded, color: Colors.white.withValues(alpha: 0.9), size: 22),
          const SizedBox(height: 6),
          Text(
            _domain,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TypeCell extends StatelessWidget {
  final ItemType type;
  final Color color;
  const _TypeCell({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (type) {
      ItemType.video => (Icons.videocam_rounded,          'video'),
      ItemType.audio => (Icons.audiotrack_rounded,        'audio'),
      ItemType.text  => (Icons.text_fields_rounded,       'text'),
      ItemType.file  => (Icons.insert_drive_file_rounded, 'file'),
      _              => (Icons.folder_rounded,             'item'),
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.80), color.withValues(alpha: 0.60)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String path;
  const _Thumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final isNet = path.startsWith('http');
    return SizedBox.expand(
      child: isNet
          ? Image.network(path, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: AppColors.cardHover))
          : Image.file(File(path), fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: AppColors.cardHover)),
    );
  }
}

class _ColorFill extends StatelessWidget {
  final Color color;
  const _ColorFill({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.anchor_rounded,
            color: color.withValues(alpha: 0.30), size: 56),
      ),
    );
  }
}

class _CardInfo extends StatelessWidget {
  final AnchorModel anchor;
  const _CardInfo({required this.anchor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          anchor.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          anchor.itemCount == 0
              ? 'Empty'
              : '${anchor.itemCount} item${anchor.itemCount == 1 ? '' : 's'}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ─── Page route ───────────────────────────────────────────────────────────────

Route<void> _anchorRoute(AnchorModel anchor) {
  return PageRouteBuilder(
    pageBuilder: (_, __, ___) => AnchorDetailScreen(anchor: anchor),
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
              begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

// ─── Empty / error states ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(
              color: AppColors.accentDim,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.anchor_rounded,
                size: 40, color: AppColors.accent),
          ),
          const SizedBox(height: 20),
          const Text('No anchors yet',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Tap + to create your first anchor',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message,
          style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
