import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

// Type alias for conditional import compatibility - WebOAuthHandler refers to DesktopOAuthHandler
typedef WebOAuthHandler = DesktopOAuthHandler;

class DesktopOAuthHandler {
  static final Logger _logger = Logger('DesktopOAuth');

  // Tracks any active local callback server so we can close it before rebinding.
  static HttpServer? _activeCallbackServer;

  /// Starts OAuth flow with browser + local server callback
  /// Starts OAuth flow with browser + local server callback.
  ///
  /// [tokenUrl] — explicit token endpoint; required (auto-derive removed to avoid wrong URLs).
  /// [clientSecret] — for confidential clients (e.g. Slack). When provided, PKCE is skipped.
  /// [usePkce] — override PKCE; defaults to true when [clientSecret] is absent, false when present.
  static Future<Map<String, dynamic>> startOAuthFlow({
    required String authorizationUrl,
    required String tokenUrl,
    String? clientId,
    String? clientSecret,
    required String redirectUri,
    required String scope,
    String? state,
    bool? usePkce,
  }) async {
    // Confidential clients (have a client_secret) use standard auth code without PKCE.
    final pkce = usePkce ?? (clientSecret == null || clientSecret.isEmpty);

    final String? codeVerifier = pkce ? _generateRandomString(128) : null;
    final String? codeChallenge = pkce ? _generateCodeChallenge(codeVerifier!) : null;
    final stateParam = state ?? _generateRandomString(32);

    // Extract port from redirect URI
    final redirectUriParsed = Uri.parse(redirectUri);
    final port = redirectUriParsed.port;

    // Start local server to catch callback
    final server = await _startLocalServer(port, codeVerifier, redirectUri);

    try {
      // Build authorization URL
      final authUri = Uri.parse(authorizationUrl).replace(
        queryParameters: {
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'scope': scope,
          'state': stateParam,
          if (pkce) 'code_challenge': codeChallenge!,
          if (pkce) 'code_challenge_method': 'S256',
          if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
        },
      );

      _logger.info('Opening browser for OAuth: $authUri (pkce=$pkce)');

      // Open system browser
      if (!await launchUrl(authUri)) {
        throw Exception('Failed to open browser');
      }

      // Wait for callback
      final result = await server.result.future;

      _logger.info('OAuth callback received');

      // Exchange code for token
      final tokenResult = await exchangeCodeForToken(
        tokenUrl: tokenUrl,
        clientId: clientId,
        clientSecret: clientSecret,
        code: result['code'] as String,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
      );

      return {
        'access_token': tokenResult['access_token'],
        'refresh_token': tokenResult['refresh_token'],
        'expires_in': tokenResult['expires_in'],
        'token_type': tokenResult['token_type'] ?? 'Bearer',
      };
    } finally {
      await server.server.close(force: true).catchError((_) {});
      _activeCallbackServer = null;
    }
  }

  /// Exchange authorization code for access token.
  /// [codeVerifier] is null for non-PKCE (confidential client) flows.
  static Future<Map<String, dynamic>> exchangeCodeForToken({
    required String tokenUrl,
    String? clientId,
    String? clientSecret,
    required String code,
    String? codeVerifier,
    required String redirectUri,
  }) async {
    _logger.info('Exchanging code for token at $tokenUrl');

    final response = await http.post(
      Uri.parse(tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
        'code': code,
        if (codeVerifier != null) 'code_verifier': codeVerifier,
        'redirect_uri': redirectUri,
        if (clientSecret != null && clientSecret.isNotEmpty) 'client_secret': clientSecret,
      },
    );

    if (response.statusCode != 200) {
      _logger.severe('Token exchange failed: ${response.body}');
      throw Exception('Token exchange failed: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Refresh access token
  static Future<Map<String, dynamic>> refreshToken({
    required String tokenUrl,
    String? clientId,
    String? clientSecret,
    required String refreshToken,
  }) async {
    _logger.info('Refreshing token at $tokenUrl');

    final response = await http.post(
      Uri.parse(tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': clientId ?? '',
        'refresh_token': refreshToken,
        if (clientSecret != null) 'client_secret': clientSecret,
      },
    );

    if (response.statusCode != 200) {
      _logger.severe('Token refresh failed: ${response.body}');
      throw Exception('Token refresh failed: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Start local HTTP server to catch OAuth callback
  static Future<_LocalServerResult> _startLocalServer(int port, String? codeVerifier, String redirectUri) async {
    // Close any lingering server from a previous aborted flow before rebinding.
    if (_activeCallbackServer != null) {
      await _activeCallbackServer!.close(force: true).catchError((_) {});
      _activeCallbackServer = null;
    }

    final completer = Completer<Map<String, dynamic>>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _activeCallbackServer = server;

    _logger.info('Local OAuth server started on port $port');

    server.listen((request) async {
      _logger.info('Received request: ${request.uri}');

      // Parse callback parameters
      final uri = request.uri;
      final params = uri.queryParameters;

      if (params.containsKey('code')) {
        // Send success response to browser — use utf8.encode to avoid Latin1 crash on emoji.
        request.response.statusCode = 200;
        request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
        request.response.add(utf8.encode('''<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Authentication Successful</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
             display: flex; justify-content: center; align-items: center;
             height: 100vh; margin: 0; background: #1a1a2e; color: #fff; }
      .container { text-align: center; }
      .icon { font-size: 48px; margin-bottom: 16px; }
      h1 { font-size: 24px; margin-bottom: 8px; }
      p { color: #888; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="icon">&#x2705;</div>
      <h1>Authentication Successful!</h1>
      <p>You can close this window and return to the app.</p>
      <script>setTimeout(() => window.close(), 2000);</script>
    </div>
  </body>
</html>'''));
        await request.response.close();

        // Complete with the auth code
        completer.complete({'code': params['code'], 'state': params['state']});
      } else if (params.containsKey('error')) {
        request.response.statusCode = 400;
        request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
        request.response.add(utf8.encode('''<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Authentication Failed</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
             display: flex; justify-content: center; align-items: center;
             height: 100vh; margin: 0; background: #1a1a2e; color: #fff; }
      .container { text-align: center; }
      .icon { font-size: 48px; margin-bottom: 16px; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="icon">&#x274C;</div>
      <h1>Authentication Failed</h1>
      <p>${params['error_description'] ?? params['error']}</p>
    </div>
  </body>
</html>'''));
        await request.response.close();
        completer.completeError(Exception('OAuth error: ${params['error']}'));
      }
    });

    return _LocalServerResult(server: server, result: completer);
  }

  /// Generate random string for PKCE
  static String _generateRandomString(int length) {
    final random = List<int>.generate(length, (_) => DateTime.now().microsecondsSinceEpoch % 256);
    return base64Url.encode(random).substring(0, length);
  }

  /// Generate code challenge from verifier (S256)
  static String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes);
  }
}

class _LocalServerResult {
  final HttpServer server;
  final Completer<Map<String, dynamic>> result;

  _LocalServerResult({required this.server, required this.result});
}
