class PluginEntry {
  final String name;
  final String repo;
  final String version;
  final String description;
  final String defaultYaml;

  const PluginEntry({
    required this.name,
    required this.repo,
    this.version = '0.1.0',
    this.description = '',
    this.defaultYaml = '',
  });
}

class PluginRegistry {
  final List<PluginEntry> entries = [
    PluginEntry(
      name: 'voice',
      repo: 'https://github.com/AvengerMoJo/chatmcp-voice-mcp',
      version: '0.1.0',
      description: 'Voice bridge with MiniCPM-o end-to-end speech model',
      defaultYaml: 'name: voice\nversion: 0.1.0\nrepo: https://github.com/AvengerMoJo/chatmcp-voice-mcp\nentrypoint: voice_mcp_server.py\nruntime: python3\ndescription: Voice bridge with MiniCPM-o end-to-end speech model',
    ),
  ];

  PluginEntry? lookup(String name) {
    return entries.where((e) => e.name == name).firstOrNull;
  }
}
