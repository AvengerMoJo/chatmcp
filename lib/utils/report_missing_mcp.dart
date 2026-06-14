/// Builds the GitHub "new issue" URL used by the in-app "Report Missing MCP"
/// dialog. The URL targets the [repo] issues page with query params that
/// pre-fill the issue body. The companion template is
/// `.github/ISSUE_TEMPLATE/mcp-missing.yml`.
String buildReportMissingMcpUrl({
  required String provider,
  required String serverName,
  required String serverUrl,
  required String description,
  required String version,
  String repo = 'daodao97/chatmcp',
}) {
  final title = '[MCP] Missing: $provider / $serverName';
  final body = StringBuffer()
    ..writeln('**LLM Provider:** $provider')
    ..writeln('**Server Name:** $serverName')
    ..writeln('**Server URL / Transport:** ${serverUrl.isEmpty ? "(not provided)" : serverUrl}')
    ..writeln('**Description:** $description')
    ..writeln()
    ..writeln('**chatmcp version:** $version')
    ..writeln()
    ..writeln('_Submitted from in-app "Report Missing MCP" dialog._');
  final params = <String, String>{
    'title': title,
    'body': body.toString(),
    'labels': 'mcp,enhancement,user-request',
    'template': 'mcp-missing.yml',
  };
  final qs = params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
  return 'https://github.com/$repo/issues/new?$qs';
}
