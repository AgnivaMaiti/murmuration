import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/murmuration_config.dart';
import '../messaging/message.dart';
import '../exceptions.dart';
import '../logging/logger.dart';

class GoogleClient {
  final MurmurationConfig config;
  final String baseUrl;
  final http.Client _client;
  final MurmurationLogger _logger;
  final Lock _rateLimitLock = Lock();
  final Map<String, int> _rateLimitCounts = {};
  final Map<String, DateTime> _rateLimitResetTimes = {};
  final Map<String, int> _rateLimitLimits = {
    'generateContent': 3,
    'embedContent': 3,
  };
  final Map<String, Duration> _rateLimitWindows = {
    'generateContent': const Duration(minutes: 1),
    'embedContent': const Duration(minutes: 1),
  };
  late final GenerativeModel _model;

  GoogleClient(this.config)
      : baseUrl = config.baseUrl ?? 'https://generativelanguage.googleapis.com/v1',
        _client = http.Client(),
        _logger = config.logger {
    _initializeModel();
  }

  void _initializeModel() {
    final modelName = config.modelConfig.modelName;
    if (!modelName.startsWith('gemini-')) {
      throw InvalidConfigurationException(
        'Invalid model name for Google provider. Must start with "gemini-"',
        details: {'model': modelName},
      );
    }

    _model = GenerativeModel(
      model: modelName,
      apiKey: config.apiKey,
      generationConfig: GenerationConfig(
        maxOutputTokens: config.modelConfig.maxTokens,
        temperature: config.modelConfig.temperature,
        topP: config.modelConfig.topP,
        topK: config.modelConfig.topK,
        stopSequences: config.modelConfig.stopSequences,
      ),
    );
  }

  Future<Map<String, dynamic>> chatCompletion({
    required List<Message> messages,
    bool? stream,
    Map<String, dynamic>? overrideParameters,
    Map<String, dynamic>? functions,
    String? functionCall,
  }) async {
    try {
      await _checkRateLimit('generateContent');

      final content = messages.map((m) {
        final role = m.role == MessageRole.assistant ? 'model' : m.role.name;
        return Content.text(m.content, role: role);
      }).toList();

      final response = await _retryWithBackoff(
        () => _model.generateContent(content),
      );

      if (response.text == null) {
        throw MurmurationException(
          'No response text received from model',
          code: ErrorCode.unknownError,
        );
      }

      return {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': response.text,
            },
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 0, // Google API doesn't provide token counts
          'completion_tokens': 0,
          'total_tokens': 0,
        },
      };
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

  Future<Map<String, dynamic>> embeddings({
    required String input,
    Map<String, dynamic>? overrideParameters,
  }) async {
    try {
      await _checkRateLimit('embedContent');

      final response = await _retryWithBackoff(
        () => _model.embedContent(input),
      );

      if (response.embedding == null) {
        throw MurmurationException(
          'No embedding received from model',
          code: ErrorCode.unknownError,
        );
      }

      return {
        'data': [
          {
            'embedding': response.embedding,
            'index': 0,
            'object': 'embedding',
          }
        ],
        'model': config.modelConfig.modelName,
        'usage': {
          'prompt_tokens': 0, // Google API doesn't provide token counts
          'total_tokens': 0,
        },
      };
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