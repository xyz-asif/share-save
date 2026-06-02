import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/cloudinary_service.dart';
import '../../core/link_preview_service.dart';
import '../../core/sync_service.dart';
import '../../core/theme.dart';
import '../../models/anchor_item_model.dart';
import '../../models/anchor_model.dart';
import '../../providers/anchor_items_provider.dart';
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
  bool _wasHidden = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _searchQuery = q);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden) {
      _wasHidden = true;
    } else if (state == AppLifecycleState.resumed && _wasHidden) {
      _wasHidden = false;
      _refreshAfterShare();
    }
  }

  Future<void> _refreshAfterShare() async {
    final prefs = await SharedPreferences.getInstance();
    final touched = prefs.getStringList('share_touched_anchors') ?? const [];

    // Always refresh the anchor list — item counts may have changed.
    ref.invalidate(anchorsProvider);

    // For each anchor that received new items via the share-target,
    // invalidate BOTH the home preview AND the detail items providers.
    // Targeted invalidation only — never invalidate the whole family.
    for (final anchorId in touched) {
      ref.invalidate(anchorPreviewProvider(anchorId));
      ref.invalidate(anchorItemsProvider(anchorId));
    }

    if (touched.isNotEmpty) {
      await prefs.remove('share_touched_anchors');
    }
  }

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
                  onSearchChanged: _onSearchChanged,
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
                    if (_selectedTab == 2) {
                      return const SliverToBoxAdapter(
                          child: _SyncActivityView());
                    }
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
                    if (_selectedTab == 1) {
                      return SliverToBoxAdapter(
                        child: _AnchorGridView(
                          key: ValueKey('grid_$_sortReversed'),
                          anchors: list,
                        ),
                      );
                    }
                    return SliverToBoxAdapter(
                      child: _AnchorListColumn(
                        key: ValueKey(_sortReversed),
                        anchors: list,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 8,
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
    _searchFade = CurvedAnimation(parent: _searchAnim, curve: Curves.easeOut);
    _searchSlide = Tween<Offset>(begin: const Offset(0.15, 0), end: Offset.zero)
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
          for (int i = 0; i < widget.anchors.length; i++) _buildCard(i),
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

// ─── Grid View ────────────────────────────────────────────────────────────────

class _AnchorGridView extends StatefulWidget {
  final List<AnchorModel> anchors;
  const _AnchorGridView({required this.anchors, super.key});

  @override
  State<_AnchorGridView> createState() => _AnchorGridViewState();
}

class _AnchorGridViewState extends State<_AnchorGridView>
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
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 56.h),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16.w,
          mainAxisSpacing: 24.h,
          childAspectRatio: 0.76,
        ),
        itemCount: widget.anchors.length,
        itemBuilder: (context, i) {
          final start = (i * 0.07).clamp(0.0, 0.65);
          final end = (start + 0.35).clamp(0.0, 1.0);
          final anim = CurvedAnimation(
            parent: _ctrl,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.18),
              end: Offset.zero,
            ).animate(anim),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _ctrl,
                curve: Interval(start, end, curve: Curves.easeOut),
              ),
              child: _AnchorGridCard(anchor: widget.anchors[i]),
            ),
          );
        },
      ),
    );
  }
}

// ─── Grid Card ────────────────────────────────────────────────────────────────

class _AnchorGridCard extends ConsumerStatefulWidget {
  final AnchorModel anchor;
  const _AnchorGridCard({required this.anchor});

  @override
  ConsumerState<_AnchorGridCard> createState() => _AnchorGridCardState();
}

class _AnchorGridCardState extends ConsumerState<_AnchorGridCard> {
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
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _StackedCardsPreview(
                  items: items, color: widget.anchor.color),
            ),
            SizedBox(height: 4.h),
            Text(
              widget.anchor.name,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 3.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.anchor.itemCount == 0
                      ? 'Empty'
                      : '${widget.anchor.itemCount} item${widget.anchor.itemCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(
                  CupertinoIcons.lock_fill,
                  size: 10.sp,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            SizedBox(height: 4.h),
          ],
        ),
      ),
    );
  }
}

