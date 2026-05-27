import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/cloudinary_service.dart';
import '../../core/link_preview_service.dart';
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
  String _searchQuery = '';
  bool _sortReversed = false;
  int _selectedTab = 0;

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
    // Only refresh when returning from the share-target activity so newly
    // shared items appear. We detect this via the 'hidden → resumed' transition
    // (the share overlay puts the app in 'hidden', not 'paused').
    // We do NOT invalidate on every resume — that was causing 61-frame drops
    // on sign-in return and contributing to the MIUI ANR scout triggering.
    if (state == AppLifecycleState.hidden) {
      _wasHidden = true;
    } else if (state == AppLifecycleState.resumed && _wasHidden) {
      _wasHidden = false;
      ref.invalidate(anchorsProvider);
      ref.invalidate(anchorPreviewProvider);
    }
  }

  bool _wasHidden = false;

  @override
  Widget build(BuildContext context) {
    final anchorsAsync = ref.watch(anchorsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _createAnchor,
        backgroundColor: Colors.black,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.anchor_rounded, color: Colors.white, size: 26),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            onRefresh: () => ref.read(anchorsProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                _SliverHeader(
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  sortReversed: _sortReversed,
                  onSortToggle: () =>
                      setState(() => _sortReversed = !_sortReversed),
                ),
                anchorsAsync.when(
                  loading: () => const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent, strokeWidth: 2)),
                  ),
                  error: (e, _) => SliverFillRemaining(
                    child: _ErrorState(message: '$e'),
                  ),
                  data: (anchors) {
                    var list = _searchQuery.isEmpty
                        ? anchors
                        : anchors
                            .where((a) => a.name
                                .toLowerCase()
                                .contains(_searchQuery.toLowerCase()))
                            .toList();
                    if (_sortReversed) list = list.reversed.toList();
                    if (list.isEmpty) {
                      return const SliverFillRemaining(child: _EmptyState());
                    }
                    return SliverToBoxAdapter(
                      child: _AnchorListColumn(
                        key: ValueKey('$_sortReversed|$_searchQuery'),
                        anchors: list,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 20.w,
            child: _FloatingNavBar(
              selectedIndex: _selectedTab,
              onTap: (i) => setState(() => _selectedTab = i),
            ),
          ),
        ],
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

class _SliverHeader extends StatefulWidget {
  final ValueChanged<String> onSearchChanged;
  final bool sortReversed;
  final VoidCallback onSortToggle;

  const _SliverHeader({
    required this.onSearchChanged,
    required this.sortReversed,
    required this.onSortToggle,
  });

  @override
  State<_SliverHeader> createState() => _SliverHeaderState();
}

class _SliverHeaderState extends State<_SliverHeader>
    with TickerProviderStateMixin {
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  late final AnimationController _searchAnim;
  late final AnimationController _sortAnim;
  late final Animation<double> _searchFade;
  late final Animation<Offset> _searchSlide;
  late final Animation<double> _sortRotation;

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _sortAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _searchFade =
        CurvedAnimation(parent: _searchAnim, curve: Curves.easeOut);
    _searchSlide = Tween<Offset>(
            begin: const Offset(0.15, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _searchAnim, curve: Curves.easeOut));
    _sortRotation = Tween<double>(begin: 0, end: 0.5)
        .animate(CurvedAnimation(parent: _sortAnim, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_SliverHeader old) {
    super.didUpdateWidget(old);
    if (widget.sortReversed != old.sortReversed) {
      widget.sortReversed ? _sortAnim.forward() : _sortAnim.reverse();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchAnim.dispose();
    _sortAnim.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchAnim.forward();
      _searchFocus.requestFocus();
    } else {
      _searchAnim.reverse();
      _searchFocus.unfocus();
      _searchCtrl.clear();
      widget.onSearchChanged('');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      toolbarHeight: 64.h,
      automaticallyImplyLeading: false,
      titleSpacing: 16.w,
      title: _searchOpen ? _buildSearchBar() : _buildDefaultTitle(),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(1.h),
        child: Container(height: 1.h, color: AppColors.divider),
      ),
    );
  }

  Widget _buildDefaultTitle() {
    return Row(
      children: [
        CircleAvatar(
          radius: 19.r,
          backgroundImage: const NetworkImage(
            'https://api.dicebear.com/7.x/adventurer/png?seed=AnchorApp&backgroundColor=ffd5dc',
          ),
          backgroundColor: AppColors.surface,
        ),
        const Spacer(),
        _HeaderIconBtn(icon: CupertinoIcons.search, onTap: _toggleSearch),
        SizedBox(width: 8.w),
        RotationTransition(
          turns: _sortRotation,
          child: _HeaderIconBtn(
            icon: CupertinoIcons.arrow_up_arrow_down,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onSortToggle();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return FadeTransition(
      opacity: _searchFade,
      child: SlideTransition(
        position: _searchSlide,
        child: Row(
          children: [
            GestureDetector(
              onTap: _toggleSearch,
              child: Icon(CupertinoIcons.xmark_circle_fill,
                  color: AppColors.textTertiary, size: 22.sp),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Container(
                height: 40.h,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: widget.onSearchChanged,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14.sp),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(
                              color: AppColors.textTertiary, fontSize: 14.sp),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(CupertinoIcons.search,
                        color: AppColors.accent, size: 16.sp),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.r,
        height: 36.r,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 16.sp),
      ),
    );
  }
}

// ─── List ─────────────────────────────────────────────────────────────────────

class _AnchorListColumn extends StatefulWidget {
  final List<AnchorModel> anchors;
  const _AnchorListColumn({required this.anchors, super.key});

  @override
  State<_AnchorListColumn> createState() => _AnchorListColumnState();
}

class _AnchorListColumnState extends State<_AnchorListColumn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 100.h),
      child: Column(
        children: [
          for (int i = 0; i < widget.anchors.length; i++)
            _buildCard(i),
        ],
      ),
    );
  }

  Widget _buildCard(int i) {
    final start = (i * 0.07).clamp(0.0, 0.65);
    final end = (start + 0.35).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(anim),
        child: _AnchorCard(anchor: widget.anchors[i]),
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
                  height: 88.h,
                  child: Container(
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20.r),
                      ),
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
                        left: BorderSide(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
                        right: BorderSide(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
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
          padding: EdgeInsets.fromLTRB(totalW * 0.15, 10.h, totalW * 0.15, 31.h),
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
              top: 10.h,
              bottom: 31.h,
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
            ItemType.image => _Thumb(item: item),
            ItemType.link => _LinkCell(item: item, color: color),
            // Video with any thumbnail (CDN or local) → show it like an image
            ItemType.video when item.displayThumbnail != null =>
              _Thumb(item: item),
            _ => _TypeCell(type: item.type, color: color),
          },
        ),
      ),
    );
  }
}

