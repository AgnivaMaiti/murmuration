import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../exceptions.dart';

enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  critical(4);

  final int value;
  const LogLevel(this.value);

  bool operator >=(LogLevel other) => value >= other.value;
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.context,
  });

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write(
        '${timestamp.toIso8601String()} [${level.name.toUpperCase()}] $message');

    if (context != null) {
      buffer.write('\nContext: ${context.toString()}');
    }

    if (error != null) {
      buffer.write('\nError: $error');
    }

    if (stackTrace != null) {
      buffer.write('\nStack trace:\n$stackTrace');
    }

    return buffer.toString();
  }
}

class MurmurationLogger {
  final bool enabled;
  final LogLevel minLevel;
  final int maxFileSize;
  final int maxFiles;
  final String logDirectory;
  final void Function(LogEntry) onLog;
  final void Function(LogEntry) onError;
  final List<LogEntry> _buffer = [];
  final _lock = Lock();
  Timer? _flushTimer;
  File? _logFile;

  MurmurationLogger({
    this.enabled = false,
    this.minLevel = LogLevel.info,
    this.maxFileSize = 5 * 1024 * 1024, // 5MB
    this.maxFiles = 5,
    this.logDirectory = 'logs',
    this.onLog = _defaultLogHandler,
    this.onError = _defaultErrorHandler,
  }) {
    if (enabled) {
      _initializeLogger();
    }
  }

  static void _defaultLogHandler(LogEntry entry) {
    if (kDebugMode) print(entry.toFormattedString());
  }

  static void _defaultErrorHandler(LogEntry entry) {
    if (kDebugMode) print('ERROR: ${entry.toFormattedString()}');
  }

  Future<void> _initializeLogger() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/$logDirectory');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      _logFile = File('${logDir.path}/murmuration.log');
      _startFlushTimer();
    } catch (e) {
      print('Failed to initialize logger: $e');
    }
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => flush());
  }

  Future<void> flush() async {
    if (!enabled || _buffer.isEmpty) return;

    await _lock.synchronized(() async {
      try {
        if (_logFile != null) {
          final entries = _buffer.map((e) => e.toFormattedString()).join('\n');
          await _logFile!.writeAsString('$entries\n', mode: FileMode.append);
          _rotateLogIfNeeded();
        }
      } catch (e) {
        print('Failed to flush logs: $e');
      } finally {
        _buffer.clear();
      }
    });
  }

  Future<void> _rotateLogIfNeeded() async {
    if (_logFile == null) return;

    try {
      final size = await _logFile!.length();
      if (size >= maxFileSize) {
        final dir = _logFile!.parent;
        final name = _logFile!.path.split('/').last;
        final extension = name.contains('.') ? '.${name.split('.').last}' : '';
        final baseName = name.replaceAll(extension, '');

        // Delete oldest file if we've reached max files
        final oldFile = File('${dir.path}/$baseName${maxFiles - 1}$extension');
        if (await oldFile.exists()) {
          await oldFile.delete();
        }

        // Rotate existing files
        for (var i = maxFiles - 2; i >= 0; i--) {
          final oldFile = File('${dir.path}/$baseName$i$extension');
          final newFile = File('${dir.path}/$baseName${i + 1}$extension');
          if (await oldFile.exists()) {
            await oldFile.rename(newFile.path);
          }
        }

        // Rename current file to .0
        await _logFile!.rename('${dir.path}/$baseName.0$extension');
        _logFile = File('${dir.path}/$baseName$extension');
      }
    } catch (e) {
      print('Failed to rotate logs: $e');
    }
  }

  void log(
    String message, {
    LogLevel level = LogLevel.info,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    if (!enabled || level < minLevel) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );

    _buffer.add(entry);
    onLog(entry);

    if (level >= LogLevel.error) {
      onError(entry);
    }
  }

  void debug(String message, {Map<String, dynamic>? context}) {
    log(message, level: LogLevel.debug, context: context);
  }

  void info(String message, {Map<String, dynamic>? context}) {
    log(message, level: LogLevel.info, context: context);
  }

  void warning(String message, {Map<String, dynamic>? context}) {
    log(message, level: LogLevel.warning, context: context);
  }

  void error(String message,
      [dynamic error, StackTrace? stackTrace, Map<String, dynamic>? context]) {
    log(
      message,
      level: LogLevel.error,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  void critical(String message,
      [dynamic error, StackTrace? stackTrace, Map<String, dynamic>? context]) {
    log(
      message,
      level: LogLevel.critical,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await flush();
  }
}
