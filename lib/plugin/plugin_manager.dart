import 'dart:io' as io;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'plugin.dart';
import 'plugin_registry.dart';

class PluginManager {
  final Logger _log = Logger.root;
  final List<Plugin> _plugins = [];
  final PluginRegistry _registry = PluginRegistry();

  String? _installBasePath;

  Future<String> get installBasePath async {
    if (_installBasePath != null) return _installBasePath!;
    final appDir = await getApplicationDocumentsDirectory();
    _installBasePath = '${appDir.path}/plugins';
    final dir = io.Directory(_installBasePath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _installBasePath!;
  }

  List<PluginEntry> get availablePlugins => _registry.entries;

  Future<List<Plugin>> discover() async {
    final base = await installBasePath;
    final dir = io.Directory(base);
    if (!await dir.exists()) return [];

    _plugins.clear();
    await for (final entry in dir.list()) {
      if (entry is io.Directory) {
        final yamlFile = io.File('${entry.path}/plugin.yaml');
        if (await yamlFile.exists()) {
          final yamlStr = await yamlFile.readAsString();
          final manifest = PluginManifest.fromYaml(yamlStr);
          final plugin = Plugin(manifest: manifest, installPath: entry.path);
          plugin.state = PluginState.installed;
          _plugins.add(plugin);
        }
      }
    }
    return _plugins;
  }

  Future<Plugin> install(String pluginName) async {
    final base = await installBasePath;

    final existing = _plugins.where((p) => p.name == pluginName).toList();
    if (existing.isNotEmpty) return existing.first;

    final entry = _registry.lookup(pluginName);
    if (entry == null) throw Exception('Plugin "$pluginName" not found in registry');

    _log.info('Installing plugin: $pluginName from ${entry.repo}');
    final installPath = '$base/$pluginName';

    await _run('git', ['clone', entry.repo, installPath]);

    final yamlFile = io.File('$installPath/plugin.yaml');
    String yamlStr;
    if (await yamlFile.exists()) {
      yamlStr = await yamlFile.readAsString();
    } else {
      yamlStr = entry.defaultYaml;
      await yamlFile.writeAsString(yamlStr);
    }

    final manifest = PluginManifest.fromYaml(yamlStr);
    final plugin = Plugin(manifest: manifest, installPath: installPath);
    plugin.state = PluginState.installed;
    _plugins.add(plugin);

    _log.info('Plugin installed: $pluginName at $installPath');
    return plugin;
  }

  Future<Plugin> enable(String pluginName) async {
    var plugin = _plugins.where((p) => p.name == pluginName).firstOrNull;
    if (plugin == null) {
      plugin = await install(pluginName);
    }

    if (plugin.isEnabled) {
      _log.info('Plugin already enabled: $pluginName');
      return plugin;
    }

    _log.info('Enabling plugin: $pluginName');
    final process = await io.Process.start(
      plugin.runtime,
      [plugin.entrypoint],
      workingDirectory: plugin.installPath,
    );

    plugin.processId = process.pid.toString();
    plugin.state = PluginState.enabled;

    _log.info('Plugin enabled: $pluginName (PID: ${plugin.processId})');
    return plugin;
  }

  Future<void> disable(String pluginName) async {
    final plugin = _plugins.where((p) => p.name == pluginName).firstOrNull;
    if (plugin == null) return;

    if (plugin.processId != null) {
      _log.info('Disabling plugin: $pluginName (PID: ${plugin.processId})');
      await _run('pkill', ['-f', plugin.entrypoint]);
      plugin.processId = null;
      plugin.state = PluginState.installed;
    }
  }

  Future<void> uninstall(String pluginName) async {
    final plugin = _plugins.where((p) => p.name == pluginName).firstOrNull;
    if (plugin == null) return;

    await disable(pluginName);

    _log.info('Uninstalling plugin: $pluginName');
    final dir = io.Directory(plugin.installPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _plugins.remove(plugin);
  }

  Future<String> _run(String command, List<String> args) async {
    final result = await io.Process.run(command, args);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      if (stderr.isNotEmpty) _log.warning('$command ${args.join(" ")}: $stderr');
    }
    return (result.stdout as String).trim();
  }
}
