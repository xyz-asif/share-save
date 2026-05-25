import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/anchors_provider.dart';

class CreateAnchorSheet extends ConsumerStatefulWidget {
  const CreateAnchorSheet({super.key});

  @override
  ConsumerState<CreateAnchorSheet> createState() => _CreateAnchorSheetState();
}

class _CreateAnchorSheetState extends ConsumerState<CreateAnchorSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int _selectedColorIndex = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      final anchor = await ref.read(anchorsProvider.notifier).add(
            name: name,
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            colorValue:
                AppColors.anchorPalette[_selectedColorIndex].toARGB32(),
          );
      if (mounted) Navigator.pop(context, anchor);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _nameCtrl.text.trim().isNotEmpty && !_saving;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: Color(0x15000000), blurRadius: 30, offset: Offset(0, -4)),
        ],
      ),
      padding:
          EdgeInsets.fromLTRB(20, 12, 20, bottom == 0 ? 36 : bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 22),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text('New Anchor',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const SizedBox(height: 4),
          const Text('Name it and pick a colour',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 15),
            decoration: const InputDecoration(hintText: 'Anchor name'),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 15),
            decoration:
                const InputDecoration(hintText: 'Description (optional)'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 22),
          const Text('COLOUR',
              style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          _ColorRow(
            selectedIndex: _selectedColorIndex,
            onSelect: (i) {
              HapticFeedback.selectionClick();
              setState(() => _selectedColorIndex = i);
            },
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canCreate ? _create : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor:
                    AppColors.accent.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Create Anchor',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  const _ColorRow({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(AppColors.anchorPalette.length, (i) {
        final color = AppColors.anchorPalette[i];
        final selected = selectedIndex == i;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: selected ? 36 : 30,
            height: selected ? 36 : 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: Colors.white, width: 2.5)
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ]
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 15)
                : null,
          ),
        );
      }),
    );
  }
}
