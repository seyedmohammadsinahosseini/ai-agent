import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';
import 'model_panel.dart';

/// Separate settings dialog for BYOK API key management, kept distinct from
/// the model-selection floating panel (which is purely for picking a model
/// among providers that already have a key configured).
///
/// Two ways to connect a provider:
///  1. One of the built-in presets (OpenAI / Anthropic / Gemini).
///  2. Any other OpenAI-API-compatible service, by typing its base URL
///     (Groq, OpenRouter, Together, DeepSeek, a self-hosted Ollama/LM
///     Studio server, etc.) - the app tries to auto-detect which models
///     the key can access.
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
  List<CustomProviderInfo> _customProviders = [];
  bool _loading = true;

  // Custom provider form state.
  final _customLabelController = TextEditingController();
  final _customUrlController = TextEditingController();
  final _customKeyController = TextEditingController();
  final _customModelController = TextEditingController();
  bool _customObscure = true;
  bool _connectingCustom = false;
  String? _customStatus;
  bool _customIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _customLabelController.dispose();
    _customUrlController.dispose();
    _customKeyController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await widget.api.providersStatus();
      setState(() {
        _configured = result.configuredProviders;
        _customProviders = result.customProviders;
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

  Future<void> _connectCustom() async {
    final label = _customLabelController.text.trim();
    final url = _customUrlController.text.trim();
    final key = _customKeyController.text.trim();
    if (label.isEmpty || url.isEmpty || key.isEmpty) {
      setState(() {
        _customStatus = 'Name, base URL, and API key are all required.';
        _customIsError = true;
      });
      return;
    }
    setState(() {
      _connectingCustom = true;
      _customStatus = null;
    });
    try {
      final info = await widget.api.addCustomProvider(
        label: label,
        baseUrl: url,
        apiKey: key,
        model: _customModelController.text,
      );
      setState(() {
        _customStatus = 'Connected "${info.label}" — detected ${info.models.length} '
            'model${info.models.length == 1 ? '' : 's'}.';
        _customIsError = false;
        _connectingCustom = false;
      });
      _customLabelController.clear();
      _customUrlController.clear();
      _customKeyController.clear();
      _customModelController.clear();
      await _load();
      widget.onKeysChanged();
    } catch (e) {
      setState(() {
        _customStatus = e.toString().replaceFirst('Exception: ', '');
        _customIsError = true;
        _connectingCustom = false;
      });
    }
  }

  Future<void> _removeCustom(String id) async {
    try {
      await widget.api.deleteCustomProvider(id);
      await _load();
      widget.onKeysChanged();
    } catch (_) {}
  }

  Future<void> _removeBuiltIn(String provider) async {
    try {
      await widget.api.deleteApiKey(provider);
      setState(() {
        _status = '${providerLabels[provider] ?? provider} key removed. Add a new one below whenever you like.';
        _isError = false;
      });
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
        width: 480,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key_outlined, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                const Text('API Keys & Providers',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Your keys are stored securely on this device only, and sent directly to the '
              'provider you choose. They are never sent anywhere else.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Well-known providers',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                              color: AppColors.textMuted, letterSpacing: 0.4)),
                      const SizedBox(height: 4),
                      const Text(
                        'A key already saved? Tap the × to remove it and connect a different one.',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 8),
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
                            deleteIcon: isConfigured ? const Icon(Icons.close, size: 14) : null,
                            onDeleted: isConfigured ? () => _removeBuiltIn(p) : null,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: const Text('Save key'),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Divider(height: 1),
                      const SizedBox(height: 18),
                      Row(
                        children: const [
                          Icon(Icons.hub_outlined, size: 15, color: AppColors.textSecondary),
                          SizedBox(width: 6),
                          Text('Connect any other provider by URL',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Works with any OpenAI-API-compatible service - Groq, OpenRouter, '
                        'Together, DeepSeek, a self-hosted Ollama/LM Studio server, etc. '
                        'Leave "Model" blank and we\'ll try to auto-detect which models your '
                        'key can access.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customLabelController,
                        decoration: const InputDecoration(labelText: 'Name (e.g. "Groq")'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          hintText: 'https://api.groq.com/openai/v1',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customKeyController,
                        obscureText: _customObscure,
                        decoration: InputDecoration(
                          labelText: 'API key',
                          suffixIcon: IconButton(
                            icon: Icon(_customObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                            onPressed: () => setState(() => _customObscure = !_customObscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customModelController,
                        decoration: const InputDecoration(
                          labelText: 'Model (optional - auto-detect if blank)',
                          hintText: 'llama-3.3-70b-versatile',
                        ),
                      ),
                      if (_customStatus != null) ...[
                        const SizedBox(height: 10),
                        Text(_customStatus!,
                            style: TextStyle(
                                color: _customIsError ? AppColors.blocked : AppColors.safe, fontSize: 12)),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _connectingCustom ? null : _connectCustom,
                          icon: _connectingCustom
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.link, size: 16),
                          label: const Text('Connect provider'),
                        ),
                      ),
                      if (_customProviders.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text('Connected custom providers',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                color: AppColors.textMuted, letterSpacing: 0.4)),
                        const SizedBox(height: 8),
                        ..._customProviders.map((p) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.hub_outlined, size: 14, color: AppColors.safe),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                        Text(
                                          '${p.baseUrl} · ${p.models.length} model${p.models.length == 1 ? '' : 's'}',
                                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textMuted),
                                    tooltip: 'Remove',
                                    onPressed: () => _removeCustom(p.id),
                                  ),
                                ],
                              ),
                            )),
                      ],
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
