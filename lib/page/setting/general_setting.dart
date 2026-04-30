import 'package:chatmcp/components/widgets/base.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../provider/settings_provider.dart';
import 'package:chatmcp/generated/app_localizations.dart';
import 'package:chatmcp/utils/platform.dart';
import 'package:chatmcp/utils/toast.dart';
import 'package:chatmcp/file_logger.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/page/layout/widgets/system_prompt_config_picker.dart';

import 'setting_switch.dart';

class GeneralSettings extends StatefulWidget {
  const GeneralSettings({super.key});

  @override
  State<GeneralSettings> createState() => _GeneralSettingsState();
}

class _GeneralSettingsState extends State<GeneralSettings> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _systemPromptController = TextEditingController();

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      const SizedBox(height: 10),
                      _buildThemeCard(context),
                      _buildLocaleCard(context),
                      _buildAvatarCard(context),
                      _buildNewLineKeyCard(context),
                      if (!kIsBrowser) _buildProxyCard(context),
                      _buildSystemPromptCard(context),
                      if (!kIsBrowser) _buildMaintenanceCard(context),
                      _buildMojoVoiceCard(context),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildLocaleCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, l10n.languageSettings, CupertinoIcons.globe),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
              ),
              child: ListTile(
                title: CText(text: l10n.language),
                trailing: DropdownButton<String>(
                  value: settings.generalSetting.locale,
                  underline: const SizedBox(),
                  icon: Icon(CupertinoIcons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurface.withAlpha(50)),
                  items: const [
                    DropdownMenuItem(
                      value: 'en',
                      child: CText(text: 'English'),
                    ),
                    DropdownMenuItem(
                      value: 'zh',
                      child: CText(text: '中文'),
                    ),
                    DropdownMenuItem(
                      value: 'tr',
                      child: CText(text: 'Türkçe'),
                    ),
                    DropdownMenuItem(
                      value: 'de',
                      child: CText(text: 'Deutsch'),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value != null) {
                      settings.updateGeneralSettingsPartially(locale: value);
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, l10n.themeSettings, CupertinoIcons.paintbrush),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 1.0),
                child: DropdownButtonFormField<String>(
                  value: settings.generalSetting.theme,
                  decoration: InputDecoration(border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 2.0)),
                  icon: Icon(CupertinoIcons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurface.withAlpha(50)),
                  items: [
                    DropdownMenuItem(
                      value: 'light',
                      child: CText(text: l10n.lightTheme),
                    ),
                    DropdownMenuItem(
                      value: 'dark',
                      child: CText(text: l10n.darkTheme),
                    ),
                    DropdownMenuItem(
                      value: 'system',
                      child: CText(text: l10n.followSystem),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      settings.updateGeneralSettingsPartially(theme: value);
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvatarCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, l10n.showAvatar, CupertinoIcons.person_crop_circle),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
              ),
              child: Column(
                children: [
                  SettingSwitch(
                    title: l10n.showAssistantAvatar,
                    subtitle: l10n.showAssistantAvatarDescription,
                    value: settings.generalSetting.showAssistantAvatar,
                    titleFontSize: 14,
                    subtitleFontSize: 12,
                    onChanged: (bool value) {
                      settings.updateGeneralSettingsPartially(showAssistantAvatar: value);
                    },
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: Theme.of(context).colorScheme.outline.withAlpha(50)),
                  SettingSwitch(
                    title: l10n.showUserAvatar,
                    subtitle: l10n.showUserAvatarDescription,
                    value: settings.generalSetting.showUserAvatar,
                    titleFontSize: 14,
                    subtitleFontSize: 12,
                    onChanged: (bool value) {
                      settings.updateGeneralSettingsPartially(showUserAvatar: value);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNewLineKeyCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, l10n.inputSettings, CupertinoIcons.keyboard),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
              ),
              child: ListTile(
                title: CText(text: l10n.newLineKey),
                subtitle: CText(text: l10n.newLineKeyDescription),
                trailing: DropdownButton<NewLineKey>(
                  value: settings.generalSetting.newLineKey,
                  underline: const SizedBox(),
                  icon: Icon(CupertinoIcons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurface.withAlpha(50)),
                  items: const [
                    DropdownMenuItem(
                      value: NewLineKey.ctrlEnter,
                      child: CText(text: 'Ctrl+Enter'),
                    ),
                    DropdownMenuItem(
                      value: NewLineKey.shiftEnter,
                      child: CText(text: 'Shift+Enter'),
                    ),
                    DropdownMenuItem(
                      value: NewLineKey.ctrlShiftEnter,
                      child: CText(text: 'Ctrl+Shift+Enter'),
                    ),
                  ],
                  onChanged: (NewLineKey? value) {
                    if (value != null) {
                      settings.updateGeneralSettingsPartially(newLineKey: value);
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProxyCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, l10n.proxySettings, CupertinoIcons.globe),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 启用代理开关
                    SettingSwitch(
                      title: l10n.enableProxy,
                      subtitle: l10n.enableProxyDescription,
                      value: settings.generalSetting.enableProxy,
                      titleFontSize: 14,
                      subtitleFontSize: 12,
                      onChanged: (bool value) {
                        settings.updateGeneralSettingsPartially(enableProxy: value);
                        ToastUtils.success(l10n.saved);
                      },
                    ),

                    // 如果启用代理，显示代理配置选项
                    if (settings.generalSetting.enableProxy) ...[
                      const SizedBox(height: 16),
                      Divider(height: 1, color: Theme.of(context).colorScheme.outline.withAlpha(50)),
                      const SizedBox(height: 16),

                      // 代理类型选择
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              l10n.proxyType,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: settings.generalSetting.proxyType,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(20)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'HTTP',
                                  child: CText(text: 'HTTP'),
                                ),
                                DropdownMenuItem(
                                  value: 'HTTPS',
                                  child: CText(text: 'HTTPS'),
                                ),
                                DropdownMenuItem(
                                  value: 'SOCKS4',
                                  child: CText(text: 'SOCKS4'),
                                ),
                                DropdownMenuItem(
                                  value: 'SOCKS5',
                                  child: CText(text: 'SOCKS5'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  settings.updateGeneralSettingsPartially(proxyType: value);
                                  ToastUtils.success(l10n.saved);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 代理地址和端口
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: settings.generalSetting.proxyHost,
                              decoration: InputDecoration(
                                labelText: l10n.proxyHost,
                                hintText: l10n.enterProxyHost,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                              validator: (value) {
                                if (settings.generalSetting.enableProxy && (value == null || value.isEmpty)) {
                                  return l10n.proxyHostRequired;
                                }
                                return null;
                              },
                              onChanged: (value) {
                                settings.updateGeneralSettingsPartially(proxyHost: value);
                                if (value.isNotEmpty) {
                                  ToastUtils.success(l10n.saved);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              initialValue: settings.generalSetting.proxyPort.toString(),
                              decoration: InputDecoration(
                                labelText: l10n.proxyPort,
                                hintText: l10n.enterProxyPort,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return null;
                                }
                                final port = int.tryParse(value);
                                if (port == null || port < 1 || port > 65535) {
                                  return l10n.proxyPortInvalid;
                                }
                                return null;
                              },
                              onChanged: (value) {
                                final port = int.tryParse(value);
                                if (port != null && port >= 1 && port <= 65535) {
                                  settings.updateGeneralSettingsPartially(proxyPort: port);
                                  ToastUtils.success(l10n.saved);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 用户名和密码（可选）
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: settings.generalSetting.proxyUsername,
                              decoration: InputDecoration(
                                labelText: l10n.proxyUsername,
                                hintText: l10n.enterProxyUsername,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                              onChanged: (value) {
                                settings.updateGeneralSettingsPartially(proxyUsername: value);
                                ToastUtils.success(l10n.saved);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: settings.generalSetting.proxyPassword,
                              decoration: InputDecoration(
                                labelText: l10n.proxyPassword,
                                hintText: l10n.enterProxyPassword,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                              obscureText: true,
                              onChanged: (value) {
                                settings.updateGeneralSettingsPartially(proxyPassword: value);
                                ToastUtils.success(l10n.saved);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSystemPromptCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        // Only update controller text if it's significantly different to avoid cursor jumping
        if (_systemPromptController.text != settings.generalSetting.systemPrompt) {
          _systemPromptController.text = settings.generalSetting.systemPrompt;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, l10n.systemPrompt, CupertinoIcons.text_quote),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(26), width: 1),
                          boxShadow: [
                            BoxShadow(color: Theme.of(context).colorScheme.shadow.withAlpha(13), blurRadius: 10, offset: const Offset(0, 2)),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.text_fields, size: 18, color: Color(0xFF78909C)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Prompt Configuration', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Color(0xFF78909C))),
                            ),
                            const SizedBox(width: 8),
                            const SystemPromptConfigPicker(),
                          ],
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _systemPromptController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(20)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(20)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                      maxLines: 5,
                      onChanged: (value) {
                        settings.updateGeneralSettingsPartially(systemPrompt: value);
                        ProviderManager.systemPromptConfigProvider.syncToSelectedConfig(value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.systemPromptDescription, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withAlpha(60))),
                    const SizedBox(height: 12),
                    _buildSystemPromptActionButtons(context),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSystemPromptActionButtons(BuildContext context) {
    return ListenableBuilder(
      listenable: ProviderManager.systemPromptConfigProvider,
      builder: (context, child) {
        final systemPromptConfigProvider = ProviderManager.systemPromptConfigProvider;
        final selectedConfig = systemPromptConfigProvider.getSelectedConfig();
        final isCustomConfigSelected = selectedConfig?.isCustom ?? false;

        return Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isCustomConfigSelected)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(51), width: 1),
                  ),
                  child: TextButton.icon(
                    onPressed: () async {
                      await systemPromptConfigProvider.saveSelectedConfig(_systemPromptController.text);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Configuration "${selectedConfig!.label}" saved')));
                      }
                    },
                    icon: const Icon(CupertinoIcons.checkmark, size: 18, color: Color(0xFF2196F3)),
                    label: const Text(
                      'Save',
                      style: TextStyle(color: Color(0xFF2196F3), fontWeight: FontWeight.w500),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2196F3),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (isCustomConfigSelected) const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(51), width: 1),
                ),
                child: TextButton.icon(
                  onPressed: () => _showSaveAsConfigDialog(context),
                  icon: const Icon(CupertinoIcons.add, size: 18, color: Color(0xFF4CAF50)),
                  label: const Text(
                    'Save As',
                    style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w500),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSaveAsConfigDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.saveConfiguration),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Configuration name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ProviderManager.systemPromptConfigProvider.createCustomConfig(name, _systemPromptController.text);
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.configurationSaved)));
    }
  }

  Widget _buildMaintenanceCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.maintenance, CupertinoIcons.wrench),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
          ),
          child: ListTile(
            leading: Icon(CupertinoIcons.delete, color: Theme.of(context).colorScheme.onSurface.withAlpha(200)),
            title: CText(text: l10n.cleanupLogs),
            subtitle: CText(text: l10n.cleanupLogsDescription),
            trailing: Icon(CupertinoIcons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurface.withAlpha(50)),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: CText(text: l10n.confirmCleanup),
                  content: CText(text: l10n.confirmCleanupMessage),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: CText(text: l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: CText(text: l10n.confirm),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                try {
                  await FileLogger.cleanupOldLogs(days: 0);
                  if (mounted) {
                    ToastUtils.success(l10n.cleanupSuccess);
                  }
                } catch (e) {
                  if (mounted) {
                    ToastUtils.error('${l10n.cleanupFailed}: $e');
                  }
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMojoVoiceCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final urlController = TextEditingController();
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        urlController.text = settings.generalSetting.mojoVoiceUrl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, 'MoJo Voice', CupertinoIcons.waveform),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(50)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingSwitch(
                      title: 'Enable MoJo Voice',
                      subtitle: 'Connect to MoJo Assistant voice backend for two-brain architecture',
                      value: settings.generalSetting.mojoVoiceEnabled,
                      titleFontSize: 14,
                      subtitleFontSize: 12,
                      onChanged: (bool value) {
                        settings.updateGeneralSettingsPartially(mojoVoiceEnabled: value);
                        ToastUtils.success(l10n.saved);
                      },
                    ),
                    if (settings.generalSetting.mojoVoiceEnabled) ...[
                      const SizedBox(height: 16),
                      Divider(height: 1, color: Theme.of(context).colorScheme.outline.withAlpha(50)),
                      const SizedBox(height: 16),
                      CText(
                        text: 'Server URL',
                        fontWeight: FontWeight.w500,
                        size: 14,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          hintText: 'http://localhost:9089',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(20)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: (value) {
                          settings.updateGeneralSettingsPartially(mojoVoiceUrl: value);
                          ToastUtils.success(l10n.saved);
                        },
                        onChanged: (value) {
                          settings.updateGeneralSettingsPartially(mojoVoiceUrl: value);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
