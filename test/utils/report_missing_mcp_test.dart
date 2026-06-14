import 'package:chatmcp/utils/report_missing_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildReportMissingMcpUrl', () {
    test('URL targets the daodao97/chatmcp repo by default', () {
      final url = buildReportMissingMcpUrl(
        provider: 'Z.AI',
        serverName: 'web-search',
        serverUrl: 'https://mcp.z.ai/web-search',
        description: 'Web search via Z.AI Coding Plan.',
        version: 'v0.0.90+1',
      );
      expect(url, startsWith('https://github.com/daodao97/chatmcp/issues/new?'));
    });

    test('encodes provider, server, URL, description, and version in body', () {
      final url = buildReportMissingMcpUrl(
        provider: 'Z.AI',
        serverName: 'web-search',
        serverUrl: 'https://mcp.z.ai/web-search',
        description: 'Web search via Z.AI Coding Plan.',
        version: 'v0.0.90+1',
      );
      expect(url, contains('title='));
      expect(url, contains('body='));
      expect(url, contains('Z.AI'));
      expect(url, contains('web-search'));
      expect(url, contains('v0.0.90%2B1')); // '+' encoded
    });

    test('title includes both provider and server name', () {
      final url = buildReportMissingMcpUrl(
        provider: 'Anthropic',
        serverName: 'memory',
        serverUrl: '',
        description: 'Persistent memory server.',
        version: 'v0.0.90+1',
      );
      expect(url, contains('Anthropic'));
      expect(url, contains('memory'));
    });

    test('includes the issue template hint', () {
      final url = buildReportMissingMcpUrl(
        provider: 'X',
        serverName: 'Y',
        serverUrl: '',
        description: 'Z',
        version: 'v1',
      );
      expect(url, contains('template=mcp-missing.yml'));
    });

    test('replaces empty serverUrl with a placeholder', () {
      final url = buildReportMissingMcpUrl(
        provider: 'X',
        serverName: 'Y',
        serverUrl: '',
        description: 'Z',
        version: 'v1',
      );
      // `Uri.encodeQueryComponent` encodes space as '+'.
      expect(url, contains('not+provided'));
    });

    test('labels parameter includes the expected labels', () {
      final url = buildReportMissingMcpUrl(
        provider: 'X',
        serverName: 'Y',
        serverUrl: '',
        description: 'Z',
        version: 'v1',
      );
      expect(url, contains('labels=mcp%2Cenhancement%2Cuser-request'));
    });

    test('respects a custom repo argument', () {
      final url = buildReportMissingMcpUrl(
        provider: 'X',
        serverName: 'Y',
        serverUrl: '',
        description: 'Z',
        version: 'v1',
        repo: 'my-fork/chatmcp',
      );
      expect(url, startsWith('https://github.com/my-fork/chatmcp/issues/new?'));
    });
  });
}
