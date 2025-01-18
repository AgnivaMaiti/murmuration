import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import '../../murmuration.dart';

class MessageHistory {
  static final Map<String, _CachedHistory> _cache = {};
  static const Duration _cacheTimeout = Duration(hours: 1);
  static final Lock _cacheLock = Lock();

  final String threadId;
  final int maxMessages;
  final int maxTokens;
  final Lock _lock = Lock();
  final List<Message> _messages = [];
  // ignore: unused_field
  DateTime _lastAccessed = DateTime.now();

  List<Message> get messages => List.unmodifiable(_messages);

  factory MessageHistory({
    required String threadId,
    int maxMessages = 50,
    int maxTokens = 4000,
  }) {
    return _cache
        .putIfAbsent(
          threadId,
          () => _CachedHistory(
            MessageHistory._internal(
              threadId: threadId,
              maxMessages: maxMessages,
              maxTokens: maxTokens,
            ),
          ),
        )
        .history;
  }

  MessageHistory._internal({
    required this.threadId,
    required this.maxMessages,
    required this.maxTokens,
  });

  static Future<void> cleanup() async {
    await _cacheLock.synchronized(() {
      final now = DateTime.now();
      _cache.removeWhere(
          (_, cached) => now.difference(cached.lastAccessed) > _cacheTimeout);
    });
  }

  Future<void> addMessage(Message message) async {
    await _lock.synchronized(() async {
      _messages.add(message);
      _trim();
      await save();
      _lastAccessed = DateTime.now();
    });
  }

  void _trim() {
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
  }

  Future<void> load() async {
    await _lock.synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_history_$threadId';
      final savedMessages = prefs.getString(key);
      if (savedMessages != null) {
        final List<dynamic> decoded = jsonDecode(savedMessages);
        _messages.clear();
        _messages.addAll(
          decoded.map((m) => Message.fromJson(m)).toList(),
        );
      }
    });
  }

  Future<void> save() async {
    await _lock.synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_history_$threadId';
      final encoded = jsonEncode(
        _messages.map((m) => m.toJson()).toList(),
      );
      await prefs.setString(key, encoded);
    });
  }

  Future<void> clear() async {
    await _lock.synchronized(() async {
      _messages.clear();
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_history_$threadId';
      await prefs.remove(key);
      await _cacheLock.synchronized(() {
        _cache.remove(threadId);
      });
    });
  }
}

class _CachedHistory {
  final MessageHistory history;
  DateTime lastAccessed;

  _CachedHistory(this.history) : lastAccessed = DateTime.now();
}