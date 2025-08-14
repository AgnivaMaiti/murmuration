import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:synchronized/synchronized.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';

import '../config/murmuration_config.dart';
import '../messaging/message.dart';
import '../exceptions.dart';
import '../logging/logger.dart';

class AnthropicClient {
  final MurmurationConfig config;
  final String baseUrl;
  final http.Client _client;
  final MurmurationLogger _logger;
  final Lock _rateLimitLock = Lock();
  final Map<String, int> _rateLimitCounts = {};
  final Map<String, DateTime> _rateLimitResetTimes = {};
  final Map<String, int> _rateLimitLimits = {
    'messages': 30,  // Increased default limit
    'completions': 30,
  };
  final Map<String, Duration> _rateLimitWindows = {
    'messages': const Duration(seconds: 10),  // Shorter window for better granularity
    'completions': const Duration(seconds: 10),
  };
  final Map<String, int> _rateLimitRemaining = {};
  final Map<String, int> _rateLimitLimit = {};
  final Map<String, int> _rateLimitReset = {};
  final _jitter = Random();
  late final Anthropic _anthropic;

  AnthropicClient(this.config)
      : baseUrl = config.baseUrl ?? 'https://api.anthropic.com/v1',
        _client = http.Client(),
        _logger = config.logger {
    _initializeClient();
  }

  void _initializeClient() {
    _anthropic = Anthropic(
      apiKey: config.apiKey,
      baseUrl: baseUrl,
      client: _client,
    );
  }

