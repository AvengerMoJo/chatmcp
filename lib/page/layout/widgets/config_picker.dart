import 'package:flutter/material.dart';
import 'package:chatmcp/model/model_config.dart';
import 'package:chatmcp/provider/model_config_provider.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/generated/app_localizations.dart';

class ConfigPicker extends StatelessWidget {
  const ConfigPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final modelConfigProvider = ProviderManager.modelConfigProvider;
    final currentModel = ProviderManager.chatModelProvider.currentModel;

    final configs = modelConfigProvider.configs;
    final selectedConfig = modelConfigProvider.getSelectedConfig();

    return DropdownButton<String>(
      value: selectedConfig?.id,
      hint: Text(l10n.modelConfig),
      icon: const Icon(Icons.tune, size: 18),
      items: configs.map((config) {
        return DropdownMenuItem<String>(
          value: config.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(config.label, style: Theme.of(context).textTheme.bodyMedium),
                    if (config.description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          config.description!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 11),
                        ),
                      ),
                    if (config.settings.maxTokens != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${config.settings.temperature.toStringAsFixed(1)}° • ${config.settings.maxTokens} tokens',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selectedConfig?.id == config.id) const Icon(Icons.check, size: 16),
            ],
          ),
        );
      }).toList(),
      onChanged: (configId) {
        if (configId != null) {
          modelConfigProvider.selectConfig(configId!);
        }
      },
    );
  }
}
