import '../logging/logger.dart';
import '../exceptions.dart';

enum LLMProvider { google, openai, anthropic, custom }

class ModelConfig {
  final String modelName;
  final Map<String, dynamic> modelParameters;
  final Map<String, String> headers;
  final int maxTokens;
  final double temperature;
  final double topP;
  final int topK;
  final bool stream;
  final List<String> stopSequences;
  final Map<String, dynamic>? providerOptions;

  const ModelConfig({
    required this.modelName,
    this.modelParameters = const {},
    this.headers = const {},
    this.maxTokens = 4000,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.topK = 40,
    this.stream = false,
    this.stopSequences = const [],
    this.providerOptions,
  });

  ModelConfig copyWith({
    String? modelName,
    Map<String, dynamic>? modelParameters,
    Map<String, String>? headers,
    int? maxTokens,
    double? temperature,
    double? topP,
    int? topK,
    bool? stream,
    List<String>? stopSequences,
    Map<String, dynamic>? providerOptions,
  }) {
    return ModelConfig(
      modelName: modelName ?? this.modelName,
      modelParameters: modelParameters ?? this.modelParameters,
      headers: headers ?? this.headers,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      stream: stream ?? this.stream,
      stopSequences: stopSequences ?? this.stopSequences,
      providerOptions: providerOptions ?? this.providerOptions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modelName': modelName,
      'modelParameters': modelParameters,
      'headers': headers,
      'maxTokens': maxTokens,
      'temperature': temperature,
      'topP': topP,
      'topK': topK,
      'stream': stream,
      'stopSequences': stopSequences,
      if (providerOptions != null) 'providerOptions': providerOptions,
    };
  }

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      modelName: json['modelName'] as String,
      modelParameters: Map<String, dynamic>.from(json['modelParameters'] ?? {}),
      headers: Map<String, String>.from(json['headers'] ?? {}),
      maxTokens: json['maxTokens'] as int? ?? 4000,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 1.0,
      topK: json['topK'] as int? ?? 40,
      stream: json['stream'] as bool? ?? false,
      stopSequences: List<String>.from(json['stopSequences'] ?? []),
      providerOptions: json['providerOptions'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'ModelConfig(modelName: $modelName, maxTokens: $maxTokens)';
  }
}

class MurmurationConfig {
  final String apiKey;
  final ModelConfig modelConfig;
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
  final LLMProvider provider;
  final String? baseUrl;
  final Map<String, dynamic>? providerOptions;

  MurmurationConfig({
    required this.apiKey,
    ModelConfig? modelConfig,
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
    this.provider = LLMProvider.openai,
    this.baseUrl,
    this.providerOptions,
  })  : modelConfig =
            modelConfig ?? ModelConfig(modelName: 'gpt-3.5-turbo'),
        logger = logger ?? MurmurationLogger() {
    _validateConfig();
  }

  void _validateConfig() {
    if (apiKey.isEmpty) {
      throw InvalidConfigurationException(
        'API key cannot be empty',
        errorDetails: {'provider': provider.name},
      );
    }

    if (modelConfig.modelName.isEmpty) {
      throw InvalidConfigurationException(
        'Model name cannot be empty',
        errorDetails: {'provider': provider.name},
      );
    }

    if (maxTokens <= 0) {
      throw InvalidConfigurationException(
        'maxTokens must be greater than 0',
        errorDetails: {'maxTokens': maxTokens},
      );
    }

    if (maxMessages <= 0) {
      throw InvalidConfigurationException(
        'maxMessages must be greater than 0',
        errorDetails: {'maxMessages': maxMessages},
      );
    }

    if (timeout.inMilliseconds <= 0) {
      throw InvalidConfigurationException(
        'timeout must be greater than 0',
        errorDetails: {'timeout': timeout},
      );
    }

    if (maxRetries < 0) {
      throw InvalidConfigurationException(
        'maxRetries must be non-negative',
        errorDetails: {'maxRetries': maxRetries},
      );
    }

    if (retryDelay.inMilliseconds < 0) {
      throw InvalidConfigurationException(
        'retryDelay must be non-negative',
        errorDetails: {'retryDelay': retryDelay},
      );
    }

    if (cacheTimeout.inMilliseconds <= 0) {
      throw InvalidConfigurationException(
        'cacheTimeout must be greater than 0',
        errorDetails: {'cacheTimeout': cacheTimeout},
      );
    }

    _validateProviderConfig();
  }