  /// Sends a chat completion request to the Anthropic API.
  /// [messages] The list of messages in the conversation
  /// [stream] Whether to stream the response
  /// [overrideParameters] Additional parameters to override the default ones
  /// [functions] (Not supported in streaming mode) Functions available for the model to call
  /// [functionCall] (Not supported in streaming mode) Controls if a specific function is called
  Future<Map<String, dynamic>> chatCompletion({
    required List<Message> messages,
    bool? stream,
    Map<String, dynamic>? overrideParameters,
    Map<String, dynamic>? functions,
    String? functionCall,
  }) async {
    if (stream == true) {
      throw UnsupportedError('Use streamChatCompletion for streaming responses');
    }
    
    try {
      await _checkRateLimit('messages');

      final model = config.modelConfig.modelName;
      final systemMessages = messages.where((m) => m.role == MessageRole.system);
      final conversation = messages.where((m) => m.role != MessageRole.system);

      final response = await _anthropic.messages.create(
        model: model,
        messages: conversation.map((m) => Message(
          role: _convertRole(m.role),
          content: [TextContent(text: m.content)],
        )).toList(),
        system: systemMessages.isNotEmpty ? systemMessages.first.content : null,
        maxTokens: config.modelConfig.maxTokens,
        temperature: config.modelConfig.temperature,
        topP: config.modelConfig.topP,
        topK: config.modelConfig.topK,
        ...?overrideParameters,
      );

      return {
        'id': response.id,
        'object': 'chat.completion',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': model,
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': response.content.isNotEmpty ? response.content.first.text : '',
            },
            'finish_reason': response.stopReason,
          },
        ],
        'usage': {
          'prompt_tokens': response.usage.inputTokens,
          'completion_tokens': response.usage.outputTokens,
          'total_tokens': response.usage.inputTokens + response.usage.outputTokens,
        },
      };
    } catch (e, stackTrace) {
      _logger.error('Anthropic API error', error: e, stackTrace: stackTrace);
      if (e is AnthropicException) {
        throw MurmurationException(
          'Anthropic API error: ${e.message}',
          code: ErrorCode.apiError,
          originalError: e,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  }

  /// Converts a MessageRole to an Anthropic MessageRole enum
  /// Handles special cases for function and tool roles
  MessageRole _convertRole(MessageRole role) {
    switch (role) {
      case MessageRole.user:
        return MessageRole.user;
      case MessageRole.assistant:
        return MessageRole.assistant;
      case MessageRole.system:
        return MessageRole.user; // Anthropic doesn't have a system role, map to user
      case MessageRole.function:
        _logger.warning('Function role not directly supported by Anthropic, mapping to user');
        return MessageRole.user;
      case MessageRole.tool:
        _logger.warning('Tool role not directly supported by Anthropic, mapping to user');
        return MessageRole.user;
    }
  }

  /// Checks and enforces rate limits with adaptive backoff and jitter
  /// Implements exponential backoff and jitter to prevent thundering herd problem
  Future<void> _checkRateLimit(String endpoint) async {
    await _rateLimitLock.synchronized(() async {
      final now = DateTime.now();
      final resetTime = _rateLimitResetTimes[endpoint];
      final remaining = _rateLimitRemaining[endpoint];
      
      // Reset counters if the window has passed
      if (resetTime != null && now.isAfter(resetTime)) {
        _rateLimitCounts[endpoint] = 0;
        _rateLimitResetTimes.remove(endpoint);
        _rateLimitRemaining.remove(endpoint);
        _rateLimitLimit.remove(endpoint);
        _rateLimitReset.remove(endpoint);
      }

      // If we have rate limit info from headers, use that
      if (remaining != null && remaining <= 0) {
        final resetTime = _rateLimitReset[endpoint] ?? 0;
        final resetDateTime = DateTime.fromMillisecondsSinceEpoch(resetTime * 1000);
        final waitTime = resetDateTime.difference(now).inSeconds;
        
        if (waitTime > 0) {
          // Add jitter to prevent thundering herd
          final jitter = _jitter.nextInt(3000); // Up to 3 seconds jitter
          await Future.delayed(Duration(milliseconds: waitTime * 1000 + jitter));
        }
      }
      
      // Fallback to basic rate limiting if no header info is available
      final count = _rateLimitCounts[endpoint] ?? 0;
      final limit = _rateLimitLimits[endpoint] ?? 30;
      
      if (count >= limit) {
        // Exponential backoff with jitter
        final backoff = min(pow(2, (count ~/ limit)).toInt(), 60); // Max 60 seconds
        final jitter = _jitter.nextInt(2000); // Up to 2 seconds jitter
        await Future.delayed(Duration(seconds: backoff) + Duration(milliseconds: jitter));
      }
      
      _rateLimitCounts[endpoint] = count + 1;
      if (count == 0) {
        _rateLimitResetTimes[endpoint] = now.add(_rateLimitWindows[endpoint]!);
      }
    });
  }
  
  /// Updates rate limit information from HTTP response headers
  void _updateRateLimitFromHeaders(Map<String, String> headers, String endpoint) {
    try {
      final remaining = headers['x-ratelimit-remaining-requests'];
      final limit = headers['x-ratelimit-limit-requests'];
      final reset = headers['x-ratelimit-reset-requests'];
      
      if (remaining != null) _rateLimitRemaining[endpoint] = int.tryParse(remaining) ?? 0;
      if (limit != null) _rateLimitLimit[endpoint] = int.tryParse(limit) ?? 30;
      if (reset != null) _rateLimitReset[endpoint] = int.tryParse(reset) ?? 0;
      
      _logger.fine('Rate limit updated - Remaining: $remaining, Limit: $limit, Reset: $reset');
    } catch (e) {
      _logger.warning('Failed to update rate limit from headers', error: e);
    }
  }

  /// Streams chat completion responses from the Anthropic API
  /// Returns a stream of chat completion chunks
  Stream<Map<String, dynamic>> streamChatCompletion({
    required List<Message> messages,
    Map<String, dynamic>? overrideParameters,
  }) {
    final controller = StreamController<Map<String, dynamic>>();
    
    // Run the streaming in a separate zone to handle errors properly
    runZonedGuarded(() async {
      try {
        await _checkRateLimit('messages');
        
        final model = config.modelConfig.modelName;
        final systemMessages = messages.where((m) => m.role == MessageRole.system);
        final conversation = messages.where((m) => m.role != MessageRole.system);
        
        final stream = _anthropic.createMessageStream(
          request: CreateMessageRequest(
            model: Model.modelId(model),
            messages: conversation.map((m) => Message(
              role: _convertRole(m.role),
              content: [TextContent(text: m.content)],
            )).toList(),
            system: systemMessages.isNotEmpty ? systemMessages.first.content : null,
            maxTokens: config.modelConfig.maxTokens,
            temperature: config.modelConfig.temperature,
            topP: config.modelConfig.topP,
            topK: config.modelConfig.topK,
          ),
        );
        
        var buffer = StringBuffer();
        
        await for (final event in stream) {
          event.map(
            messageStart: (_) {
              // Handle message start
              final chunk = {
                'id': 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
                'object': 'chat.completion.chunk',
                'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'model': model,
                'choices': [
                  {
                    'index': 0,
                    'delta': {'role': 'assistant', 'content': ''},
                    'finish_reason': null,
                  },
                ],
              };
              controller.add(chunk);
            },
            contentBlockDelta: (event) {
              // Handle content delta
              buffer.write(event.delta.text);
              
              final chunk = {
                'id': 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
                'object': 'chat.completion.chunk',
                'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'model': model,
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': event.delta.text},
                    'finish_reason': null,
                  },
                ],
              };
              controller.add(chunk);
            },
            messageStop: (event) {
              // Send final chunk with finish reason
              final chunk = {
                'id': 'cmpl-${DateTime.now().millisecondsSinceEpoch}',
                'object': 'chat.completion.chunk',
                'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'model': model,
                'choices': [
                  {
                    'index': 0,
                    'delta': {},
                    'finish_reason': 'stop',
                  },
                ],
                'usage': {
                  'prompt_tokens': event.usage.inputTokens,
                  'completion_tokens': event.usage.outputTokens,
                  'total_tokens': event.usage.inputTokens + event.usage.outputTokens,
                },
              };
              controller.add(chunk);
              controller.close();
            },
            contentBlockStart: (_) {},
            contentBlockStop: (_) {},
            messageDelta: (_) {},
            ping: (_) {},
            error: (event) {
              _logger.error('Error in streaming: ${event.error}');
              controller.addError(MurmurationException(
                'Anthropic streaming error: ${event.error}',
                code: ErrorCode.apiError,
              ));
              controller.close();
            },
          );
        }
      } catch (e, stackTrace) {
        _logger.error('Streaming error', error: e, stackTrace: stackTrace);
        
        if (!controller.isClosed) {
          if (e is AnthropicException) {
            controller.addError(MurmurationException(
              'Anthropic streaming error: ${e.message}',
              code: ErrorCode.apiError,
              originalError: e,
              stackTrace: stackTrace,
            ));
          } else {
            controller.addError(e, stackTrace);
          }
          await controller.close();
        }
      }
    }, (error, stackTrace) {
      _logger.error('Unhandled error in streaming', error: error, stackTrace: stackTrace);
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        controller.close();
      }
    });
    
    return controller.stream;
  }

  /// Disposes of resources used by the client
  /// Cleans up HTTP client and rate limiting state
  void dispose() {
    try {
      _client.close();
      _rateLimitCounts.clear();
      _rateLimitResetTimes.clear();
      _rateLimitRemaining.clear();
      _rateLimitLimit.clear();
      _rateLimitReset.clear();
      _logger.fine('Anthropic client disposed');
    } catch (e, stackTrace) {
      _logger.warning('Error disposing Anthropic client', error: e, stackTrace: stackTrace);
    }
  }
}
