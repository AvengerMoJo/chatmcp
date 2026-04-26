import 'package:flutter/material.dart';
import 'package:chatmcp/plugin/plugin_server_adapter.dart';
import 'package:chatmcp/plugin/plugin.dart';
import 'package:chatmcp/plugin/plugin_registry.dart';
import 'package:logging/logging.dart';

class PluginInstallPanel extends StatefulWidget {
  const PluginInstallPanel({super.key});

  @override
  State<PluginInstallPanel> createState() => _PluginInstallPanelState();
}

class _PluginInstallPanelState extends State<PluginInstallPanel> {
  final PluginServerAdapter _adapter = PluginServerAdapter();
  List<Plugin> _installed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _adapter.init();
    final plugins = await _adapter.getInstalledPlugins();
    setState(() {
      _installed = plugins;
      _loading = false;
    });
  }

  Future<void> _togglePlugin(String name, bool enable) async {
    try {
      if (enable) {
        await _adapter.enableAndRegister(name);
      } else {
        await _adapter.disableAndUnregister(name);
      }
      await _refresh();
    } catch (e) {
      Logger.root.warning('Plugin toggle failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView.builder(
      itemCount: _adapter.availablePlugins.length,
      itemBuilder: (context, index) {
        final entry = _adapter.availablePlugins[index];
        final installed = _installed.where((p) => p.name == entry.name).firstOrNull;
        final isEnabled = installed?.isEnabled ?? false;

        return SwitchListTile(
          title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(entry.description, style: const TextStyle(fontSize: 12)),
          value: isEnabled,
          onChanged: (v) => _togglePlugin(entry.name, v),
          secondary: _pluginIcon(entry.name),
        );
      },
    );
  }

  Widget _pluginIcon(String name) {
    switch (name) {
      case 'voice':
        return const Icon(Icons.mic);
      default:
        return const Icon(Icons.extension);
    }
  }
}
