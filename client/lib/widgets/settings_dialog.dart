import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';
import 'model_panel.dart';

/// Separate settings dialog for BYOK API key management, kept distinct from
/// the model-selection floating panel (which is purely for picking a model
/// among providers that already have a key configured).
class SettingsDialog extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onKeysChanged;
  const SettingsDialog({super.key, required this.api, required this.onKeysChanged});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  String _provider = 'openai';
  final _keyController = TextEditingController();
  bool _obscure = true;
  String? _status;
  bool _isError = false;
  List<String> _configured = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.api.providersStatus();
      setState(() {
        _configured = result.configuredProviders;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_keyController.text.trim().isEmpty) return;
    try {
      await widget.api.saveApiKey(_provider, _keyController.text.trim());
      setState(() {
        _status = 'API key saved and encrypted on this device.';
        _isError = false;
      });
      _keyController.clear();
      await _load();
      widget.onKeysChanged();
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key_outlined, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                const Text('API Keys (Bring your own key)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Your key is stored securely on this device only, and sent directly to the '
              'provider you choose. It is never sent anywhere else.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['openai', 'anthropic', 'gemini'].map((p) {
                  final isConfigured = _configured.contains(p);
                  return Chip(
                    avatar: Icon(providerIcons[p] ?? Icons.circle, size: 14,
                        color: isConfigured ? AppColors.safe : AppColors.textMuted),
                    label: Text(providerLabels[p] ?? p, style: const TextStyle(fontSize: 12)),
                    backgroundColor: isConfigured
                        ? AppColors.safe.withValues(alpha: 0.12)
                        : AppColors.surface,
                    side: BorderSide(color: isConfigured ? AppColors.safe.withValues(alpha: 0.4) : AppColors.border),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: providerLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _provider = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'API key',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(_status!,
                    style: TextStyle(color: _isError ? AppColors.blocked : AppColors.safe, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save key'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
