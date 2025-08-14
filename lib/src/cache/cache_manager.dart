import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';
import 'package:crypto/crypto.dart';
import '../exceptions.dart';

/// Cache entry with metadata
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

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'tags': tags,
        'priority': priority,
      };

  factory CacheEntry.fromJson(
    Map<String, dynamic> json, 
    T Function(dynamic) fromJsonT,
  ) {
    return CacheEntry<T>(
      key: json['key'],
      value: fromJsonT(json['value']),
      ttl: DateTime.parse(json['expiresAt']).difference(DateTime.now()),
      tags: List<String>.from(json['tags'] ?? []),
      priority: json['priority'] ?? 0,
    );
  }
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
}

/// Cache exception
class CacheException extends MurmurationException {
  CacheException(String message) : super(message);
}

/// Cache manager implementation
class CacheManager {
  static const String _cacheDir = 'murmuration_cache';
  
  final Map<String, CacheEntry> _memoryCache = {};
  final Map<String, int> _accessCount = {};
  final Lock _lock = Lock();
  
  final int maxInMemoryItems;
  final int maxCacheSize;
  final Duration defaultTtl;
  final bool persistToDisk;
  
  String? _cacheDirPath;
  bool _initialized = false;
  
  CacheManager({
    this.maxInMemoryItems = 100,
    this.maxCacheSize = 100 * 1024 * 1024, // 100MB
    this.defaultTtl = const Duration(days: 7),
    this.persistToDisk = true,
  });

  /// Initialize the cache manager
  Future<void> initialize() async {
    if (_initialized) return;
    
    if (persistToDisk) {
      final appDocDir = await getApplicationDocumentsDirectory();
      _cacheDirPath = path.join(appDocDir.path, _cacheDir);
      
      try {
        final dir = Directory(_cacheDirPath!);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (e) {
        throw CacheException('Failed to initialize cache: $e');
      }
    }
    
    _initialized = true;
  }

  /// Store a value in the cache
  Future<void> set<T>({
    required String key,
    required T value,
    Duration? ttl,
    List<String>? tags,
    int priority = 0,
  }) async {
    if (!_initialized) await initialize();
    
    final entry = CacheEntry<T>(
      key: key,
      value: value,
      ttl: ttl ?? defaultTtl,
      tags: tags ?? [],
      priority: priority,
    );
    
    await _lock.synchronized(() async {
      // Store in memory
      _memoryCache[key] = entry;
      _accessCount[key] = (_accessCount[key] ?? 0) + 1;
      
      // Persist to disk if enabled
      if (persistToDisk) {
        await _persistToDisk(key, entry);
      }
      
      // Evict if needed
      await _evictIfNeeded();
    });
  }

  /// Get a value from the cache
  Future<T?> get<T>(String key) async {
    if (!_initialized) await initialize();
    
    return _lock.synchronized(() async {
      // Check memory first
      if (_memoryCache.containsKey(key)) {
        final entry = _memoryCache[key]!;
        if (_isExpired(entry)) {
          await _remove(key);
          return null;
        }
        _accessCount[key] = (_accessCount[key] ?? 0) + 1;
        return entry.value as T;
      }
      
      // Check disk if enabled
      if (persistToDisk) {
        final entry = await _loadFromDisk<T>(key);
        if (entry != null) {
          if (_isExpired(entry)) {
            await _remove(key);
            return null;
          }
          // Move to memory
          _memoryCache[key] = entry;
          _accessCount[key] = 1;
          return entry.value;
        }
      }
      
      return null;
    });
  }

  /// Remove a key from the cache
  Future<bool> remove(String key) async {
    if (!_initialized) await initialize();
    
    return _lock.synchronized(() async {
      bool existed = false;
      
      // Remove from memory
      if (_memoryCache.containsKey(key)) {
        _memoryCache.remove(key);
        _accessCount.remove(key);
        existed = true;
      }
      
      // Remove from disk if enabled
      if (persistToDisk) {
        final file = _getCacheFile(key);
        if (await file.exists()) {
          await file.delete();
          existed = true;
        }
      }
      
      return existed;
    });
  }

  /// Clear the entire cache
  Future<void> clear() async {
    if (!_initialized) await initialize();
    
    await _lock.synchronized(() async {
      _memoryCache.clear();
      _accessCount.clear();
      
      if (persistToDisk && _cacheDirPath != null) {
        try {
          final dir = Directory(_cacheDirPath!);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
            await dir.create();
          }
        } catch (e) {
          throw CacheException('Failed to clear cache: $e');
        }
      }
    });
  }

  // Helper methods
  
  bool _isExpired(CacheEntry entry) => entry.isExpired;
  
  Future<void> _persistToDisk<T>(String key, CacheEntry<T> entry) async {
    if (_cacheDirPath == null) return;
    
    final file = _getCacheFile(key);
    try {
      await file.writeAsString(jsonEncode({
        ...entry.toJson(),
        'runtimeType': T.toString(),
      }));
    } catch (e) {
      throw CacheException('Failed to persist cache entry: $e');
    }
  }
  
  Future<CacheEntry<T>?> _loadFromDisk<T>(String key) async {
    if (_cacheDirPath == null) return null;
    
    final file = _getCacheFile(key);
    if (!await file.exists()) return null;
    
    try {
      final json = jsonDecode(await file.readAsString());
      return CacheEntry<T>.fromJson(json, (value) => value as T);
    } catch (e) {
      await file.delete(); // Remove corrupted file
      return null;
    }
  }
  
  File _getCacheFile(String key) {
    final safeKey = _sanitizeKey(key);
    return File(path.join(_cacheDirPath!, '$safeKey.json'));
  }
  
  String _sanitizeKey(String key) {
    // Create a safe filename from the key
    final bytes = utf8.encode(key);
    final digest = md5.convert(bytes);
    return digest.toString();
  }
  
  Future<void> _evictIfNeeded() async {
    // Evict from memory if needed
    if (_memoryCache.length > maxInMemoryItems) {
      final keysByAccess = _accessCount.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      final toRemove = (keysByAccess.length - maxInMemoryItems).clamp(0, keysByAccess.length);
      for (int i = 0; i < toRemove; i++) {
        _memoryCache.remove(keysByAccess[i].key);
        _accessCount.remove(keysByAccess[i].key);
      }
    }
    
    // Check disk size if enabled
    if (persistToDisk && _cacheDirPath != null) {
      final dir = Directory(_cacheDirPath!);
      if (await dir.exists()) {
        int totalSize = 0;
        final files = <File>[];
        
        await for (final entity in dir.list()) {
          if (entity is File) {
            final size = await entity.length();
            totalSize += size;
            files.add(entity);
          }
        }
        
        // If over size limit, delete oldest files first
        if (totalSize > maxCacheSize) {
          files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
          
          for (final file in files) {
            if (totalSize <= maxCacheSize) break;
            
            final size = await file.length();
            await file.delete();
            totalSize -= size;
          }
        }
      }
    }
  }
}
