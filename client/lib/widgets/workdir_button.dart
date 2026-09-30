import 'package:flutter/material.dart';
import '../theme.dart';

/// Small pill button shown above the input bar letting the user pick / see
/// the agent's current working folder.
class WorkdirButton extends StatelessWidget {
  final String? workingDir;
  final VoidCallback onTap;
  const WorkdirButton({super.key, required this.workingDir, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasDir = workingDir != null && workingDir!.isNotEmpty;
    final displayName = hasDir ? workingDir!.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasDir ? AppColors.buildColor.withValues(alpha: 0.10) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasDir ? AppColors.buildColor.withValues(alpha: 0.35) : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined, size: 14, color: hasDir ? AppColors.buildColor : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              hasDir ? displayName! : 'No folder selected',
              style: TextStyle(
                fontSize: 12,
                color: hasDir ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.unfold_more, size: 12, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
