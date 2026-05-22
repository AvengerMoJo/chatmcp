import 'package:flutter_test/flutter_test.dart';

void main() {
  group('function tag regex', () {
    final rx = RegExp(
      r"<(function|tool_call)(?:=([\w]+)|\s+[^>]*name=['\x22]([^'\x22]*)['\x22][^>]*>)(.*?)</\1",
      dotAll: true,
    );

    test('standard name attribute', () {
      final m = rx.allMatches('<function name="foo">{}</function>').toList();
      expect(m.length, 1);
      expect(m[0].group(2) ?? m[0].group(3), 'foo');
    });

    test('shorthand =name', () {
      final m = rx.allMatches('<function=foo>{}</function>').toList();
      expect(m.length, 1);
      expect(m[0].group(2) ?? m[0].group(3), 'foo');
    });

    test('tool_call with name', () {
      final m = rx.allMatches('<tool_call name="bar">{}</tool_call>').toList();
      expect(m.length, 1);
      expect(m[0].group(2) ?? m[0].group(3), 'bar');
    });

    test('tool_call shorthand', () {
      final m = rx.allMatches('<tool_call=bar>{}</tool_call>').toList();
      expect(m.length, 1);
      expect(m[0].group(2) ?? m[0].group(3), 'bar');
    });
  });
}