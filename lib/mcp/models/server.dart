import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class OAuth {
  final bool enabled;
  final String clientId;
  final String? clientSecret;
  final String authorizationUrl;
  final String tokenUrl;
  final String scope;
  final String redirectUri;
  final String? refreshToken;
  final String? accessToken;
  final DateTime? tokenExpiry;

  const OAuth({
    required this.enabled,
    required this.clientId,
    this.clientSecret,
    required this.authorizationUrl,
    required this.tokenUrl,
    required this.scope,
    required this.redirectUri,
    this.refreshToken,
    this.accessToken,
    this.tokenExpiry,
  });

  factory OAuth.fromJson(Map<String, dynamic> json) {
    return OAuth(
      enabled: json['enabled'] as bool? ?? false,
      clientId: json['client_id'] as String? ?? '',
      clientSecret: json['client_secret'] as String?,
      authorizationUrl: json['authorization_url'] as String? ?? '',
      tokenUrl: json['token_url'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      redirectUri: json['redirect_uri'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      accessToken: json['access_token'] as String?,
      tokenExpiry: json['token_expiry'] != null ? DateTime.parse(json['token_expiry'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'client_id': clientId,
      if (clientSecret != null) 'client_secret': clientSecret,
      'authorization_url': authorizationUrl,
      'token_url': tokenUrl,
      'scope': scope,
      'redirect_uri': redirectUri,
      if (refreshToken != null) 'refresh_token': refreshToken,
      if (accessToken != null) 'access_token': accessToken,
      if (tokenExpiry != null) 'token_expiry': tokenExpiry!.toIso8601String(),
    };
  }

  OAuth copyWith({
    bool? enabled,
    String? clientId,
    String? clientSecret,
    String? authorizationUrl,
    String? tokenUrl,
    String? scope,
    String? redirectUri,
    String? refreshToken,
    String? accessToken,
    DateTime? tokenExpiry,
  }) {
    return OAuth(
      enabled: enabled ?? this.enabled,
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      authorizationUrl: authorizationUrl ?? this.authorizationUrl,
      tokenUrl: tokenUrl ?? this.tokenUrl,
      scope: scope ?? this.scope,
      redirectUri: redirectUri ?? this.redirectUri,
      refreshToken: refreshToken ?? this.refreshToken,
      accessToken: accessToken ?? this.accessToken,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
    );
  }

  bool get isTokenValid {
    if (accessToken == null) return false;
    if (tokenExpiry == null) return true; // No expiry means token doesn't expire
    return DateTime.now().isBefore(tokenExpiry!);
  }

  bool get needsRefresh {
    if (accessToken == null) return true;
    if (tokenExpiry == null) return false;
    // Refresh if token expires in less than 5 minutes
    return DateTime.now().isAfter(tokenExpiry!.subtract(const Duration(minutes: 5)));
  }
}

class ServerConfig {
  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String author;
  final String type;
  final OAuth? oauth;

  const ServerConfig({required this.command, required this.args, this.env = const {}, this.author = '', this.type = '', this.oauth});

  // Create ServerConfig from JSON Map.
  // Supports shorthand HTTP config:
  //   "url"  → alias for "command"
  //   "auth" → { "CLIENT_ID": "...", "CLIENT_SECRET": "..." }
  //            Values resolved in order: "${VAR}", "$VAR", bare ALL_CAPS name, literal.
  //            So "CLIENT_ID": "CLIENT_ID" auto-reads the CLIENT_ID env var.
  //            CLIENT_ID / CLIENT_SECRET are mapped into the oauth block.
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    // "url" is an alias for "command" (HTTP MCP servers).
    final command = (json['url'] ?? json['command'] ?? '') as String;

    // Resolve env-var references in a string value.
    // Supported forms (tried in order):
    //   ${VAR}       — explicit brace syntax
    //   $VAR         — dollar prefix
    //   VAR_NAME     — bare ALL_CAPS_IDENTIFIER that matches an existing env var
    String resolveEnvRef(String val) {
      if (kIsWeb) return val; // Platform.environment not available on web
      // ${VAR} form
      final braceMatch = RegExp(r'^\$\{([^}]+)\}$').firstMatch(val);
      if (braceMatch != null) {
        return Platform.environment[braceMatch.group(1)!] ?? val;
      }
      // $VAR form
      final dollarMatch = RegExp(r'^\$([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(val);
      if (dollarMatch != null) {
        return Platform.environment[dollarMatch.group(1)!] ?? val;
      }
      // Bare ALL_CAPS_IDENTIFIER that exists in the environment (e.g. CLIENT_ID → $CLIENT_ID).
      // Only resolves if the env var actually exists, so literal values like "my-secret" are safe.
      if (RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(val) && Platform.environment.containsKey(val)) {
        return Platform.environment[val]!;
      }
      return val;
    }

    // Parse and resolve the env block.
    final envRaw = ((json['env'] ?? {}) as Map<String, dynamic>?)?.cast<String, String>() ?? <String, String>{};
    final env = envRaw.map((k, v) => MapEntry(k, resolveEnvRef(v)));

    // Parse the auth block and resolve its values.
    OAuth? oauth = json['oauth'] != null ? OAuth.fromJson(json['oauth'] as Map<String, dynamic>) : null;
    final authRaw = json['auth'] as Map<String, dynamic>?;
    if (authRaw != null) {
      final resolved = authRaw.map((k, v) => MapEntry(k, resolveEnvRef(v.toString())));
      final clientId = resolved['CLIENT_ID'] ?? resolved['client_id'] ?? '';
      final clientSecret = resolved['CLIENT_SECRET'] ?? resolved['client_secret'];
      // Merge into existing oauth block or create a minimal one with just the credentials.
      oauth = OAuth(
        enabled: oauth?.enabled ?? false,
        clientId: clientId.isNotEmpty ? clientId : (oauth?.clientId ?? ''),
        clientSecret: (clientSecret?.isNotEmpty == true) ? clientSecret : oauth?.clientSecret,
        authorizationUrl: oauth?.authorizationUrl ?? '',
        tokenUrl: oauth?.tokenUrl ?? '',
        scope: oauth?.scope ?? '',
        redirectUri: oauth?.redirectUri ?? '',
        refreshToken: oauth?.refreshToken,
        accessToken: oauth?.accessToken,
        tokenExpiry: oauth?.tokenExpiry,
      );
    }

    return ServerConfig(
      command: command,
      args: ((json['args'] ?? []) as List<dynamic>).cast<String>(),
      env: env,
      type: json['type'] as String? ?? '',
      oauth: oauth,
    );
  }

  // Convert ServerConfig to JSON Map
  Map<String, dynamic> toJson() {
    return {'command': command, 'args': args, 'env': env, 'author': author, 'type': type, if (oauth != null) 'oauth': oauth!.toJson()};
  }

  ServerConfig copyWith({String? command, List<String>? args, Map<String, String>? env, String? author, String? type, OAuth? oauth}) {
    return ServerConfig(
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      author: author ?? this.author,
      type: type ?? this.type,
      oauth: oauth ?? this.oauth,
    );
  }
}
