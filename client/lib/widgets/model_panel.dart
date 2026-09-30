import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';

const Map<String, String> providerLabels = {
  'openai': 'OpenAI',
  'anthropic': 'Anthropic',
  'gemini': 'Google Gemini',
};

const Map<String, IconData> providerIcons = {
  'openai': Icons.circle_outlined,
  'anthropic': Icons.change_history,
  'gemini': Icons.auto_awesome,
};

/// Floating panel docked to the right edge of the screen. Scrollable list of
/// models grouped by provider; only providers with a saved API key show up.
class ModelPanel extends StatelessWidget {
  final ProvidersStatus status;
  final String? selectedModelId;
  final ValueChanged<ModelInfo> onSelect;
  final VoidCallback onOpenSettings;

  const ModelPanel({
    super.key,
    required this.status,
    required this.selectedModelId,
    required this.onSelect,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<ModelInfo>>{};
    for (final m in status.availableModels) {
      grouped.putIfAbsent(m.provider, () => []).add(m);
    }

    return Container(
      width: 260,
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.smart_toy_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text('Model', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Tooltip(
                  message: 'API keys',
                  child: InkWell(
                    onTap: onOpenSettings,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.key_outlined, size: 16, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: grouped.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('No API keys configured yet.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: onOpenSettings,
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add an API key', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  )
                : Scrollbar(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: grouped.entries.expand((entry) {
                        return [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                            child: Row(
                              children: [
                                Icon(providerIcons[entry.key] ?? Icons.circle,
                                    size: 12, color: AppColors.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  providerLabels[entry.key] ?? entry.key,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMuted,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...entry.value.map((m) => _ModelTile(
                                model: m,
                                selected: m.id == selectedModelId,
                                onTap: () => onSelect(m),
                              )),
                        ];
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final ModelInfo model;
  final bool selected;
  final VoidCallback onTap;
  const _ModelTile({required this.model, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? AppColors.accent : AppColors.textPrimary,
                      )),
                  if (model.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(model.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                    ),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, size: 14, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
