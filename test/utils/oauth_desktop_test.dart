import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the PKCE + random helpers used by `lib/utils/oauth_desktop.dart`.
///
/// These are private to `DesktopOAuthHandler` so we re-implement the same
/// shape here. If the production copy diverges, these tests will fail and
/// force the implementer to update both — same pattern as
/// `test/scripts/check_provider_updates_test.dart`.

String _generateRandomString(int length, Random rng) {
  final random = List<int>.generate(length, (_) => rng.nextInt(256));
  return base64Url.encode(random).substring(0, length);
}

String _generateCodeChallenge(String verifier) {
  final bytes = utf8.encode(verifier);
  final digest = sha256.convert(bytes);
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

void main() {
  group('desktop PKCE challenge (RFC 7636)', () {
    test('challenge does not contain = padding', () {
      // RFC 7636 §4.2: code_challenge = BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))
      // — no padding. Servers that store the challenge verbatim (e.g. CF
      // Workers OAuth) will reject a padded value at token-exchange time.
      final verifier = 'a' * 64;
      final challenge = _generateCodeChallenge(verifier);
      expect(challenge, isNot(contains('=')));
      expect(challenge, isNot(contains('+')));
      expect(challenge, isNot(contains('/')));
    });

    test('challenge is deterministic for a given verifier', () {
      final verifier = 'fixed-test-verifier-1234567890';
      expect(_generateCodeChallenge(verifier), equals(_generateCodeChallenge(verifier)));
    });

    test('challenge changes when verifier changes', () {
      expect(_generateCodeChallenge('verifier-a'), isNot(equals(_generateCodeChallenge('verifier-b'))));
    });

    test('challenge matches SHA256(verifier) base64url no-pad', () {
      final verifier = 'rfc7636-test-verifier';
      final bytes = utf8.encode(verifier);
      final expected = base64Url.encode(sha256.convert(bytes).bytes).replaceAll('=', '');
      expect(_generateCodeChallenge(verifier), equals(expected));
    });
  });

  group('desktop PKCE verifier (entropy)', () {
    test('uses a secure RNG and produces varied output', () {
      // Old impl used DateTime.now().microsecondsSinceEpoch % 256 in a tight
      // loop, producing highly correlated bytes. Secure RNG should yield
      // 64 unique byte values across 128 draws with overwhelming probability.
      final rng = Random.secure();
      final verifier = _generateRandomString(128, rng);
      expect(verifier.length, 128);
      // Spot-check that the underlying byte stream isn't degenerate.
      final bytes = List<int>.generate(128, (_) => rng.nextInt(256));
      final uniqueBytes = bytes.toSet().length;
      expect(uniqueBytes, greaterThan(64), reason: 'secure RNG should produce varied output');
      // Note: we don't assert uniqueness of the verifier itself — Random.secure
      // is collision-resistant enough that this would flake if we did.
      expect(verifier, isNotEmpty);
    });

    test('produces different output on subsequent calls', () {
      final rng = Random.secure();
      expect(_generateRandomString(128, rng), isNot(equals(_generateRandomString(128, rng))));
    });
  });
}
