import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';

/// Folder picker for choosing the agent's working directory.
///
/// Design note: the final Windows Desktop build should use the native
/// Win32/Shell "Browse for folder" dialog for a truly native feel. Since this
/// preview runs in a Linux sandbox (no native Windows dialog available), we
/// ship a polished in-app browser that talks to the same backend endpoint
/// (`/workspace/browse`) the native picker would eventually confirm against
/// via `/workspace/select`. Swapping in `FilePicker.platform.getDirectoryPath()`
/// on Windows is a drop-in replacement for this dialog's body.
class FolderPickerDialog extends StatefulWidget {
  final ApiClient api;
  final String? initialPath;
  const FolderPickerDialog({super.key, required this.api, this.initialPath});

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  BrowseResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(widget.initialPath);
  }

  Future<void> _load(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.browse(path);
      setState(() {
        _result = res;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 480,
        height: 520,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                const Text('Select working folder',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The agent will only read/act inside this folder in Build mode.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_result != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_result!.currentPath,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.blocked)))
                      : _buildList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _result == null ? null : () => Navigator.pop(context, _result!.currentPath),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Use this folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final entries = _result!.entries;
    return ListView(
      children: [
        if (_result!.parentPath != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward, size: 18, color: AppColors.textMuted),
            title: const Text('.. (parent folder)', style: TextStyle(fontSize: 13)),
            onTap: () => _load(_result!.parentPath),
          ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No subfolders here.', style: TextStyle(color: AppColors.textMuted)),
          ),
        ...entries.map((e) => ListTile(
              dense: true,
              leading: const Icon(Icons.folder, size: 18, color: AppColors.accent),
              title: Text(e.name, style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
              onTap: () => _load(e.path),
            )),
      ],
    );
  }
}
