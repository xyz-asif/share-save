import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../models/anchor_item_model.dart';
import '../../models/anchor_model.dart';
import '../../providers/anchor_items_provider.dart';
import '../../providers/anchors_provider.dart';
import '../create_anchor/create_anchor_sheet.dart';
import 'shared_data.dart';

class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen>
    with SingleTickerProviderStateMixin {
  static const _channel =
      MethodChannel('com.asif.anchors/share');

  SharedData? _sharedData;
  AnchorModel? _selectedAnchor;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
    _loadSharedData();
  }

  Future<void> _loadSharedData() async {
    try {
      final data =
          await _channel.invokeMapMethod<dynamic, dynamic>('getSharedData');
      if (data != null && mounted) {
        final shared = SharedData.fromMap(data);
        final autoTitle = shared.subject ??
            (shared.type == ItemType.link
                ? _extractDomain(shared.text ?? '')
                : null) ??
            (shared.type == ItemType.text
                ? _truncate(shared.text ?? '', 40)
                : null);
        if (autoTitle != null) _titleCtrl.text = autoTitle;
        setState(() {
          _sharedData = shared;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _extractDomain(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  Future<void> _save() async {
    if (_selectedAnchor == null || _sharedData == null) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      final data = _sharedData!;
      final anchorId = _selectedAnchor!.id;
      final title =
          _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();
      final desc =
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();

      // Use the notifier so items are saved to both SQLite and Firestore.
      final notifier =
          ref.read(anchorItemsProvider(anchorId).notifier);

      if (data.type == ItemType.link || data.type == ItemType.text) {
        await notifier.addItem(
          type: data.type,
          title: title,
          description: desc,
          content: data.text ?? '',
          mimeType: data.mimeType,
        );
      } else {
        for (final path in data.uris) {
          if (path.isEmpty) continue;
          await notifier.addItem(
            type: data.type,
            title: title,
            description: desc,
            content: path,
            originalFilename: path.split('/').last,
            mimeType: data.mimeType,
          );
        }
      }
      ref.invalidate(anchorsProvider);
      _close();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _close() {
    _slideCtrl.reverse().then((_) => _channel.invokeMethod('close'));
  }

  Future<void> _createNewAnchor() async {
    final anchor = await showModalBottomSheet<AnchorModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateAnchorSheet(),
    );
    if (anchor != null) setState(() => _selectedAnchor = anchor);
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchors = ref.watch(anchorsProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {},
                child: SlideTransition(
                  position: _slideAnim,
                  child: _buildSheet(anchors),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheet(List<AnchorModel> anchors) {
    final bottom = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Color(0x18000000), blurRadius: 30, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 24),
              child: _loading ? _buildLoading() : _buildContent(anchors),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 52),
        child: Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2),
        ),
      );

  Widget _buildContent(List<AnchorModel> anchors) {
    if (_sharedData == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 52),
        child: Center(
          child: Text('Nothing to save',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Save to Anchor',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3)),
        const SizedBox(height: 4),
        const Text('Pick an anchor and give it a name',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 18),
        _ContentPreview(data: _sharedData!),
        const SizedBox(height: 16),
        TextField(
          controller: _titleCtrl,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 15),
          decoration: const InputDecoration(hintText: 'Name'),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 15),
          decoration:
              const InputDecoration(hintText: 'Description (optional)'),
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
        ),
        const SizedBox(height: 22),
        const Text('SAVE TO',
            style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        _AnchorPicker(
          anchors: anchors,
          selected: _selectedAnchor,
          onSelect: (a) => setState(() => _selectedAnchor = a),
          onCreateNew: _createNewAnchor,
        ),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _close,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: (_selectedAnchor != null && !_saving) ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor:
                    AppColors.accent.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ]),
      ],
    );
  }
}

// ─── Content preview ──────────────────────────────────────────────────────────

class _ContentPreview extends StatelessWidget {
  final SharedData data;
  const _ContentPreview({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        _typeIcon(),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            data.displayContent,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _typeIcon() {
    final (icon, color) = switch (data.type) {
      ItemType.link  => (Icons.link_rounded,              AppColors.accent),
      ItemType.image => (Icons.image_rounded,              const Color(0xFF4CAF50)),
      ItemType.video => (Icons.videocam_rounded,           const Color(0xFFFF9500)),
      ItemType.audio => (Icons.audiotrack_rounded,         const Color(0xFFE91E8C)),
      ItemType.text  => (Icons.text_fields_rounded,        const Color(0xFF00BCD4)),
      ItemType.file  => (Icons.insert_drive_file_rounded,  AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

// ─── Anchor picker ────────────────────────────────────────────────────────────

class _AnchorPicker extends StatelessWidget {
  final List<AnchorModel> anchors;
  final AnchorModel? selected;
  final ValueChanged<AnchorModel> onSelect;
  final VoidCallback onCreateNew;

  const _AnchorPicker({
    required this.anchors,
    required this.selected,
    required this.onSelect,
    required this.onCreateNew,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _NewAnchorChip(onTap: onCreateNew),
          const SizedBox(width: 8),
          ...anchors.map((a) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _AnchorChip(
                  anchor: a,
                  isSelected: selected?.id == a.id,
                  onTap: () => onSelect(a),
                ),
              )),
        ],
      ),
    );
  }
}

class _AnchorChip extends StatelessWidget {
  final AnchorModel anchor;
  final bool isSelected;
  final VoidCallback onTap;
  const _AnchorChip(
      {required this.anchor, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 84,
        decoration: BoxDecoration(
          color: isSelected
              ? anchor.color.withValues(alpha: 0.12)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? anchor.color : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: anchor.color.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: anchor.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.anchor_rounded, color: anchor.color, size: 15),
            ),
            Text(
              anchor.name,
              style: TextStyle(
                color: isSelected
                    ? anchor.color
                    : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _NewAnchorChip extends StatelessWidget {
  final VoidCallback onTap;
  const _NewAnchorChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          color: AppColors.accentDim,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.add_rounded,
                  color: AppColors.accent, size: 16),
            ),
            const Text('New',
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