// ─── Stacked Cards Preview ────────────────────────────────────────────────────

class _StackedCardsPreview extends StatelessWidget {
  final List<AnchorItemModel> items;
  final Color color;
  const _StackedCardsPreview({required this.items, required this.color});

  // [angle°, dx fraction of W, dy fraction of H] — index 0=back-right, 1=back-left, 2=front
  static const _cfg = [
    (17.0, 0.10, -0.09),   // back-right: peeks right, shifted UP
    (-15.0, -0.09, -0.07), // back-left: peeks left, shifted UP
    (0.0, 0.0, 0.0),       // front: straight, centered
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final cardW = w * 0.64;
      final cardH = h * 0.70;

      return Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(_cfg[i].$2 * w, _cfg[i].$3 * h),
              child: Transform.rotate(
                angle: _cfg[i].$1 * math.pi / 180,
                child: _cardSlot(
                  i < items.length ? items[i] : null,
                  cardW,
                  cardH,
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _cardSlot(AnchorItemModel? item, double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: item == null
            ? Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.30),
                      color.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              )
            : switch (item.type) {
                ItemType.image => _Thumb(item: item),
                ItemType.video when item.displayThumbnail != null =>
                  _Thumb(item: item),
                ItemType.link => _LinkCell(item: item, color: color),
                _ => _TypeCell(type: item.type, color: color),
              },
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
                        top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 1.2),
                        left: BorderSide(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 1.2),
                        right: BorderSide(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 1.2),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20.r),
                      ),
                      // OPTION D — BackdropFilter blur restored, with dark tint
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0),
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
          padding:
              EdgeInsets.fromLTRB(totalW * 0.15, 10.h, totalW * 0.15, 31.h),
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
    final ogCdnImage = preview?.cdnImageUrl;
    final ogRawImage = preview?.imageUrl;
    final ogImage = ogCdnImage ?? ogRawImage;

    // _fallback() is always the base layer — the image appears on top once
    // loaded. This eliminates the placeholder flash: instead of switching
    // between two widget trees, the solid color never disappears.
    return Stack(
      fit: StackFit.expand,
      children: [
        _fallback(),
        if (ogImage != null) ...[
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: ogImage,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) {
                if (ogImage == ogCdnImage && ogRawImage != null) {
                  return Image.network(
                    ogRawImage,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
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
      ],
    );
  }

  Widget _fallback() {
    return Container(
      color: color,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.link, color: Colors.white, size: 22.sp),
          SizedBox(height: 6.h),
          Text(
            _domain,
            style: TextStyle(
              color: Colors.white,
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
      return CloudinaryService.instance.thumbnailUrl(
        item.cloudinaryPublicId!,
        item.type,
        mimeType: item.mimeType,
      );
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
                icon: CupertinoIcons.rectangle_stack,
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

// ─── Sync Activity Tab (Tab 2) ────────────────────────────────────────────────

enum _SyncFilter { all, synced, uploading, pending, failed }

extension _SyncFilterExt on _SyncFilter {
  String get label => switch (this) {
        _SyncFilter.all => 'All',
        _SyncFilter.synced => 'Synced',
        _SyncFilter.uploading => 'Uploading',
        _SyncFilter.pending => 'Pending',
        _SyncFilter.failed => 'Failed',
      };

  IconData get icon => switch (this) {
        _SyncFilter.all => CupertinoIcons.square_grid_2x2,
        _SyncFilter.synced => CupertinoIcons.checkmark_circle_fill,
        _SyncFilter.uploading => CupertinoIcons.arrow_up_circle_fill,
        _SyncFilter.pending => CupertinoIcons.clock_fill,
        _SyncFilter.failed => CupertinoIcons.xmark_circle_fill,
      };

  Color get color => switch (this) {
        _SyncFilter.all => AppColors.accent,
        _SyncFilter.synced => AppColors.success,
        _SyncFilter.uploading => const Color(0xFFFF9500),
        _SyncFilter.pending => AppColors.accentSoft,
        _SyncFilter.failed => AppColors.danger,
      };
}

class _SyncActivityView extends ConsumerStatefulWidget {
  const _SyncActivityView();

  @override
  ConsumerState<_SyncActivityView> createState() => _SyncActivityViewState();
}

class _SyncActivityViewState extends ConsumerState<_SyncActivityView> {
  _SyncFilter _filter = _SyncFilter.all;

  List<ItemWithAnchor> _applyFilter(
      List<ItemWithAnchor> all, _SyncFilter filter) {
    return switch (filter) {
      _SyncFilter.all => all,
      _SyncFilter.synced => all
          .where((e) =>
              e.item.syncStatus == SyncStatus.synced ||
              e.item.syncStatus == SyncStatus.na)
          .toList(),
      _SyncFilter.uploading =>
        all.where((e) => e.item.syncStatus == SyncStatus.uploading).toList(),
      _SyncFilter.pending =>
        all.where((e) => e.item.syncStatus == SyncStatus.pending).toList(),
      _SyncFilter.failed =>
        all.where((e) => e.item.syncStatus == SyncStatus.failed).toList(),
    };
  }

  Map<_SyncFilter, int> _buildCounts(List<ItemWithAnchor> all) => {
        _SyncFilter.all: all.length,
        _SyncFilter.synced: all
            .where((e) =>
                e.item.syncStatus == SyncStatus.synced ||
                e.item.syncStatus == SyncStatus.na)
            .length,
        _SyncFilter.uploading:
            all.where((e) => e.item.syncStatus == SyncStatus.uploading).length,
        _SyncFilter.pending:
            all.where((e) => e.item.syncStatus == SyncStatus.pending).length,
        _SyncFilter.failed:
            all.where((e) => e.item.syncStatus == SyncStatus.failed).length,
      };

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allItemsWithAnchorProvider);

    return allAsync.when(
      loading: () => const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2),
        ),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.all(32.r),
        child: Center(
          child: Text('$e',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13.sp)),
        ),
      ),
      data: (all) {
        final counts = _buildCounts(all);
        final filtered = _applyFilter(all, _filter);
        final uploading = counts[_SyncFilter.uploading] ?? 0;
        final pending = counts[_SyncFilter.pending] ?? 0;
        final failed = counts[_SyncFilter.failed] ?? 0;

        return Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 100.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Items',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (uploading > 0 || pending > 0)
                        Text(
                          uploading > 0
                              ? '$uploading uploading${pending > 0 ? ', $pending pending' : ''}'
                              : '$pending pending',
                          style: TextStyle(
                            color: const Color(0xFFFF9500),
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  // Total count pill
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20.r),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 5.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(20.r),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.90),
                              width: 1.0),
                        ),
                        child: Text(
                          '${all.length}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (failed > 0) ...[
                    SizedBox(width: 6.w),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        ref
                            .read(cloudinarySyncProvider.notifier)
                            .retryFailed();
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8.w, vertical: 5.h),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20.r),
                          border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.30)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.arrow_clockwise,
                                size: 11.sp, color: AppColors.danger),
                            SizedBox(width: 3.w),
                            Text('Retry $failed',
                                style: TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 14.h),
              // ── Filter chips ─────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _SyncFilter.values.map((f) {
                    return Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: _SyncFilterChip(
                        filter: f,
                        count: counts[f] ?? 0,
                        selected: _filter == f,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _filter = f);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: 16.h),
              // ── Item list (keyed so animation replays on filter change) ──
              _SyncItemList(key: ValueKey(_filter), items: filtered),
            ],
          ),
        );
      },
    );
  }
}

