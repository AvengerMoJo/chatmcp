import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

/// Web-based OAuth 2.0 + PKCE handler for MCP servers
///
/// Handles OAuth authorization flows in web environments using popup windows
/// and cross-origin messaging. Supports both public clients (no client_id)
/// and confidential clients with PKCE (RFC 7636) for security.
class WebOAuthHandler {
  static const String _chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  static final Random _rng = Random();

  /// Generates a random string for PKCE code verifier
  static String _generateRandomString(int length) {
    return String.fromCharCodes(Iterable.generate(length, (_) => _chars.codeUnitAt(_rng.nextInt(_chars.length))));
  }

  /// Generates PKCE code challenge from verifier
  static String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Starts OAuth flow with Authorization Code + PKCE
  static Future<Map<String, dynamic>> startOAuthFlow({
    required String authorizationUrl,
    String? clientId, // Made nullable for public clients
    required String redirectUri,
    required String scope,
    String? state,
  }) async {
    try {
      // Debug log the parameters
      Logger.root.info('OAuth Parameters:');
      Logger.root.info('  authorizationUrl: $authorizationUrl');
      Logger.root.info('  clientId: $clientId');
      Logger.root.info('  redirectUri: $redirectUri');
      Logger.root.info('  scope: $scope');

      // Generate PKCE parameters
      final codeVerifier = _generateRandomString(128);
      final codeChallenge = _generateCodeChallenge(codeVerifier);
      final stateParam = state ?? _generateRandomString(32);

      // Build authorization URL
      final authUri = Uri.parse(authorizationUrl).replace(
        queryParameters: {
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'scope': scope,
          'state': stateParam,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          // Only include client_id if provided (some servers support public clients)
          if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
        },
      );

      Logger.root.info('Starting OAuth flow with URL: $authUri');

      // Open popup window for authorization
      final popup = html.window.open(authUri.toString(), 'oauth_popup', 'width=600,height=700,scrollbars=yes,resizable=yes,status=yes,location=yes');

      // Check if popup opened successfully
      Timer? timer;
      timer = Timer(const Duration(milliseconds: 100), () {
        if (popup.closed == true) {
          timer?.cancel();
          throw Exception('Popup was closed immediately. This may be due to popup blocker settings.');
        }
      });

      try {
        // Listen for the callback
        final result = await _waitForCallback(popup, redirectUri, stateParam);
        timer.cancel();

        // Extract authorization code from callback
        final code = result['code'];
        if (code == null) {
          throw Exception('Authorization code not received');
        }

        return {'code': code, 'code_verifier': codeVerifier, 'state': result['state']};
      } catch (e) {
        timer.cancel();
        popup.close();
        rethrow;
      }
    } catch (e) {
      Logger.root.severe('OAuth flow failed: $e');
      rethrow;
    }
  }

