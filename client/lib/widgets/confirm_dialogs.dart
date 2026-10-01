import 'package:flutter/material.dart';
import '../theme.dart';

const String dangerousConfirmationPhrase = 'I understand, run it';

Future<bool?> showSimpleConfirmDialog(BuildContext context, {required String command, required String reason}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Row(
        children: [
          Icon(Icons.help_outline, color: AppColors.confirm, size: 20),
          SizedBox(width: 8),
          Text('Confirm this action'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason, style: const TextStyle(fontSize: 13.5)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
                child: SingleChildScrollView(
                  child: SelectableText(command, style: monoStyle(fontSize: 12.5)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.confirm, foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Run it'),
        ),
      ],
    ),
  );
}

Future<String?> showDangerousConfirmDialog(BuildContext context, {required String command, required String reason}) {
  final controller = TextEditingController();
  return showDialog<String?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final matches = controller.text.trim() == dangerousConfirmationPhrase;
        return AlertDialog(
          backgroundColor: const Color(0xFF241416),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.dangerous, width: 1),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.dangerous, size: 22),
              SizedBox(width: 8),
              Text('Dangerous action'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reason, style: const TextStyle(fontSize: 13.5)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: SingleChildScrollView(
                      child: SelectableText(command, style: monoStyle(fontSize: 12.5)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('To confirm, type the phrase below exactly:',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                SelectableText('"$dangerousConfirmationPhrase"',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.dangerous),
              onPressed: matches ? () => Navigator.pop(ctx, controller.text.trim()) : null,
              child: const Text('Run it'),
            ),
          ],
        );
      },
    ),
  );
}

Future<bool?> showStopConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Row(
        children: [
          Icon(Icons.stop_circle_outlined, color: AppColors.blocked, size: 20),
          SizedBox(width: 8),
          Text('Stop the agent?'),
        ],
      ),
      content: const Text(
        'Are you sure you want to stop the current action? Anything in progress will be interrupted immediately.',
        style: TextStyle(fontSize: 13.5),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep running')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.blocked),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Stop'),
        ),
      ],
    ),
  );
}
