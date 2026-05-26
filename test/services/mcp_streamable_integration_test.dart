/// Integration test for streamable MCP client against a real backend.
///
/// Run with:
///   flutter test test/services/mcp_streamable_integration_test.dart
///
/// The backend URL and token are read from environment variables so the token
/// is never committed to the repo:
///   MCP_TEST_URL   — e.g. https://ai.avengergear.com
///   MCP_TEST_TOKEN — Bearer token (without "Bearer " prefix)
///
/// If the env vars are absent the tests are skipped.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _envUrl = String.fromEnvironment('MCP_TEST_URL');
const _envToken = String.fromEnvironment('MCP_TEST_TOKEN');

/// Thin helper: sends a single JSON-RPC POST and returns the parsed result map.
Future<Map<String, dynamic>> _rpc(
  String url,
  String token,
  String method,
  Map<String, dynamic> params, {
  String id = '1',
}) async {
  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
    },
    body: jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}),
  );

  expect(response.statusCode, 200, reason: 'HTTP $method failed: ${response.body}');

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  expect(data['error'], isNull, reason: 'JSON-RPC error: ${data['error']}');
  return data['result'] as Map<String, dynamic>;
}

void main() {
  final url = _envUrl.isNotEmpty ? _envUrl : const String.fromEnvironment('MCP_TEST_URL', defaultValue: '');
  final token = _envToken.isNotEmpty ? _envToken : const String.fromEnvironment('MCP_TEST_TOKEN', defaultValue: '');

  group('MCP Streamable Integration', () {
    setUpAll(() {
      if (url.isEmpty || token.isEmpty) {
        // Tests will be skipped individually below.
      }
    });

    test('initialize — server handshake succeeds', () async {
      if (url.isEmpty || token.isEmpty) {
        markTestSkipped('MCP_TEST_URL / MCP_TEST_TOKEN not set');
        return;
      }

      final result = await _rpc(url, token, 'initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'chatmcp-test', 'version': '1.0'},
      });

      expect(result['protocolVersion'], isNotEmpty);
      expect(result['serverInfo'], isNotNull);
      // ignore: avoid_print
      print('Server: ${result['serverInfo']}');
    });

    test('tools/list — returns at least one tool', () async {
      if (url.isEmpty || token.isEmpty) {
        markTestSkipped('MCP_TEST_URL / MCP_TEST_TOKEN not set');
        return;
      }

      // Initialize first (required by MCP protocol)
      await _rpc(url, token, 'initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'chatmcp-test', 'version': '1.0'},
      }, id: 'init');

      final result = await _rpc(url, token, 'tools/list', {}, id: 'tools');
      final tools = result['tools'] as List<dynamic>;
      expect(tools, isNotEmpty);
      // ignore: avoid_print
      print('Available tools: ${tools.map((t) => (t as Map)['name']).toList()}');
    });

    test('scheduler — list pending tasks', () async {
      if (url.isEmpty || token.isEmpty) {
        markTestSkipped('MCP_TEST_URL / MCP_TEST_TOKEN not set');
        return;
      }

      await _rpc(url, token, 'initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'chatmcp-test', 'version': '1.0'},
      }, id: 'init');

      final result = await _rpc(url, token, 'tools/call', {
        'name': 'scheduler',
        'arguments': {'action': 'list', 'status': 'pending', 'limit': 5},
      }, id: 'sched-list');

      final content = (result['content'] as List<dynamic>).first as Map<String, dynamic>;
      expect(content['type'], 'text');
      // ignore: avoid_print
      print('Scheduler list: ${content['text']}');
    });

    test('scheduler — assign task to Ahman and verify it appears', () async {
      if (url.isEmpty || token.isEmpty) {
        markTestSkipped('MCP_TEST_URL / MCP_TEST_TOKEN not set');
        return;
      }

      await _rpc(url, token, 'initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'chatmcp-test', 'version': '1.0'},
      }, id: 'init');

      // Add task
      final addResult = await _rpc(url, token, 'tools/call', {
        'name': 'scheduler',
        'arguments': {
          'action': 'add',
          'type': 'internal_assignment',
          'role_id': 'Ahman',
          'goal': '[TEST] Look up the current public IP address and report it back.',
          'priority': 'low',
          'max_iterations': 3,
        },
      }, id: 'sched-add');

      final addContent = (addResult['content'] as List<dynamic>).first as Map<String, dynamic>;
      // ignore: avoid_print
      print('Task added: ${addContent['text']}');

      // Extract task id from response text (field is "id" inside "task" object)
      final text = addContent['text'] as String;
      final taskIdMatch = RegExp(r'"message"\s*:\s*"Task ([a-f0-9]+) added').firstMatch(text);
      expect(taskIdMatch, isNotNull, reason: 'task id not found in response: $text');
      final taskId = taskIdMatch!.group(1)!;
      // ignore: avoid_print
      print('Created task_id: $taskId');

      // Get task status
      final getResult = await _rpc(url, token, 'tools/call', {
        'name': 'scheduler',
        'arguments': {'action': 'get', 'task_id': taskId},
      }, id: 'sched-get');

      final getContent = (getResult['content'] as List<dynamic>).first as Map<String, dynamic>;
      // ignore: avoid_print
      print('Task status: ${getContent['text']}');
      expect(getContent['text'], contains(taskId));
    });
  });
}