  /// Exchanges authorization code for access token
  static Future<Map<String, dynamic>> exchangeCodeForToken({
    required String tokenUrl,
    String? clientId, // Made nullable for public clients
    String? clientSecret,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    try {
      final headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'};

      final body = <String, String>{'grant_type': 'authorization_code', 'code': code, 'redirect_uri': redirectUri, 'code_verifier': codeVerifier};

      // Only include client_id if it's provided and not the default fallback
      // Some OAuth servers (like Notion MCP) work with public clients (no client_id)
      if (clientId != null && clientId.isNotEmpty && clientId != 'mcp-client') {
        body['client_id'] = clientId;
      }

      if (clientSecret != null && clientSecret.isNotEmpty) {
        body['client_secret'] = clientSecret;
      }

      Logger.root.info('Exchanging code for token at: $tokenUrl');

      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: headers,
        body: body.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&'),
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body) as Map<String, dynamic>;

        // Calculate token expiry if expires_in is provided
        if (tokenData['expires_in'] != null) {
          final expiresIn = tokenData['expires_in'] as int;
          tokenData['expires_at'] = DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String();
        }

        Logger.root.info('Token exchange successful');
        return tokenData;
      } else {
        final errorBody = response.body;
        Logger.root.severe('Token exchange failed: ${response.statusCode} - $errorBody');
        throw Exception('Token exchange failed: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      Logger.root.severe('Token exchange error: $e');
      rethrow;
    }
  }

  /// Refreshes an expired access token
  static Future<Map<String, dynamic>> refreshToken({
    required String tokenUrl,
    String? clientId, // Made nullable for public clients
    String? clientSecret,
    required String refreshToken,
  }) async {
    try {
      final headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'};

      final body = <String, String>{'grant_type': 'refresh_token', 'refresh_token': refreshToken};

      // Only include client_id if provided
      if (clientId != null && clientId.isNotEmpty) {
        body['client_id'] = clientId;
      }

      if (clientSecret != null && clientSecret.isNotEmpty) {
        body['client_secret'] = clientSecret;
      }

      Logger.root.info('Refreshing token at: $tokenUrl');

      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: headers,
        body: body.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&'),
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body) as Map<String, dynamic>;

        // Calculate token expiry if expires_in is provided
        if (tokenData['expires_in'] != null) {
          final expiresIn = tokenData['expires_in'] as int;
          tokenData['expires_at'] = DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String();
        }

        Logger.root.info('Token refresh successful');
        return tokenData;
      } else {
        final errorBody = response.body;
        Logger.root.severe('Token refresh failed: ${response.statusCode} - $errorBody');
        throw Exception('Token refresh failed: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      Logger.root.severe('Token refresh error: $e');
      rethrow;
    }
  }

  /// Waits for OAuth callback in popup window
  static Future<Map<String, String>> _waitForCallback(html.WindowBase popup, String redirectUri, String expectedState) async {
    final completer = Completer<Map<String, String>>();

    Logger.root.info('Waiting for OAuth callback...');
    Logger.root.info('Expected redirect URI: $redirectUri');
    Logger.root.info('Expected state: $expectedState');

    // Set up message listener for cross-origin communication
    late StreamSubscription<html.MessageEvent> subscription;

    subscription = html.window.onMessage.listen((html.MessageEvent event) {
      try {
        Logger.root.info('Received OAuth message from: ${event.origin}');
        Logger.root.info('Message data: ${event.data}');

        final data = event.data;

        // Filter out browser extension messages
        if (data is Map) {
          final messageMap = Map<String, dynamic>.from(data);

          // Check for known browser extension message patterns
          if (messageMap.containsKey('source') &&
              (messageMap['source'].toString().contains('devtools') ||
                  messageMap['source'].toString().contains('extension') ||
                  messageMap['source'].toString().contains('react-devtools'))) {
            Logger.root.info('Ignoring browser extension message from: ${messageMap['source']}');
            return;
          }

          // Check for other extension-like messages
          if (messageMap.containsKey('hello') && messageMap['hello'] == true) {
            Logger.root.info('Ignoring extension hello message');
            return;
          }

          // Check for webpack/dev server messages
          if (messageMap.containsKey('type') &&
              (messageMap['type'].toString().contains('webpack') || messageMap['type'].toString().contains('devserver'))) {
            Logger.root.info('Ignoring webpack/dev server message');
            return;
          }
        }

        // Verify origin for security - must match redirect URI host
        final redirectHost = Uri.parse(redirectUri).host;
        if (!event.origin.contains(redirectHost)) {
          Logger.root.warning('Ignoring message from untrusted origin: ${event.origin} (expected: $redirectHost)');
          return;
        }

        if (data is Map) {
          final result = Map<String, String?>.from(data.map((k, v) => MapEntry(k.toString(), v?.toString())));

          Logger.root.info('Processing OAuth result: $result');

          // Only process messages that look like OAuth responses
          if (!result.containsKey('code') && !result.containsKey('error') && !result.containsKey('state')) {
            Logger.root.info('Ignoring non-OAuth message (missing OAuth parameters)');
            return;
          }

          // Verify state parameter
          if (result['state'] != expectedState) {
            Logger.root.severe('State mismatch - expected: $expectedState, got: ${result['state']}');
            completer.completeError(Exception('Invalid state parameter'));
            return;
          }

          if (result['error'] != null) {
            Logger.root.severe('OAuth error received: ${result['error']}');
            completer.completeError(Exception('OAuth error: ${result['error']} - ${result['error_description'] ?? ''}'));
            return;
          }

          if (result['code'] != null) {
            Logger.root.info('Authorization code received successfully');
            subscription.cancel();
            popup.close();
            // Filter out null values before completing
            final filteredResult = <String, String>{};
            result.forEach((key, value) {
              if (value != null) {
                filteredResult[key] = value;
              }
            });
            completer.complete(filteredResult);
          }
        }
      } catch (e) {
        Logger.root.severe('Error processing OAuth callback: $e');
        completer.completeError(e);
      }
    });

    // Check if popup is closed manually
    final timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (popup.closed == true) {
        Logger.root.warning('OAuth popup was closed by user');
        timer.cancel();
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.completeError(Exception('OAuth popup was closed by user'));
        }
      }
    });

    try {
      final result = await completer.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          subscription.cancel();
          timer.cancel();
          popup.close();
          throw Exception('OAuth flow timed out');
        },
      );

      timer.cancel();
      return result;
    } catch (e) {
      timer.cancel();
      subscription.cancel();
      popup.close();
      rethrow;
    }
  }
}