class _LinkCell extends ConsumerWidget {
  final AnchorItemModel item;
  final Color color;
  const _LinkCell({required this.item, required this.color});

  String get _domain {
    try {
      return Uri.parse(item.content).host.replaceFirst('www.', '');
    } catch (_) {
      return item.content;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(linkPreviewProvider(item.content)).valueOrNull;
    // Prefer Cloudinary Fetch CDN (caching + transforms); fall back to raw OG URL
    final ogCdnImage = preview?.cdnImageUrl;
    final ogRawImage = preview?.imageUrl;
    final ogImage = ogCdnImage ?? ogRawImage;

    if (ogImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Positioned.fill gives CachedNetworkImage explicit bounded constraints
          // so BoxFit.cover always fills and crops correctly
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: ogImage,
              fit: BoxFit.cover,
              placeholder: (_, __) => _fallback(),
              // CDN failed → retry with raw OG URL before giving up
              errorWidget: (_, __, ___) {
                if (ogImage == ogCdnImage && ogRawImage != null) {
                  return Image.network(
                    ogRawImage,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => _fallback(),
                  );
                }
                return _fallback();
              },
            ),
          ),
          // Scrim + site name at the bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Text(
                preview?.siteName ?? _domain,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8.sp,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.80),
            color.withValues(alpha: 0.60),
          ],
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.link,
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
      ItemType.video => (CupertinoIcons.video_camera, 'video'),
      ItemType.audio => (CupertinoIcons.music_note, 'audio'),
      ItemType.text => (CupertinoIcons.textformat, 'text'),
      ItemType.file => (CupertinoIcons.doc, 'file'),
      _ => (CupertinoIcons.folder, 'item'),
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
  final AnchorItemModel item;
  const _Thumb({required this.item});

  /// Returns the best square CDN thumbnail URL.
  /// Derives it fresh from [cloudinaryPublicId] so existing synced items
  /// automatically get the corrected square crop (fixes the "zoomed-out"
  /// appearance that occurred when the old 400×300 landscape thumbnail was
  /// displayed inside portrait or near-square card slots).
  String? get _cdnThumbUrl {
    if (item.cloudinaryPublicId != null) {
      return CloudinaryService.instance
          .thumbnailUrl(item.cloudinaryPublicId!, item.type);
    }
    return item.thumbnailUrl;
  }

  @override
  Widget build(BuildContext context) {
    final cdnUrl = _cdnThumbUrl;

    // 1) CDN thumbnail — square crop, fills any aspect-ratio slot correctly
    if (cdnUrl != null) {
      return SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: cdnUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (_, __) => Container(color: AppColors.cardHover),
          errorWidget: (_, __, ___) => _localFallback(),
        ),
      );
    }
    // 2) Full CDN URL (no dedicated thumbnail yet)
    if (item.cloudinaryUrl != null) {
      return SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: item.cloudinaryUrl!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (_, __) => Container(color: AppColors.cardHover),
          errorWidget: (_, __, ___) => _localFallback(),
        ),
      );
    }
    return SizedBox.expand(child: _localFallback());
  }

  /// 3) Local thumbnail path → 4) content path (images only)
  Widget _localFallback() {
    if (item.thumbnailPath != null) {
      return Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _contentImage(),
      );
    }
    return _contentImage();
  }

  Widget _contentImage() {
    final path = item.content;
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: AppColors.cardHover),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: AppColors.cardHover),
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
        ItemType.image => CupertinoIcons.photo,
        ItemType.video => CupertinoIcons.video_camera,
        ItemType.audio => CupertinoIcons.music_note,
        ItemType.text => CupertinoIcons.textformat,
        ItemType.file => CupertinoIcons.doc,
        ItemType.link => CupertinoIcons.link,
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

// ─── Floating nav bar ─────────────────────────────────────────────────────────

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _FloatingNavBar({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40.r),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.all(5.r),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(40.r),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.90),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavItem(
                icon: CupertinoIcons.rectangle_grid_2x2,
                index: 0,
                selectedIndex: selectedIndex,
                onTap: onTap,
              ),
              SizedBox(width: 4.w),
              _NavItem(
                icon: CupertinoIcons.person_2,
                index: 1,
                selectedIndex: selectedIndex,
                onTap: onTap,
              ),
              SizedBox(width: 4.w),
              _NavItem(
                icon: CupertinoIcons.doc_text,
                index: 2,
                selectedIndex: selectedIndex,
                onTap: onTap,
                hasBadge: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final int index;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool hasBadge;

  const _NavItem({
    required this.icon,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
    this.hasBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == selectedIndex;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 40.r,
        height: 40.r,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.60)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24.r),
          border: isSelected
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.0,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.50),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                icon,
                size: 20.sp,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            if (hasBadge)
              Positioned(
                top: 7.h,
                right: 7.w,
                child: Container(
                  width: 7.r,
                  height: 7.r,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
