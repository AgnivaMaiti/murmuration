import 'package:flutter/foundation.dart';

class MurmurationLogger {
  final bool enabled;
  final void Function(String) onLog;
  final void Function(String, [dynamic error, StackTrace? stackTrace]) onError;

  const MurmurationLogger({
    this.enabled = false,
    this.onLog = _defaultLogHandler,
    this.onError = _defaultErrorHandler,
  });

  static void _defaultLogHandler(String message) {
    if (kDebugMode) print('Murmuration: $message');
  }

  static void _defaultErrorHandler(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    if (kDebugMode) {
      print('Murmuration Error: $message');
      if (error != null) print('Caused by: $error');
      if (stackTrace != null) print(stackTrace);
    }
  }

  void log(String message) {
    if (enabled) onLog(message);
  }

  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (enabled) onError(message, error, stackTrace);
  }
}
