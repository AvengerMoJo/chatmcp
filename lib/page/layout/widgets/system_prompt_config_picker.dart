import 'package:flutter/material.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/generated/app_localizations.dart';

class SystemPromptConfigPicker extends StatelessWidget {
  const SystemPromptConfigPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final systemPromptConfigProvider = ProviderManager.systemPromptConfigProvider;

    return ListenableBuilder(
      listenable: systemPromptConfigProvider,
      builder: (context, child) {
        final selectedConfig = systemPromptConfigProvider.getSelectedConfig();

        return GestureDetector(
          onTap: () => _showConfigPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(51)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(selectedConfig?.label ?? l10n.systemPrompt, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showConfigPicker(BuildContext context) {
    final systemPromptConfigProvider = ProviderManager.systemPromptConfigProvider;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setSheetState) {
          final currentSelected = systemPromptConfigProvider.getSelectedConfig();
          final configs = systemPromptConfigProvider.configs;

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(builderContext).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(builderContext).colorScheme.onSurface.withAlpha(51),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'System Prompt Configuration',
                        style: Theme.of(builderContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetContext)),
                    ],
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: configs.length,
                    itemBuilder: (listContext, index) {
                      final config = configs[index];
                      final isSelected = currentSelected?.id == config.id;

                      return ListTile(
                        leading: isSelected
                            ? Icon(Icons.check, color: Theme.of(builderContext).colorScheme.primary)
                            : const Icon(Icons.text_fields, size: 20),
                        title: Text(config.label, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                        subtitle: config.description != null ? Text(config.description!, style: Theme.of(builderContext).textTheme.bodySmall) : null,
                        onTap: () async {
                          final prompt = systemPromptConfigProvider.applyConfig(config.id);
                          await ProviderManager.settingsProvider.updateGeneralSettingsPartially(systemPrompt: prompt);
                          await systemPromptConfigProvider.selectConfig(config.id);
                          if (listContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      );
                    },
                  ),
                ),
                if (currentSelected != null && currentSelected.isCustom) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmDelete(context, sheetContext, systemPromptConfigProvider, currentSelected.label),
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        label: const Text('Delete Configuration', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, dynamic sheetContext, dynamic systemPromptConfigProvider, String configName) {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.saveConfiguration),
        content: Text('Are you sure you want to delete "$configName"? This will reset to Default.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              Navigator.pop(sheetContext);
              await systemPromptConfigProvider.deleteConfig(systemPromptConfigProvider.selectedConfigId!);
              await systemPromptConfigProvider.resetToDefault();
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