  void _validateProviderConfig() {
    switch (provider) {
      case LLMProvider.google:
        if (!modelConfig.modelName.startsWith('gemini-')) {
          throw InvalidConfigurationException(
            'Google models must start with "gemini-"',
            errorDetails: {'model': modelConfig.modelName},
          );
        }
        break;
      case LLMProvider.openai:
        if (!modelConfig.modelName.startsWith('gpt-')) {
          throw InvalidConfigurationException(
            'OpenAI models must start with "gpt-"',
            errorDetails: {'model': modelConfig.modelName},
          );
        }
        break;
      case LLMProvider.anthropic:
        if (!modelConfig.modelName.startsWith('claude-')) {
          throw InvalidConfigurationException(
            'Anthropic models must start with "claude-"',
            errorDetails: {'model': modelConfig.modelName},
          );
        }
        break;
      case LLMProvider.custom:
        if (baseUrl == null || baseUrl!.isEmpty) {
          throw InvalidConfigurationException(
            'Custom provider requires a base URL',
            errorDetails: {'provider': provider.name},
          );
        }
        break;
    }
  }

  MurmurationConfig copyWith({
    String? apiKey,
    ModelConfig? modelConfig,
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
    LLMProvider? provider,
    String? baseUrl,
    Map<String, dynamic>? providerOptions,
  }) {
    final config = MurmurationConfig(
      apiKey: apiKey ?? this.apiKey,
      modelConfig: modelConfig ?? this.modelConfig,
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
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      providerOptions: providerOptions ?? this.providerOptions,
    );
    return config;
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'modelConfig': modelConfig.toJson(),
      'debug': debug,
      'stream': stream,
      'maxMessages': maxMessages,
      'maxTokens': maxTokens,
      'threadId': threadId,
      'timeout': timeout.inMilliseconds,
      'maxRetries': maxRetries,
      'retryDelay': retryDelay.inMilliseconds,
      'enableCache': enableCache,
      'cacheTimeout': cacheTimeout.inMilliseconds,
      'provider': provider.name,
      'baseUrl': baseUrl,
      if (providerOptions != null) 'providerOptions': providerOptions,
    };
  }

  factory MurmurationConfig.fromJson(Map<String, dynamic> json) {
    return MurmurationConfig(
      apiKey: json['apiKey'] as String,
      modelConfig:
          ModelConfig.fromJson(json['modelConfig'] as Map<String, dynamic>),
      debug: json['debug'] as bool? ?? false,
      stream: json['stream'] as bool? ?? false,
      maxMessages: json['maxMessages'] as int? ?? 50,
      maxTokens: json['maxTokens'] as int? ?? 4000,
      threadId: json['threadId'] as String?,
      timeout: Duration(milliseconds: json['timeout'] as int? ?? 30000),
      maxRetries: json['maxRetries'] as int? ?? 3,
      retryDelay: Duration(milliseconds: json['retryDelay'] as int? ?? 1000),
      enableCache: json['enableCache'] as bool? ?? true,
      cacheTimeout:
          Duration(milliseconds: json['cacheTimeout'] as int? ?? 3600000),
      provider: LLMProvider.values.firstWhere(
        (e) => e.name == json['provider'],
        orElse: () => LLMProvider.openai,
      ),
      baseUrl: json['baseUrl'] as String?,
      providerOptions: json['providerOptions'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'MurmurationConfig(provider: $provider, model: ${modelConfig.modelName})';
  }
}
