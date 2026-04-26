class PluginManifest {
  final String name;
  final String version;
  final String repo;
  final String entrypoint;
  final String runtime; // python3, node, bash, etc.
  final String description;

  PluginManifest({
    required this.name,
    required this.version,
    required this.repo,
    required this.entrypoint,
    this.runtime = 'python3',
    this.description = '',
  });

  factory PluginManifest.fromYaml(String yamlStr) {
    final data = _parseSimpleYaml(yamlStr);
    return PluginManifest(
      name: data['name'] ?? '',
      version: data['version'] ?? '0.1.0',
      repo: data['repo'] ?? '',
      entrypoint: data['entrypoint'] ?? '',
      runtime: data['runtime'] ?? 'python3',
      description: data['description'] ?? '',
    );
  }

  static Map<String, String> _parseSimpleYaml(String yaml) {
    final map = <String, String>{};
    for (final line in yaml.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;
      final key = trimmed.substring(0, colonIndex).trim();
      final value = trimmed.substring(colonIndex + 1).trim();
      map[key] = value;
    }
    return map;
  }
}

enum PluginState { notInstalled, installed, enabled, error }

class Plugin {
  final PluginManifest manifest;
  final String installPath;
  PluginState state = PluginState.notInstalled;
  String? processId;
  int? port;

  Plugin({
    required this.manifest,
    required this.installPath,
  });

  String get name => manifest.name;
  String get entrypoint => manifest.entrypoint;
  String get runtime => manifest.runtime;

  bool get isInstalled => state == PluginState.installed || state == PluginState.enabled;
  bool get isEnabled => state == PluginState.enabled;
}
