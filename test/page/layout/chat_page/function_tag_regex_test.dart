import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('function tag regex — attribute style', () {
    // Mirrors Format A in _extractToolCallsFromContent()
    final rx = RegExp(
      r"<(function|tool_call)(?:=([\w]+)|\s+[^>]*name=\x22([^\x22]*)\x22[^>]*>)(.*?)</\1",
      dotAll: true,
    );

    String? nameFrom(RegExpMatch m) => m.group(2) ?? m.group(3);

    test('standard name attribute', () {
      final m = rx.allMatches('<function name="foo">{}</function>').toList();
      expect(m.length, 1);
      expect(nameFrom(m[0]), 'foo');
    });

    test('shorthand =name', () {
      final m = rx.allMatches('<function=foo>{}</function>').toList();
      expect(m.length, 1);
      expect(nameFrom(m[0]), 'foo');
    });

    test('tool_call with name attribute', () {
      final m = rx.allMatches('<tool_call name="bar">{}</tool_call>').toList();
      expect(m.length, 1);
      expect(nameFrom(m[0]), 'bar');
    });

    test('tool_call shorthand', () {
      final m = rx.allMatches('<tool_call=bar>{}</tool_call>').toList();
      expect(m.length, 1);
      expect(nameFrom(m[0]), 'bar');
    });

    test('extracts JSON arguments', () {
      const input = '<function name="search">{"query":"hello world"}</function>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 1);
      expect(nameFrom(m[0]), 'search');
      expect(m[0].group(4), '{"query":"hello world"}');
    });

    test('matches multiple calls in one response', () {
      const input =
          'some text <function name="tool_a">{"a":1}</function> more <function name="tool_b">{"b":2}</function>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 2);
      expect(nameFrom(m[0]), 'tool_a');
      expect(nameFrom(m[1]), 'tool_b');
    });

    test('handles multiline JSON arguments with dotAll', () {
      const input = '<function name="create_task">{\n  "title": "test"\n}</function>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 1);
      expect(nameFrom(m[0]), 'create_task');
    });

    test('does not match if closing tag name differs', () {
      // With backreference \1, <function...></tool_call> should NOT match
      final m = rx.allMatches('<function name="foo">{}</tool_call>').toList();
      expect(m.length, 0);
    });

    test('does not match plain text without tags', () {
      final m = rx.allMatches('just a normal response without tool calls').toList();
      expect(m.length, 0);
    });
  });

  group('function tag regex — JSON body style (Format B)', () {
    // <tool_call>{"name":"fn","arguments":{...}}</tool_call>
    final rx = RegExp(
      r'<(?:tool_call|function_call)>\s*(\{.*?\})\s*</(?:tool_call|function_call)>',
      dotAll: true,
    );

    test('plain tool_call tag with JSON body', () {
      const input = '<tool_call>{"name":"get_context","arguments":{"type":"orientation"}}</tool_call>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 1);
      final decoded = jsonDecode(m[0].group(1)!) as Map;
      expect(decoded['name'], 'get_context');
      expect((decoded['arguments'] as Map)['type'], 'orientation');
    });

    test('function_call tag variant', () {
      const input = '<function_call>{"name":"search","arguments":{"q":"hello"}}</function_call>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 1);
      final decoded = jsonDecode(m[0].group(1)!) as Map;
      expect(decoded['name'], 'search');
    });

    test('multiline JSON body', () {
      const input = '<tool_call>\n{\n  "name": "list_tasks",\n  "arguments": {}\n}\n</tool_call>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 1);
      final decoded = jsonDecode(m[0].group(1)!.trim()) as Map;
      expect(decoded['name'], 'list_tasks');
    });

    test('does not match attribute-style tags', () {
      final m = rx.allMatches('<tool_call name="foo">{}</tool_call>').toList();
      expect(m.length, 0);
    });
  });

  group('function tag regex — pipe-bracket style (Format C)', () {
    // <|tool_call>call:name{...}<tool_call|>
    final rx = RegExp(
      r'<\|(?:tool_call|function_call)\|?>\s*call:([\w]+)\s*(\{.*?\})\s*<(?:[\w_]+)\|>',
      dotAll: true,
    );

    test('pipe-bracket format with JSON args', () {
      const input = '<|tool_call>call:get_context{"type":"orientation"}<tool_call|>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 1);
      expect(m[0].group(1), 'get_context');
      final args = jsonDecode(m[0].group(2)!) as Map;
      expect(args['type'], 'orientation');
    });

    test('pipe-bracket with optional trailing pipe in opener', () {
      const input = '<|tool_call|>call:search{"q":"hello"}<tool_call|>';
      final m = rx.allMatches(input).toList();
      expect(m.length, 1);
      expect(m[0].group(1), 'search');
    });

    test('does not match attribute-style tags', () {
      final m = rx.allMatches('<tool_call name="foo">{}</tool_call>').toList();
      expect(m.length, 0);
    });
  });
}
