import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../mcp/mcp.dart';
import 'package:logging/logging.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:chatmcp/utils/platform.dart';
import 'package:chatmcp/utils/storage_manager.dart';
import '../mcp/client/mcp_client_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mcp/models/server.dart';
import '../utils/oauth_web.dart' if (dart.library.io) '../utils/oauth_desktop.dart';
import '../utils/oauth_discovery.dart';

var defaultInMemoryServers = [
  {'name': 'Math', 'type': 'inmemory', 'command': 'math', 'env': {}, 'args': [], 'tools': []},
  {'name': 'Artifact Instructions', 'type': 'inmemory', 'command': 'artifact_instructions', 'env': {}, 'args': [], 'tools': []},
];

class McpServerProvider extends ChangeNotifier {
  static final McpServerProvider _instance = McpServerProvider._internal();
  factory McpServerProvider() => _instance;

  bool _isInitialized = false;

  McpServerProvider._internal() {
    _initialize();
  }

  static const _configFileName = 'mcp_server.json';

  final Map<String, McpClient> _servers = {};

  Map<String, McpClient> get clients => _servers;

  // Check if current platform supports MCP Server
  bool get isSupported {
    return !kIsMobile && !kIsWeb;
  }

  // Get configuration file path
  Future<String> get _configFilePath async {
    if (kIsWeb) return '';
    final directoryPath = await StorageManager.getAppDataDirectory();
    return '$directoryPath/$_configFileName';
  }

  // Check and create initial configuration file
  Future<void> _initConfigFile() async {
    if (kIsWeb) return;

    final file = File(await _configFilePath);

    if (!await file.exists()) {
      // Load default configuration from assets
      final defaultConfig = await rootBundle.loadString('assets/mcp_server.json');
      // Write default configuration to file
      await file.writeAsString(defaultConfig);
      Logger.root.info('Default configuration file initialized from assets');
    }
  }

  // get installed servers count
  Future<int> get installedServersCount async {
    if (kIsWeb) return 0;
    final allServerConfig = await _loadServers();
    final serverConfig = allServerConfig['mcpServers'] as Map<String, dynamic>;
    return serverConfig.length;
  }