// ─── Filter Chip ──────────────────────────────────────────────────────────────

class _SyncFilterChip extends StatelessWidget {
  final _SyncFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SyncFilterChip({
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = filter.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.50)
                : Colors.white.withValues(alpha: 0.85),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(filter.icon,
                size: 13.sp,
                color: selected ? color : AppColors.textSecondary),
            SizedBox(width: 5.w),
            Text(
              filter.label,
              style: TextStyle(
                color: selected ? color : AppColors.textSecondary,
                fontSize: 12.sp,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (count > 0) ...[
              SizedBox(width: 5.w),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.5.h),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.18)
                      : AppColors.textTertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? color : AppColors.textTertiary,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Animated item list ───────────────────────────────────────────────────────

class _SyncItemList extends StatefulWidget {
  final List<ItemWithAnchor> items;
  const _SyncItemList({required this.items, super.key});

  @override
  State<_SyncItemList> createState() => _SyncItemListState();
}

class _SyncItemListState extends State<_SyncItemList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 48.h),
        child: Center(
          child: Column(
            children: [
              Icon(CupertinoIcons.tray,
                  size: 40.sp, color: AppColors.textTertiary),
              SizedBox(height: 12.h),
              Text(
                'No items here',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < widget.items.length; i++) _buildCard(i),
      ],
    );
  }

  Widget _buildCard(int i) {
    final start = (i * 0.055).clamp(0.0, 0.62);
    final end = (start + 0.38).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: FadeTransition(
        opacity: CurvedAnimation(
            parent: _ctrl,
            curve: Interval(start, end, curve: Curves.easeOut)),
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
                  .animate(anim),
          child: _SyncItemCard(entry: widget.items[i]),
        ),
      ),
    );
  }
}

