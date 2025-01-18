import '../logging/logger.dart';

class MurmurationConfig {
  final String apiKey;
  final String model;
  final bool debug;
  final bool stream;
  final MurmurationLogger logger;
  final int maxMessages;
  final int maxTokens;
  final String? threadId;
  final Duration timeout;
  final int maxRetries;
  final Duration retryDelay;
  final bool enableCache;
  final Duration cacheTimeout;

  const MurmurationConfig({
    required this.apiKey,
    this.model = 'gemini-1.5-flash-latest',
    this.debug = false,
    this.stream = false,
    MurmurationLogger? logger,
    this.maxMessages = 50,
    this.maxTokens = 4000,
    this.threadId,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.enableCache = true,
    this.cacheTimeout = const Duration(hours: 1),
  }) : logger = logger ?? const MurmurationLogger();

  MurmurationConfig copyWith({
    String? apiKey,
    String? model,
    bool? debug,
    bool? stream,
    MurmurationLogger? logger,
    int? maxMessages,
    int? maxTokens,
    String? threadId,
    Duration? timeout,
    int? maxRetries,
    Duration? retryDelay,
    bool? enableCache,
    Duration? cacheTimeout,
  }) {
    return MurmurationConfig(
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      debug: debug ?? this.debug,
      stream: stream ?? this.stream,
      logger: logger ?? this.logger,
      maxMessages: maxMessages ?? this.maxMessages,
      maxTokens: maxTokens ?? this.maxTokens,
      threadId: threadId ?? this.threadId,
      timeout: timeout ?? this.timeout,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      enableCache: enableCache ?? this.enableCache,
      cacheTimeout: cacheTimeout ?? this.cacheTimeout,
    );
  }
}
