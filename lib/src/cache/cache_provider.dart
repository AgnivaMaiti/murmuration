import 'dart:async';

/// Interface for cache providers
abstract class CacheProvider {
  /// Store a value in the cache
  Future<void> set<T>({
    required String key,
    required T value,
    Duration? ttl,
    List<String>? tags,
    int priority = 0,
  });

  /// Get a value from the cache
  Future<T?> get<T>(String key);

  /// Check if a key exists in the cache
  Future<bool> exists(String key);

  /// Remove a key from the cache
  Future<bool> remove(String key);

  /// Clear the entire cache
  Future<void> clear();

  /// Get all keys in the cache
  Future<Set<String>> getKeys();

  /// Remove expired entries from the cache
  Future<int> cleanup();

  /// Get cache statistics
  Future<CacheStats> getStats();
}

/// Cache statistics
class CacheStats {
  final int memoryItems;
  final int diskItems;
  final int totalSize;

  const CacheStats({
    required this.memoryItems,
    required this.diskItems,
    required this.totalSize,
  });

  @override
  String toString() => 'CacheStats(memory: $memoryItems, disk: $diskItems, size: $totalSize bytes)';
}

/// In-memory cache provider implementation
class MemoryCacheProvider implements CacheProvider {
  final Map<String, CacheEntry> _cache = {};
  final Map<String, int> _accessCount = {};
  
  @override
  Future<void> set<T>({
    required String key,
    required T value,
    Duration? ttl,
    List<String>? tags,
    int priority = 0,
  }) async {
    _cache[key] = CacheEntry<T>(
      key: key,
      value: value,
      ttl: ttl ?? const Duration(days: 7),
      tags: tags ?? [],
      priority: priority,
    );
    _accessCount[key] = (_accessCount[key] ?? 0) + 1;
  }

  @override
  Future<T?> get<T>(String key) async {
    if (!_cache.containsKey(key)) return null;
    
    final entry = _cache[key]!;
    if (entry.isExpired) {
      _cache.remove(key);
      _accessCount.remove(key);
      return null;
    }
    
    _accessCount[key] = (_accessCount[key] ?? 0) + 1;
    return entry.value as T;
  }

  @override
  Future<bool> exists(String key) async {
    if (!_cache.containsKey(key)) return false;
    if (_cache[key]!.isExpired) {
      _cache.remove(key);
      _accessCount.remove(key);
      return false;
    }
    return true;
  }\n
  @override
  Future<bool> remove(String key) async {
    final existed = _cache.containsKey(key);
    _cache.remove(key);
    _accessCount.remove(key);
    return existed;
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    _accessCount.clear();
  }

  @override
  Future<Set<String>> getKeys() async {
    // Remove expired entries
    _cache.removeWhere((key, entry) => entry.isExpired);
    return _cache.keys.toSet();
  }

  @override
  Future<int> cleanup() async {
    final before = _cache.length;
    _cache.removeWhere((key, entry) => entry.isExpired);
    return before - _cache.length;
  }

  @override
  Future<CacheStats> getStats() async {
    await cleanup();
    return CacheStats(
      memoryItems: _cache.length,
      diskItems: 0,
      totalSize: 0, // In-memory size calculation would be more complex
    );
  }
}

/// Cache entry class used by MemoryCacheProvider
class CacheEntry<T> {
  final String key;
  final T value;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> tags;
  final int priority;

  CacheEntry({
    required this.key,
    required this.value,
    required Duration ttl,
    this.tags = const [],
    this.priority = 0,
  })  : createdAt = DateTime.now(),
        expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
