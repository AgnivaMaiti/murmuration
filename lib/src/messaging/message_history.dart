import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import '../exceptions.dart';
import 'message.dart';

class MessageHistory {
  static final Map<String, _CachedHistory> _cache = {};
  static const Duration _cacheTimeout = Duration(hours: 1);
  static final Lock _cacheLock = Lock();
  static const int _maxStorageSize = 5 * 1024 * 1024; // 5MB

  final String threadId;
  final int maxMessages;
  final int maxTokens;
  final Lock _lock = Lock();
  final List<Message> _messages = [];
  DateTime _lastAccessed = DateTime.now();
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  int get messageCount => _messages.length;
  bool get isEmpty => _messages.isEmpty;

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
      try {
        _error = null;
        _messages.add(message);
        _trim();
        await save();
        _lastAccessed = DateTime.now();
      } catch (e, stackTrace) {
        _error = 'Failed to add message: $e';
        throw ResourceException(
          'Failed to add message',
          errorDetails: {'error': e.toString()},
          stackTrace: stackTrace,
        );
      }
    });
  }

  void _trim() {
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
  }

  Future<void> load() async {
    if (_isLoading) return;

    await _lock.synchronized(() async {
      try {
        _isLoading = true;
        _error = null;

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
      } catch (e, stackTrace) {
        _error = 'Failed to load messages: $e';
        throw ResourceException(
          'Failed to load messages',
          errorDetails: {'error': e.toString()},
          stackTrace: stackTrace,
        );
      } finally {
        _isLoading = false;
      }
    });
  }

  Future<void> save() async {
    if (_isSaving) return;

    await _lock.synchronized(() async {
      try {
        _isSaving = true;
        _error = null;

        final prefs = await SharedPreferences.getInstance();
        final key = 'chat_history_$threadId';
        final encoded = jsonEncode(
          _messages.map((m) => m.toJson()).toList(),
        );

        // Check storage size
        if (encoded.length > _maxStorageSize) {
          throw ResourceException(
            'Message history exceeds maximum storage size',
            errorDetails: {
              'size': encoded.length,
              'maxSize': _maxStorageSize,
            },
          );
        }

        await prefs.setString(key, encoded);
      } catch (e, stackTrace) {
        _error = 'Failed to save messages: $e';
        throw ResourceException(
          'Failed to save messages',
          errorDetails: {'error': e.toString()},
          stackTrace: stackTrace,
        );
      } finally {
        _isSaving = false;
      }
    });
  }

  Future<void> clear() async {
    await _lock.synchronized(() async {
      try {
        _error = null;
        _messages.clear();
        final prefs = await SharedPreferences.getInstance();
        final key = 'chat_history_$threadId';
        await prefs.remove(key);
        await _cacheLock.synchronized(() {
          _cache.remove(threadId);
        });
      } catch (e, stackTrace) {
        _error = 'Failed to clear messages: $e';
        throw ResourceException(
          'Failed to clear messages',
          errorDetails: {'error': e.toString()},
          stackTrace: stackTrace,
        );
      }
    });
  }

  Future<void> dispose() async {
    await _lock.synchronized(() async {
      await _cacheLock.synchronized(() {
        _cache.remove(threadId);
      });
    });
  }

  @override
  String toString() {
    return 'MessageHistory(threadId: $threadId, messageCount: ${_messages.length})';
  }
}

class _CachedHistory {
  final MessageHistory history;
  DateTime lastAccessed;

  _CachedHistory(this.history) : lastAccessed = DateTime.now();
}
