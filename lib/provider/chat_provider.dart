import 'package:chatmcp/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:chatmcp/dao/chat.dart';
import 'package:logging/logging.dart';
import 'package:chatmcp/llm/model.dart' as llm_model;
import 'package:chatmcp/repository/chat_repository_provider.dart';
import 'package:chatmcp/config/pagination_config.dart';

class ChatProvider extends ChangeNotifier {
  static final ChatProvider _instance = ChatProvider._internal();
  factory ChatProvider() => _instance;
  ChatProvider._internal();

  Chat? _activeChat;
  List<Chat> _chats = [];
  bool isSelectMode = false;
  Set<int?> selectedChats = {};

  // Pagination state
  int _currentPage = 1; // 从 1 开始更符合常规分页概念
  bool _hasMoreChats = true;
  bool _isLoadingChats = false;
  String? _currentSearchKeyword;

  Chat? get activeChat => _activeChat;
  List<Chat> get chats => _chats;
  bool get hasMoreChats => _hasMoreChats;
  bool get isLoadingChats => _isLoadingChats;

  bool _showCodePreview = false;
  bool get showCodePreview => _showCodePreview;

  void setShowCodePreview(String hash, bool show) {
    if (show) {
      _showCodePreview = true;
      _artifactEvent = _previewEvents[hash];
    } else {
      _showCodePreview = false;
      _artifactEvent = null;
    }
    notifyListeners();
  }

  CodePreviewEvent? _artifactEvent;
  CodePreviewEvent? get artifactEvent => _artifactEvent;
  final Map<String, CodePreviewEvent> _previewEvents = {};
  Map<String, CodePreviewEvent> get previewEvents => _previewEvents;

  void setPreviewEvent(CodePreviewEvent event) {
    _previewEvents[event.hash] = event;
    if (_artifactEvent != null && _artifactEvent!.hash == event.hash) {
      _artifactEvent = event;
    }
    notifyListeners();
  }

  void clearPreviewEvent(String hash) {
    _previewEvents.remove(hash);
    notifyListeners();
  }

  void clearArtifactEvent() {
    _artifactEvent = null;
    _showCodePreview = false;
    notifyListeners();
  }

  Future<void> loadChats({String? searchKeyword, bool refresh = false}) async {
    if (_isLoadingChats) return;

    if (refresh || searchKeyword != _currentSearchKeyword) {
      // Reset pagination state for new search or refresh
      _currentPage = 1; // 重置为第一页
      _hasMoreChats = true;
      _chats.clear();
      _currentSearchKeyword = searchKeyword;
    }

    if (!_hasMoreChats) return;

    _isLoadingChats = true;
    notifyListeners();

    try {
      Logger.root.info('loadChats: currentPage: $_currentPage, pageSize: ${PaginationConfig.defaultPageSize}');
      final result = await ChatRepositoryProvider.instance.getChats(
        page: _currentPage,
        pageSize: PaginationConfig.defaultPageSize,
        searchKeyword: searchKeyword,
      );

      if (_currentPage == 1) {
        // 第一页，替换现有数据
        _chats = result.chats;
      } else {
        // 后续页面，追加数据
        _chats.addAll(result.chats);
      }

      _hasMoreChats = result.hasMore;
      _currentPage++;
    } catch (e) {
      Logger.root.severe('Failed to load chats: $e');
    } finally {
      _isLoadingChats = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreChats() async {
    if (!_hasMoreChats || _isLoadingChats) return;
    await loadChats(searchKeyword: _currentSearchKeyword);
  }

  Future<void> searchChats(String keyword) async {
    await loadChats(searchKeyword: keyword.isEmpty ? null : keyword, refresh: true);
  }

  Future<void> refreshChats() async {
    await loadChats(searchKeyword: _currentSearchKeyword, refresh: true);
  }

  Future<void> setActiveChat(Chat chat) async {
    _activeChat = chat;
    notifyListeners();
  }

  Future<void> updateChatTitle(String title) async {
    if (_activeChat == null) {
      return;
    }
    final updatedChat = Chat(id: _activeChat!.id, title: title, createdAt: _activeChat!.createdAt, updatedAt: DateTime.now());
    await ChatRepositoryProvider.instance.updateChat(updatedChat);
    await loadChats(refresh: true);
    if (_activeChat?.id == updatedChat.id) {
      setActiveChat(updatedChat);
    }
  }

  Future<void> createChat(Chat chat, List<llm_model.ChatMessage> messages) async {
    final newChat = await ChatRepositoryProvider.instance.createChat(chat, messages);
    await refreshChats(); // Refresh to get updated list
    setActiveChat(newChat);
  }

  Future<void> updateChat(Chat chat) async {
    Logger.root.info('updateChat: ${chat.toJson()}');
    await ChatRepositoryProvider.instance.updateChat(chat);
    await refreshChats();
    if (_activeChat?.id == chat.id) {
      setActiveChat(chat);
    }
  }

  Future<void> deleteChat(int chatId) async {
    await ChatRepositoryProvider.instance.deleteChat(chatId);
    await refreshChats();
    if (_activeChat?.id == chatId) {
      _activeChat = null;
    }
    notifyListeners();
  }

  Future<void> clearActiveChat() async {
    _activeChat = null;
    notifyListeners();
  }

  Future<void> addChatMessage(int chatId, List<llm_model.ChatMessage> messages) async {
    await ChatRepositoryProvider.instance.addChatMessage(chatId, messages);
    notifyListeners();
  }

  void enterSelectMode() {
    isSelectMode = true;
    selectedChats.clear();
    notifyListeners();
  }

  void exitSelectMode() {
    isSelectMode = false;
    selectedChats.clear();
    notifyListeners();
  }

  void selectChat(int? chatId) {
    selectedChats.add(chatId);
    notifyListeners();
  }

  void unselectChat(int? chatId) {
    selectedChats.remove(chatId);
    notifyListeners();
  }

  void toggleSelectChat(int? chatId) {
    if (selectedChats.contains(chatId)) {
      selectedChats.remove(chatId);
    } else {
      selectedChats.add(chatId);
    }
    notifyListeners();
  }

  void toggleSelectAll() {
    if (selectedChats.length == chats.length) {
      selectedChats.clear();
    } else {
      selectedChats = chats.map((chat) => chat.id).toSet();
    }
    notifyListeners();
  }

  Future<void> deleteSelectedChats() async {
    // Delete selected chats from repository
    for (var chatId in selectedChats) {
      if (chatId != null) {
        await ChatRepositoryProvider.instance.deleteChat(chatId);
      }
    }

    // Reload chat list
    await refreshChats();

    // Update activeChat if current active chat was deleted
    if (selectedChats.contains(activeChat?.id)) {
      if (_chats.isNotEmpty) {
        await setActiveChat(_chats.first);
      } else {
        await clearActiveChat();
      }
    }

    // Exit select mode
    exitSelectMode();
  }
}