  // Read server configuration
  Future<Map<String, dynamic>> _loadServers() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      var configString = prefs.getString('mcp_servers_json');
      if (configString == null || configString.isEmpty) {
        configString = await rootBundle.loadString('assets/mcp_server.json');
        await prefs.setString('mcp_servers_json', configString);
      }
      final Map<String, dynamic> data = json.decode(configString);
      if (data['mcpServers'] == null) {
        data['mcpServers'] = <String, dynamic>{};
      }
      for (var server in data['mcpServers'].entries) {
        server.value['installed'] = true;
      }
      return data;
    }

    File? file; // Make file nullable or assign later
    try {
      await _initConfigFile();
      final configPath = await _configFilePath;
      file = File(configPath); // Assign file here
      final String contents = await file.readAsString();

      // Check if contents are empty before attempting to decode
      if (contents.trim().isEmpty) {
        Logger.root.warning('Configuration file ($configPath) is empty. Returning default configuration.');
        return {'mcpServers': <String, dynamic>{}};
      }

      final Map<String, dynamic> data = json.decode(contents);
      if (data['mcpServers'] == null) {
        data['mcpServers'] = <String, dynamic>{};
      }
      // 遍历data['mcpServers']，直接设置installed为true，
      for (var server in data['mcpServers'].entries) {
        server.value['installed'] = true;
      }
      return data;
    } on FormatException catch (e, stackTrace) {
      // Catch specific exception
      final configPath = await _configFilePath;
      Logger.root.severe('Failed to parse configuration file ($configPath): $e, stackTrace: $stackTrace');
      // Log the problematic content if possible and file is not null
      if (file != null) {
        try {
          final String errorContents = await file.readAsString(); // Read again or use already read contents if file was assigned earlier
          Logger.root.severe('Problematic configuration file content: "$errorContents"');
        } catch (readError) {
          Logger.root.severe('Could not read configuration file content after format error: $readError');
        }
      }
      return {'mcpServers': <String, dynamic>{}}; // Return default on format error
    } catch (e, stackTrace) {
      // Catch other potential errors
      final configPath = await _configFilePath;
      Logger.root.severe('Failed to read configuration file ($configPath): $e, stackTrace: $stackTrace');
      return {'mcpServers': <String, dynamic>{}};
    }
  }

  Future<Map<String, dynamic>> loadServersAll() async {
    final allServerConfig = await _loadServers();
    return allServerConfig;
  }

  Future<Map<String, dynamic>> loadServers() async {
    final allServerConfig = await _loadServers();
    final serverConfig = allServerConfig['mcpServers'] as Map<String, dynamic>;
    final servers = Map.fromEntries(serverConfig.entries.where((entry) => entry.value['type'] != 'inmemory'));
    return {'mcpServers': servers};
  }

  Future<Map<String, dynamic>> loadInMemoryServers() async {
    final allServerConfig = await _loadServers();
    final serverConfig = allServerConfig['mcpServers'] as Map<String, dynamic>;

    // 检查默认内存服务器是否已存在，如不存在则添加
    bool needSave = false;
    for (var server in defaultInMemoryServers) {
      if (!serverConfig.containsKey(server['name'])) {
        serverConfig[server['name'] as String] = server;
        needSave = true;
      }
    }

    // 如果有新增服务器，保存配置
    if (needSave) {
      await saveServers({'mcpServers': serverConfig});
    }

    // 过滤得到所有内存类型服务器
    final servers = Map.fromEntries(serverConfig.entries.where((entry) => entry.value['type'] == 'inmemory'));

    return {'mcpServers': servers};
  }

  Future<void> addMcpServer(Map<String, dynamic> server) async {
    final allServerConfig = await _loadServers();
    final newServers = <String, dynamic>{};
    newServers.addAll(allServerConfig['mcpServers'] as Map<String, dynamic>);
    newServers[server['name']] = server;
    // 更新配置
    allServerConfig['mcpServers'] = newServers;
    await saveServers(allServerConfig);
    notifyListeners();
  }

  Future<void> removeMcpServer(String serverName) async {
    final allServerConfig = await _loadServers();
    allServerConfig['mcpServers'].remove(serverName);
    await saveServers(allServerConfig);
    notifyListeners();
  }

  // Save server configuration
  Future<void> saveServers(Map<String, dynamic> servers) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final prettyContents = const JsonEncoder.withIndent('  ').convert(servers);
      await prefs.setString('mcp_servers_json', prettyContents);
      await _reinitializeClients();
      return;
    }
    try {
      final file = File(await _configFilePath);
      final prettyContents = const JsonEncoder.withIndent('  ').convert(servers);
      await file.writeAsString(prettyContents);
      // Reinitialize clients after saving
      await _reinitializeClients();
    } catch (e, stackTrace) {
      Logger.root.severe('Failed to save configuration file: $e, stackTrace: $stackTrace');
    }
  }

  // Reinitialize clients
  Future<void> _reinitializeClients() async {
    if (kIsWeb) return;
    // _servers.clear();
    await init();
    notifyListeners();
  }

  void addClient(String key, McpClient client) {
    _servers[key] = client;
    notifyListeners();
  }

  void removeClient(String key) {
    _servers.remove(key);
    notifyListeners();
  }

  McpClient? getClient(String key) {
    return _servers[key];
  }

  final Map<String, List<Map<String, dynamic>>> _tools = {};
  Map<String, List<Map<String, dynamic>>> get tools {
    return _tools;
  }

  // 存储工具类别的启用状态
  final Map<String, bool> _toolCategoryEnabled = {};
  Map<String, bool> get toolCategoryEnabled => _toolCategoryEnabled;

  // 切换工具类别的启用状态
  void toggleToolCategory(String category, bool enabled) {
    _toolCategoryEnabled[category] = enabled;
    notifyListeners();
  }

  // 获取工具类别的启用状态，默认为启用
  bool isToolCategoryEnabled(String category) {
    return _toolCategoryEnabled[category] ?? false;
  }

  bool loadingServerTools = false;

  Future<List<Map<String, dynamic>>> getServerTools(String serverName, McpClient client) async {
    final tools = <Map<String, dynamic>>[];
    final response = await client.sendToolList();
    final toolsList = response.toJson()['result']['tools'] as List<dynamic>;
    tools.addAll(toolsList.cast<Map<String, dynamic>>());
    return tools;
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    if (kIsWeb) {
      _isInitialized = true;
      return;
    }

    try {
      await _initConfigFile();
      _isInitialized = true;
    } catch (e, stackTrace) {
      Logger.root.severe('Failed to initialize MCP servers: $e, stackTrace: $stackTrace');
    }
  }

  Future<void> init() async {
    if (!_isInitialized) {
      await _initialize();
    }

    if (kIsWeb) {
      return;
    }

    try {
      final configFilePath = await _configFilePath;
      Logger.root.info('mcp_server path: $configFilePath');

      final configFile = File(configFilePath);
      final configContent = await configFile.readAsString();
      Logger.root.info('mcp_server config: $configContent');

      final ignoreServers = <String>[];
      for (var entry in clients.entries) {
        ignoreServers.add(entry.key);
      }

      Logger.root.info('mcp_server ignoreServers: $ignoreServers');

      notifyListeners();
    } catch (e, stackTrace) {
      Logger.root.severe('Failed to initialize MCP servers: $e, stackTrace: $stackTrace');
      if (e is TypeError) {
        final configFile = File(await _configFilePath);
        final content = await configFile.readAsString();
        Logger.root.severe('Configuration file parsing error, current content: $content');
      }
    }
  }

  Future<int> get mcpServerCount async {
    final allServerConfig = await _loadServers();
    final serverConfig = allServerConfig['mcpServers'] as Map<String, dynamic>;
    return serverConfig.length;
  }

  Future<List<String>> get mcpServers async {
    final allServerConfig = await _loadServers();
    final serverConfig = allServerConfig['mcpServers'] as Map<String, dynamic>;
    return serverConfig.keys.toList();
  }

  bool mcpServerIsRunning(String serverName) {
    final client = clients[serverName];
    return client != null;
  }

  Future<void> stopMcpServer(String serverName) async {
    final client = clients[serverName];
    if (client != null) {
      await client.dispose();
      clients.remove(serverName);
      notifyListeners();
    }
  }

  Future<McpClient?> startMcpServer(String serverName) async {
    final allServerConfig = await _loadServers();
    final serverConfig = allServerConfig['mcpServers'][serverName];
    final client = await initializeMcpServer(serverConfig);
    if (client != null) {
      clients[serverName] = client;
      loadingServerTools = true;
      notifyListeners();
      final tools = await getServerTools(serverName, client);
      _tools[serverName] = tools;
      loadingServerTools = false;
      notifyListeners();
    }
    return client;
  }

  Future<Map<String, McpClient>> initializeAllMcpServers(String configPath, List<String> ignoreServers) async {
    if (kIsWeb) return {};
    final file = File(configPath);
    final contents = await file.readAsString();

    final Map<String, dynamic> config = json.decode(contents) as Map<String, dynamic>? ?? {};

    final mcpServers = config['mcpServers'] as Map<String, dynamic>;

    final Map<String, McpClient> clients = {};

    for (var entry in mcpServers.entries) {
      if (ignoreServers.contains(entry.key)) {
        continue;
      }

      final serverName = entry.key;
      final serverConfig = entry.value as Map<String, dynamic>;

      try {
        // Create async task and add to list
        final client = await initializeMcpServer(serverConfig);
        if (client != null) {
          clients[serverName] = client;
          loadingServerTools = true;
          notifyListeners();
          final tools = await getServerTools(serverName, client);
          _tools[serverName] = tools;
          loadingServerTools = false;
          notifyListeners();
        }
      } catch (e, stackTrace) {
        Logger.root.severe('Failed to initialize MCP server: $serverName, $e, stackTrace: $stackTrace');
      }
    }

    return clients;
  }

  String mcpServerMarket = "https://raw.githubusercontent.com/chatmcpclient/mcp_server_market/refs/heads/main/mcp_server_market.json";

  Future<Map<String, dynamic>> loadMarketServers() async {
    try {
      final response = await http.get(Uri.parse(mcpServerMarket));
      if (response.statusCode == 200) {
        Logger.root.info('Successfully loaded market servers: ${response.body}');
        final Map<String, dynamic> jsonData = json.decode(response.body);

        final Map<String, dynamic> servers = jsonData['mcpServers'] as Map<String, dynamic>;

        var sseServers = <String, dynamic>{};

        // For mobile platforms, only keep servers with commands starting with http
        if (kIsMobile) {
          for (var server in servers.entries) {
            if (server.value['command'] != null && server.value['command'].toString().startsWith('http')) {
              sseServers[server.key] = server.value;
            }
          }
        } else {
          sseServers = servers;
        }

        // 获取本地已安装的mcp服务器
        final localInstalledServers = await _loadServers();
        //遍历sseServers，如果本地已安装的mcp服务器中存在，则将sseServers中的该服务器设置为已安装
        for (var server in sseServers.entries) {
          if (localInstalledServers['mcpServers'][server.key] != null) {
            server.value['installed'] = true;
          } else {
            server.value['installed'] = false;
          }
        }

        return {'mcpServers': sseServers};
      }
      throw Exception('Failed to load market servers: ${response.statusCode}');
    } catch (e, stackTrace) {
      Logger.root.severe('Failed to load market servers: $e, stackTrace: $stackTrace');
      throw Exception('Failed to load market servers: $e');
    }
  }

  // OAuth-related methods
  
  /// Discovers OAuth configuration for a server URL automatically
  Future<OAuthDiscoveryResult> discoverOAuthForServer(String serverUrl) async {
    if (!kIsWeb) {
      return OAuthDiscoveryResult(requiresOAuth: false);
    }
    
    try {
      Logger.root.info('Discovering OAuth for server: $serverUrl');
      final result = await OAuthDiscoveryService.discoverOAuth(serverUrl);
      
      if (result.requiresOAuth) {
        Logger.root.info('OAuth required for server: $serverUrl');
        Logger.root.info('  Authorization URL: ${result.authorizationUrl}');
        Logger.root.info('  Token URL: ${result.tokenUrl}');
        Logger.root.info('  Client ID: ${result.clientId}');
      } else {
        Logger.root.info('No OAuth required for server: $serverUrl');
      }
      
      return result;
    } catch (e) {
      Logger.root.warning('OAuth discovery failed for $serverUrl: $e');
      return OAuthDiscoveryResult(requiresOAuth: false);
    }
  }

  /// Automatically configures and authenticates a server with discovered OAuth
  Future<bool> autoAuthenticateServer(String serverName, OAuthDiscoveryResult oauthConfig) async {
    if (!kIsWeb || !oauthConfig.requiresOAuth) {
      return false;
    }

    try {
      Logger.root.info('Auto-authenticating server: $serverName');
      
      // Use discovered client ID or null for public clients (like Notion MCP)
      String? clientId = oauthConfig.clientId;
      String scope = oauthConfig.scope ?? 'read write';
      String redirectUri = oauthConfig.redirectUri ?? '${Uri.base.origin}/oauth_callback.html';
      
      Logger.root.info('Using clientId: $clientId, scope: $scope, redirectUri: $redirectUri');
      
      // Start OAuth flow with discovered configuration
      final authResult = await WebOAuthHandler.startOAuthFlow(
        authorizationUrl: oauthConfig.authorizationUrl!,
        clientId: clientId,
        redirectUri: redirectUri,
        scope: scope,
      );

      // Exchange code for token
      final tokenResult = await WebOAuthHandler.exchangeCodeForToken(
        tokenUrl: oauthConfig.tokenUrl!,
        clientId: clientId,
        clientSecret: null, // Public clients don't require client secret
        code: authResult['code'] as String,
        codeVerifier: authResult['code_verifier'] as String,
        redirectUri: redirectUri,
      );

      // Update server configuration with OAuth info and tokens  
      final updatedConfig = OAuthDiscoveryResult(
        requiresOAuth: oauthConfig.requiresOAuth,
        authorizationUrl: oauthConfig.authorizationUrl,
        tokenUrl: oauthConfig.tokenUrl,
        clientId: clientId,
        scope: scope,
        redirectUri: redirectUri,
      );
      await _saveOAuthConfigForServer(serverName, updatedConfig, tokenResult);
      
      Logger.root.info('Auto-authentication successful for: $serverName');
      notifyListeners();
      return true;

    } catch (e) {
      Logger.root.severe('Auto-authentication failed for $serverName: $e');
      return false;
    }
  }

  /// Saves discovered OAuth configuration and tokens to server config
  Future<void> _saveOAuthConfigForServer(
    String serverName, 
    OAuthDiscoveryResult oauthConfig, 
    Map<String, dynamic> tokenResult
  ) async {
    final allServerConfig = await _loadServers();
    final serverConfig = allServerConfig['mcpServers'][serverName] as Map<String, dynamic>?;
    
    if (serverConfig != null) {
      serverConfig['oauth'] = {
        'enabled': true,
        'client_id': oauthConfig.clientId,
        'authorization_url': oauthConfig.authorizationUrl,
        'token_url': oauthConfig.tokenUrl,
        'scope': oauthConfig.scope,
        'redirect_uri': oauthConfig.redirectUri,
        'access_token': tokenResult['access_token'],
        'refresh_token': tokenResult['refresh_token'],
        'token_expiry': tokenResult['expires_at'] ?? 
          DateTime.now().add(Duration(seconds: tokenResult['expires_in'] ?? 3600)).toIso8601String(),
      };
      
      // Save updated configuration
      await saveServers(allServerConfig);
    }
  }
  
  /// Initiates OAuth flow for a server
  Future<bool> authenticateServer(String serverName) async {
    try {
      final allServerConfig = await _loadServers();
      final serverConfig = allServerConfig['mcpServers'][serverName] as Map<String, dynamic>?;
      
      Logger.root.info('Authenticating server: $serverName');
      Logger.root.info('Server config: $serverConfig');
      
      if (serverConfig == null) {
        throw Exception('Server not found: $serverName');
      }

      final oauth = serverConfig['oauth'] as Map<String, dynamic>?;
      Logger.root.info('OAuth config: $oauth');
      
      if (oauth == null || oauth['enabled'] != true) {
        throw Exception('OAuth not enabled for server: $serverName');
      }

      if (!kIsWeb) {
        throw Exception('OAuth is only supported on web platform');
      }

      // Extract OAuth parameters with debugging
      final authorizationUrl = oauth['authorization_url'] as String? ?? '';
      final clientId = oauth['client_id'] as String? ?? '';
      final redirectUri = oauth['redirect_uri'] as String? ?? '';
      final scope = oauth['scope'] as String? ?? '';
      
      Logger.root.info('OAuth params extracted:');
      Logger.root.info('  authorizationUrl: "$authorizationUrl"');
      Logger.root.info('  clientId: "$clientId"');
      Logger.root.info('  redirectUri: "$redirectUri"');
      Logger.root.info('  scope: "$scope"');

      // Start OAuth flow
      final authResult = await WebOAuthHandler.startOAuthFlow(
        authorizationUrl: authorizationUrl,
        clientId: clientId,
        redirectUri: redirectUri,
        scope: scope,
      );

      // Exchange code for token
      final tokenResult = await WebOAuthHandler.exchangeCodeForToken(
        tokenUrl: oauth['token_url'] as String,
        clientId: oauth['client_id'] as String,
        clientSecret: oauth['client_secret'] as String?,
        code: authResult['code'] as String,
        codeVerifier: authResult['code_verifier'] as String,
        redirectUri: oauth['redirect_uri'] as String,
      );

      // Update server config with tokens
      final updatedOAuth = {
        ...oauth,
        'access_token': tokenResult['access_token'],
        'refresh_token': tokenResult['refresh_token'],
        'token_expiry': tokenResult['expires_at'] ?? 
          DateTime.now().add(Duration(seconds: tokenResult['expires_in'] ?? 3600)).toIso8601String(),
      };

      serverConfig['oauth'] = updatedOAuth;
      allServerConfig['mcpServers'][serverName] = serverConfig;
      
      await saveServers(allServerConfig);
      
      Logger.root.info('OAuth authentication successful for server: $serverName');
      return true;
    } catch (e, stackTrace) {
      Logger.root.severe('OAuth authentication failed for server $serverName: $e, stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Refreshes OAuth token for a server
  Future<bool> refreshServerToken(String serverName) async {
    try {
      final allServerConfig = await _loadServers();
      final serverConfig = allServerConfig['mcpServers'][serverName] as Map<String, dynamic>?;
      
      if (serverConfig == null) {
        throw Exception('Server not found: $serverName');
      }

      final oauth = serverConfig['oauth'] as Map<String, dynamic>?;
      if (oauth == null || oauth['enabled'] != true) {
        throw Exception('OAuth not enabled for server: $serverName');
      }

      final refreshToken = oauth['refresh_token'] as String?;
      if (refreshToken == null) {
        throw Exception('No refresh token available for server: $serverName');
      }

      if (!kIsWeb) {
        throw Exception('OAuth is only supported on web platform');
      }

      // Refresh token
      final tokenResult = await WebOAuthHandler.refreshToken(
        tokenUrl: oauth['token_url'] as String,
        clientId: oauth['client_id'] as String,
        clientSecret: oauth['client_secret'] as String?,
        refreshToken: refreshToken,
      );

      // Update server config with new tokens
      final updatedOAuth = {
        ...oauth,
        'access_token': tokenResult['access_token'],
        if (tokenResult['refresh_token'] != null) 'refresh_token': tokenResult['refresh_token'],
        'token_expiry': tokenResult['expires_at'] ?? 
          DateTime.now().add(Duration(seconds: tokenResult['expires_in'] ?? 3600)).toIso8601String(),
      };

      serverConfig['oauth'] = updatedOAuth;
      allServerConfig['mcpServers'][serverName] = serverConfig;
      
      await saveServers(allServerConfig);
      
      Logger.root.info('OAuth token refresh successful for server: $serverName');
      return true;
    } catch (e, stackTrace) {
      Logger.root.severe('OAuth token refresh failed for server $serverName: $e, stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Checks if server has valid OAuth token
  Future<bool> isServerAuthenticated(String serverName) async {
    try {
      final allServerConfig = await _loadServers();
      final serverConfig = allServerConfig['mcpServers'][serverName] as Map<String, dynamic>?;
      if (serverConfig == null) return false;

      final oauth = serverConfig['oauth'] as Map<String, dynamic>?;
      if (oauth == null || oauth['enabled'] != true) return false;

      final accessToken = oauth['access_token'] as String?;
      if (accessToken == null) return false;

      final tokenExpiry = oauth['token_expiry'] as String?;
      if (tokenExpiry != null) {
        final expiry = DateTime.parse(tokenExpiry);
        if (DateTime.now().isAfter(expiry)) return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Gets current OAuth status for a server
  Future<Map<String, dynamic>> getServerOAuthStatus(String serverName) async {
    try {
      final allServerConfig = await _loadServers();
      final serverConfig = allServerConfig['mcpServers'][serverName] as Map<String, dynamic>?;
      
      if (serverConfig == null) {
        return {'enabled': false, 'authenticated': false, 'error': 'Server not found'};
      }

      final oauth = serverConfig['oauth'] as Map<String, dynamic>?;
      if (oauth == null || oauth['enabled'] != true) {
        return {'enabled': false, 'authenticated': false};
      }

      final accessToken = oauth['access_token'] as String?;
      if (accessToken == null) {
        return {'enabled': true, 'authenticated': false, 'error': 'No access token'};
      }

      final tokenExpiry = oauth['token_expiry'] as String?;
      bool isExpired = false;
      bool needsRefresh = false;
      
      if (tokenExpiry != null) {
        final expiry = DateTime.parse(tokenExpiry);
        isExpired = DateTime.now().isAfter(expiry);
        needsRefresh = DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 5)));
      }

      return {
        'enabled': true,
        'authenticated': !isExpired,
        'needs_refresh': needsRefresh,
        'token_expiry': tokenExpiry,
      };
    } catch (e) {
      return {'enabled': false, 'authenticated': false, 'error': e.toString()};
    }
  }
}
