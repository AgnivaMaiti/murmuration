import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../config/murmuration_config.dart';
import '../messaging/message.dart';
import '../exceptions.dart';
import '../logging/logger.dart';
import 'dart:async';

class OpenAIClient {
  final MurmurationConfig config;
  final String baseUrl;
  final http.Client _client;
  final MurmurationLogger _logger;
  final Lock _rateLimitLock = Lock();
  final Map<String, int> _rateLimitCounts = {};
  final Map<String, DateTime> _rateLimitResetTimes = {};
  final Map<String, int> _rateLimitLimits = {
    'chat/completions': 3,
    'embeddings': 3,
  };
  final Map<String, Duration> _rateLimitWindows = {
    'chat/completions': const Duration(minutes: 1),
    'embeddings': const Duration(minutes: 1),
  };

  OpenAIClient(this.config)
      : baseUrl = config.baseUrl ?? 'https://api.openai.com/v1',
        _client = http.Client(),
        _logger = config.logger;

  Future<Map<String, dynamic>> chatCompletion({
    required List<Message> messages,
    bool? stream,
    Map<String, dynamic>? overrideParameters,
    Map<String, dynamic>? functions,
    String? functionCall,
  }) async {
    final url = Uri.parse('$baseUrl/chat/completions');

    // Merge default headers with model-specific headers
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
      'Accept': 'application/json',
      ...config.modelConfig.headers,
    };

    // Merge model parameters with override parameters
    final modelParams = {
      ...config.modelConfig.modelParameters,
      ...?overrideParameters,
    };

    final body = {
      'model': config.modelConfig.modelName,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': stream ?? config.stream,
      ...modelParams,
      if (functions != null) 'functions': functions,
      if (functionCall != null) 'function_call': functionCall,
    };

    try {
      await _checkRateLimit('chat/completions');
      final response = await _retryWithBackoff(
        () => _client.post(
          url,
          headers: headers,
          body: jsonEncode(body),
        ),
      );

      if (response.statusCode != 200) {
        final errorBody = _parseErrorResponse(response.body);
        _handleErrorResponse(response.statusCode, errorBody);
      }

      if (stream ?? config.stream) {
        return _handleStreamingResponse(response);
      }

      return jsonDecode(response.body);
    } catch (e, stackTrace) {
      if (e is MurmurationException) rethrow;
      throw MurmurationException(
        'Failed to complete chat: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<T> _retryWithBackoff<T>(Future<T> Function() operation) async {
    int attempts = 0;
    while (attempts < config.maxRetries) {
      try {
        return await operation().timeout(config.timeout);
      } catch (e) {
        attempts++;
        if (attempts >= config.maxRetries) rethrow;

        final delay = config.retryDelay * pow(2, attempts - 1);
        await Future.delayed(delay);
      }
    }
    throw MurmurationException(
      'Max retry attempts reached',
      code: ErrorCode.timeout,
    );
  }

  Map<String, dynamic> _parseErrorResponse(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return {'error': body};
    }
  }

  void _handleErrorResponse(int statusCode, Map<String, dynamic> errorBody) {
    final error = errorBody['error'] as Map<String, dynamic>?;
    final message = error?['message'] as String? ??
        errorBody['error'] as String? ??
        'Unknown error';
    final type = error?['type'] as String?;

    switch (statusCode) {
      case 401:
        throw AuthenticationException(
          message,
          statusCode: statusCode,
          errorDetails: errorBody,
        );
      case 403:
        throw AuthenticationException(
          'Insufficient permissions',
          statusCode: statusCode,
          errorDetails: errorBody,
        );
      case 429:
        throw RateLimitException(
          message,
          statusCode: statusCode,
          errorDetails: errorBody,
        );
      case 500:
        throw NetworkException(
          'OpenAI API server error',
          statusCode: statusCode,
          errorDetails: errorBody,
        );
      default:
        throw MurmurationException(
          message,
          code: ErrorCode.unknownError,
          statusCode: statusCode,
          errorDetails: errorBody,
        );
    }
  }

  Map<String, dynamic> _handleStreamingResponse(http.Response response) {
    final lines = const LineSplitter().convert(response.body);
    for (final line in lines) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6);
        if (data.trim() == '[DONE]') continue;
        try {
          return jsonDecode(data);
        } catch (e) {
          _logger.error('Failed to parse streaming response', e);
          continue;
        }
      }
    }
    throw MurmurationException(
      'No valid response in stream',
      code: ErrorCode.unknownError,
    );
  }

  Future<Map<String, dynamic>> embeddings({
    required String input,
    Map<String, dynamic>? overrideParameters,
  }) async {
    final url = Uri.parse('$baseUrl/embeddings');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
      'Accept': 'application/json',
      ...config.modelConfig.headers,
    };

    final modelParams = {
      ...config.modelConfig.modelParameters,
      ...?overrideParameters,
    };

    final body = {
      'model': config.modelConfig.modelName,
      'input': input,
      ...modelParams,
    };

    try {
      await _checkRateLimit('embeddings');
      final response = await _retryWithBackoff(
        () => _client.post(
          url,
          headers: headers,
          body: jsonEncode(body),
        ),
      );

      if (response.statusCode != 200) {
        final errorBody = _parseErrorResponse(response.body);
        _handleErrorResponse(response.statusCode, errorBody);
      }

      return jsonDecode(response.body);
    } catch (e, stackTrace) {
      if (e is MurmurationException) rethrow;
      throw MurmurationException(
        'Failed to create embeddings: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _checkRateLimit(String endpoint) async {
    await _rateLimitLock.synchronized(() async {
      final now = DateTime.now();
      final limit = _rateLimitLimits[endpoint] ?? 3;
      final window = _rateLimitWindows[endpoint] ?? const Duration(minutes: 1);
      final resetTime = _rateLimitResetTimes[endpoint];
      final count = _rateLimitCounts[endpoint] ?? 0;

      if (resetTime != null && now.isAfter(resetTime)) {
        _rateLimitCounts[endpoint] = 0;
        _rateLimitResetTimes.remove(endpoint);
      }

      if (count >= limit) {
        final waitTime = resetTime?.difference(now) ?? window;
        if (waitTime.inMilliseconds > 0) {
          await Future.delayed(waitTime);
        }
        _rateLimitCounts[endpoint] = 0;
        _rateLimitResetTimes.remove(endpoint);
      }

      _rateLimitCounts[endpoint] = (count + 1);
      _rateLimitResetTimes[endpoint] = now.add(window);
    });
  }

  Future<void> dispose() async {
    _client.close();
  }
}
