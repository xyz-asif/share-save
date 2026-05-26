import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme.dart';
import '../../models/anchor_item_model.dart';
import '../../models/anchor_model.dart';
import '../../providers/anchors_provider.dart';
import '../anchor_detail/anchor_detail_screen.dart';
import '../create_anchor/create_anchor_sheet.dart';

// ─── Screen ──────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(anchorsProvider);
      ref.invalidate(anchorPreviewProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchorsAsync = ref.watch(anchorsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _createAnchor,
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
                child: Center(
                    child: CircularProgressIndicator(
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

  Future<void> _createAnchor() async {
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
      toolbarHeight: 64.h,
      automaticallyImplyLeading: false,
      titleSpacing: 20.w,
      title: Row(children: [
        Container(
          width: 30.r,
          height: 30.r,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accentSoft],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(9.r),
            boxShadow: [
              BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Icon(Icons.anchor_rounded, color: Colors.white, size: 17.sp),
        ),
        SizedBox(width: 10.w),
        Text('Anchor',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            )),
      ]),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(1.h),
        child: Container(height: 1.h, color: AppColors.divider),
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
      padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 100.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => Padding(
            padding: EdgeInsets.only(bottom: 14.h),
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
      onTapUp: (_) {
        setState(() => _pressed = false);
        _onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: 150.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22.r),
            color: widget.anchor.color.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.45),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                  color: widget.anchor.color.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10)),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21.r),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ColorFill(color: widget.anchor.color),
                if (items.isNotEmpty)
                  _PreviewBackground(items: items, color: widget.anchor.color),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 96.h,
                  child: Container(
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20.r),
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20.r),
                      ),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.04),
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 18.h),
                          child: _CardInfo(anchor: widget.anchor, items: items),
                        ),
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
          padding: EdgeInsets.fromLTRB(totalW * 0.15, 8.h, totalW * 0.15, 36.h),
          child: _styledSlot(slots[0], 0),
        );
      }

      // Horizontal padding keeps edge items inside the card's rounded border
      final double hPad = 12.w;
      final double availW = totalW - 2 * hPad;
      final double itemW = availW / count + 14.w;
      final double step = (availW - itemW) / (count - 1);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < slots.length; i++)
            Positioned(
              left: hPad + step * i,
              top: 8.h,
              bottom: 36.h,
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
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: Colors.white, width: 1.8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(2, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18.r),
          child: switch (item.type) {
            ItemType.image => _Thumb(path: item.content),
            ItemType.link => _LinkCell(url: item.content, color: color),
            _ => _TypeCell(type: item.type, color: color),
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
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.80),
            color.withValues(alpha: 0.60)
          ],
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link_rounded,
              color: Colors.white.withValues(alpha: 0.9), size: 22.sp),
          SizedBox(height: 6.h),
          Text(
            _domain,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 10.sp,
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
      ItemType.video => (Icons.videocam_rounded, 'video'),
      ItemType.audio => (Icons.audiotrack_rounded, 'audio'),
      ItemType.text => (Icons.text_fields_rounded, 'text'),
      ItemType.file => (Icons.insert_drive_file_rounded, 'file'),
      _ => (Icons.folder_rounded, 'item'),
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.80),
            color.withValues(alpha: 0.60)
          ],
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 24.sp),
          SizedBox(height: 6.h),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 10.sp,
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
          ? Image.network(path,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppColors.cardHover))
          : Image.file(File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppColors.cardHover)),
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
  final List<AnchorItemModel> items;
  const _CardInfo({required this.anchor, required this.items});

  static IconData _iconFor(ItemType type) => switch (type) {
        ItemType.image => Icons.image_rounded,
        ItemType.video => Icons.videocam_rounded,
        ItemType.audio => Icons.audiotrack_rounded,
        ItemType.text => Icons.text_fields_rounded,
        ItemType.file => Icons.insert_drive_file_rounded,
        ItemType.link => Icons.link_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final uniqueTypes = items.map((e) => e.type).toSet().toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                anchor.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 2.h),
              Text(
                anchor.itemCount == 0
                    ? 'Empty'
                    : '${anchor.itemCount} item${anchor.itemCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        if (uniqueTypes.isNotEmpty) ...[
          SizedBox(width: 8.w),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: uniqueTypes.take(4).map((type) {
              return Padding(
                padding: EdgeInsets.only(left: 6.w),
                child: Container(
                  width: 28.r,
                  height: 28.r,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    _iconFor(type),
                    color: Colors.white.withValues(alpha: 0.90),
                    size: 14.sp,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
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
            width: 80.r,
            height: 80.r,
            decoration: const BoxDecoration(
              color: AppColors.accentDim,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.anchor_rounded,
                size: 40.sp, color: AppColors.accent),
          ),
          SizedBox(height: 20.h),
          Text('No anchors yet',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 8.h),
          Text('Tap + to create your first anchor',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14.sp)),
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
      child:
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
