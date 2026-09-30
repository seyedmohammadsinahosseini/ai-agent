import 'package:flutter/material.dart';
import '../theme.dart';
import '../models_ui.dart';

/// Segmented Plan / Build switch, always visible right next to the input box.
class ModeSwitch extends StatelessWidget {
  final AgentMode mode;
  final ValueChanged<AgentMode> onChanged;
  const ModeSwitch({super.key, required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, AgentMode.plan, Icons.map_outlined, AppColors.planColor),
          _segment(context, AgentMode.build, Icons.build_outlined, AppColors.buildColor),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, AgentMode value, IconData icon, Color color) {
    final selected = mode == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? color : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              value.label,
              style: TextStyle(
                color: selected ? color : AppColors.textMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
