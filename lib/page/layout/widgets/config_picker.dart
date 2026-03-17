import 'package:flutter/material.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/generated/app_localizations.dart';

class ConfigPicker extends StatelessWidget {
  const ConfigPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final modelConfigProvider = ProviderManager.modelConfigProvider;
    final selectedConfig = modelConfigProvider.getSelectedConfig();

    return GestureDetector(
      onTap: () => _showConfigPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withAlpha(51),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedConfig?.label ?? l10n.modelConfig,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  void _showConfigPicker(BuildContext context) {
    final modelConfigProvider = ProviderManager.modelConfigProvider;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setSheetState) {
          final currentSelected = modelConfigProvider.getSelectedConfig();
          final configs = modelConfigProvider.configs;

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
                        'Model Configuration',
                        style: Theme.of(builderContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
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
                            : const Icon(Icons.tune, size: 20),
                        title: Text(
                          config.label,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: config.description != null
                            ? Text(
                                config.description!,
                                style: Theme.of(builderContext).textTheme.bodySmall,
                              )
                            : null,
                        trailing: config.settings.maxTokens != null
                            ? Text(
                                '${config.settings.temperature.toStringAsFixed(1)}° • ${config.settings.maxTokens} tokens',
                                style: Theme.of(builderContext).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(builderContext).colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontSize: 11,
                                    ),
                              )
                            : null,
                        onTap: () async {
                          await modelConfigProvider.selectConfig(config.id);
                          if (listContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}