// ─── Item Card ────────────────────────────────────────────────────────────────

class _SyncItemCard extends StatelessWidget {
  final ItemWithAnchor entry;
  const _SyncItemCard({required this.entry});

  String _titleFor(AnchorItemModel item) {
    if (item.title != null && item.title!.isNotEmpty) return item.title!;
    if (item.originalFilename != null && item.originalFilename!.isNotEmpty) {
      return item.originalFilename!;
    }
    if (item.type == ItemType.link) {
      try {
        return Uri.parse(item.content).host.replaceFirst('www.', '');
      } catch (_) {}
    }
    final c = item.content;
    return c.length > 42 ? '${c.substring(0, 42).trimRight()}…' : c;
  }

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final anchorColor = entry.anchorColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17.r),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: Colors.white.withValues(alpha: 0.74),
            padding: EdgeInsets.all(12.r),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12.r),
                  child: SizedBox(
                    width: 58.r,
                    height: 58.r,
                    child: switch (item.type) {
                      ItemType.image => _Thumb(item: item),
                      ItemType.video when item.displayThumbnail != null =>
                        _Thumb(item: item),
                      ItemType.link =>
                        _LinkCell(item: item, color: anchorColor),
                      _ => _TypeCell(type: item.type, color: anchorColor),
                    },
                  ),
                ),
                SizedBox(width: 12.w),
                // Info column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleFor(item),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          Container(
                            width: 8.r,
                            height: 8.r,
                            decoration: BoxDecoration(
                              color: anchorColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 5.w),
                          Expanded(
                            child: Text(
                              entry.anchorName,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.sp,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 7.h),
                      _SyncStatusBadge(status: item.syncStatus),
                    ],
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

// ─── Sync Status Badge ────────────────────────────────────────────────────────

class _SyncStatusBadge extends StatelessWidget {
  final SyncStatus status;
  const _SyncStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      SyncStatus.synced =>
        (AppColors.success, CupertinoIcons.checkmark_circle_fill, 'Synced'),
      SyncStatus.uploading => (
          const Color(0xFFFF9500),
          CupertinoIcons.arrow_up_circle_fill,
          'Uploading'
        ),
      SyncStatus.pending =>
        (AppColors.accentSoft, CupertinoIcons.clock_fill, 'Pending'),
      SyncStatus.failed =>
        (AppColors.danger, CupertinoIcons.xmark_circle_fill, 'Failed'),
      SyncStatus.na =>
        (AppColors.textTertiary, CupertinoIcons.checkmark_circle, 'Saved'),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == SyncStatus.uploading)
            SizedBox(
              width: 10.r,
              height: 10.r,
              child: CupertinoActivityIndicator(radius: 5.r, color: color),
            )
          else
            Icon(icon, size: 10.sp, color: color),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
