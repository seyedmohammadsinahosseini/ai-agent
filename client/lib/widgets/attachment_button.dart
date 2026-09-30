import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

class PendingAttachment {
  final String filename;
  final Uint8List bytes;
  final String kind; // 'context' or 'workspace'
  PendingAttachment({required this.filename, required this.bytes, required this.kind});
}

/// Paperclip-style attach button above the message input. Lets the user pick
/// a file and choose whether it's just context for the AI to read, or should
/// be copied into the selected working folder for the agent to act on.
class AttachmentButton extends StatelessWidget {
  final bool workspaceSelected;
  final ValueChanged<PendingAttachment> onAttached;

  const AttachmentButton({super.key, required this.workspaceSelected, required this.onAttached});

  Future<void> _pickAndChoose(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    if (!context.mounted) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(file.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: AppColors.accent),
                title: const Text('Use as context for the AI'),
                subtitle: const Text('The assistant can read and discuss this file, nothing is changed on disk.',
                    style: TextStyle(fontSize: 11.5)),
                onTap: () => Navigator.pop(ctx, 'context'),
              ),
              ListTile(
                enabled: workspaceSelected,
                leading: Icon(Icons.drive_folder_upload_outlined,
                    color: workspaceSelected ? AppColors.buildColor : AppColors.textMuted),
                title: const Text('Add to the working folder'),
                subtitle: Text(
                  workspaceSelected
                      ? 'Copies the file into the selected folder so the agent can act on it.'
                      : 'Select a working folder first to enable this.',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onTap: workspaceSelected ? () => Navigator.pop(ctx, 'workspace') : null,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );

    if (kind == null) return;
    onAttached(PendingAttachment(filename: file.name, bytes: file.bytes!, kind: kind));
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Attach a file',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pickAndChoose(context),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.attach_file_rounded, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
