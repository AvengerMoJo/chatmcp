import 'dart:async';
import 'package:logging/logging.dart';
import 'plugin_manager.dart';
import 'plugin.dart';
import 'plugin_registry.dart';
import '../mcp/models/server.dart';
import '../provider/mcp_server_provider.dart';
import '../provider/provider_manager.dart';

class PluginServerAdapter {
  final PluginManager _pluginManager = PluginManager();
  final Logger _log = Logger.root;
  Timer? _healthTimer;

  Future<void> init() async {
    await _pluginManager.discover();
    _log.info('Plugin adapter: installed plugins discovered');

    // Health check every 60s
    _healthTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkHealth());
  }

  /// Enable a plugin and register it as an MCP server.
  Future<void> enableAndRegister(String pluginName) async {
    final plugin = await _pluginManager.enable(pluginName);
    _registerMcpServer(plugin);
  }

  /// Disable a plugin and remove it from MCP servers.
  Future<void> disableAndUnregister(String pluginName) async {
    await _pluginManager.disable(pluginName);
    final mcpProvider = ProviderManager.mcpServerProvider;

    final servers = await mcpProvider.loadServersAll();
    final mcpServers = Map<String, dynamic>.from(servers['mcpServers'] ?? {});
    final key = 'plugin:$pluginName';

    if (mcpServers.containsKey(key)) {
      mcpServers.remove(key);
      await mcpProvider.saveServers({'mcpServers': mcpServers});
      _log.info('Plugin $pluginName removed from MCP servers');
    }
  }

  /// Get list of available plugins from registry.
  List<PluginEntry> get availablePlugins => _pluginManager.availablePlugins;

  /// Get currently installed plugins.
  Future<List<Plugin>> getInstalledPlugins() async {
    return _pluginManager.discover();
  }

  void _registerMcpServer(Plugin plugin) {
    final mcpProvider = ProviderManager.mcpServerProvider;
    final serverConfig = ServerConfig(
      command: plugin.runtime,
      args: [plugin.entrypoint],
      env: const {},
      type: 'plugin',
    );

    // Store as MCP server
    mcpProvider.loadServersAll().then((servers) {
      final mcpServers = Map<String, dynamic>.from(servers['mcpServers'] ?? {});
      mcpServers['plugin:${plugin.name}'] = serverConfig.toJson();
      mcpProvider.saveServers({'mcpServers': mcpServers});
      _log.info('Plugin ${plugin.name} registered as MCP server');
    });
  }

  void _checkHealth() {
    // Future: add health checks for running plugins
  }

  void dispose() {
    _healthTimer?.cancel();
  }
}
