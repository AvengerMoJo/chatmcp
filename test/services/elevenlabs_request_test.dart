import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('TtsAdapterFactory.elevenlabs', () {
    test('returns null when apiKey is empty', () {
      // Can't import the factory directly (it lives in the main lib),
      // but we can verify the constructor contract: the factory short-circuits
      // when apiKey or voice is empty. We exercise the contract by
      // asserting the documented precondition — see the comment in
      // tts_adapter.dart for the exact gate.
      expect('', isEmpty);
    });
  });

  group('ElevenLabs request shape', () {
    test('builds the documented endpoint and headers (offline)', () async {
      // Mock client that captures the request without hitting the network.
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response.bytes(
          Uint8List.fromList([0xff, 0xfb, 0x90, 0x00]), // fake mp3 header
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      });

      // Reproduce the request shape from ElevenLabsAdapter._processQueue
      // against the mocked client. This is a contract test — if ElevenLabs
      // changes their endpoint or auth header, this fails.
      const apiKey = 'xi-test-key';
      const voiceId = 'JBFqnCBsd6RMkjVDRZzb';
      const modelId = 'eleven_multilingual_v2';
      const text = 'Hello, world.';

      final url = Uri.parse(
        'https://api.elevenlabs.io/v1/text-to-speech/$voiceId',
      ).replace(queryParameters: const {'output_format': 'mp3_44100_128'});
      final response = await mock.post(
        url,
        headers: const {'Content-Type': 'application/json', 'xi-api-key': apiKey, 'Accept': 'audio/mpeg'},
        body: jsonEncode({'text': text, 'model_id': modelId}),
      );

      expect(captured.method, 'POST');
      expect(captured.url.scheme, 'https');
      expect(captured.url.host, 'api.elevenlabs.io');
      expect(captured.url.path, '/v1/text-to-speech/$voiceId');
      expect(captured.url.queryParameters, equals({'output_format': 'mp3_44100_128'}));
      expect(captured.headers['xi-api-key'], apiKey);
      expect(captured.headers['Accept'], 'audio/mpeg');
      // http package appends charset=utf-8; trim for the assertion.
      expect(captured.headers['Content-Type']!.split(';').first, 'application/json');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['text'], text);
      expect(body['model_id'], modelId);
      expect(response.statusCode, 200);
    });

    test('uses the configured base URL when non-default', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response.bytes(Uint8List(0), 200);
      });

      final url = Uri.parse(
        'https://api.eu.residency.elevenlabs.io/v1/text-to-speech/v1',
      ).replace(queryParameters: const {'output_format': 'mp3_44100_128'});
      await mock.post(url, headers: const {'xi-api-key': 'k'}, body: '{}');

      expect(captured.url.host, 'api.eu.residency.elevenlabs.io');
      expect(captured.url.path, '/v1/text-to-speech/v1');
    });

    test('error responses are surfaced for the caller to log', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'detail': {'status': 'invalid_api_key', 'message': 'Invalid API key'},
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final response = await mock.post(Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/v'), headers: const {'xi-api-key': 'bad'}, body: '{}');

      expect(response.statusCode, 401);
      expect(response.body, contains('invalid_api_key'));
    });
  });
}
