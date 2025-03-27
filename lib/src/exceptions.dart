import 'dart:convert';

enum ErrorCode {
  // General errors (1000-1999)
  unknownError(1000),
  invalidInput(1001),
  timeout(1002),
  resourceNotFound(1003),
  resourceExhausted(1004),

  // Configuration errors (2000-2999)
  invalidConfig(2000),
  invalidApiKey(2001),
  invalidModel(2002),
  invalidProvider(2003),
  invalidParameter(2004),

  // Network errors (3000-3999)
  networkError(3000),
  connectionFailed(3001),
  requestTimeout(3002),
  rateLimitExceeded(3003),
  serviceUnavailable(3004),

  // Authentication errors (4000-4999)
  authenticationError(4000),
  invalidCredentials(4001),
  tokenExpired(4002),
  insufficientPermissions(4003),

  // Resource errors (5000-5999)
  resourceError(5000),
  quotaExceeded(5001),
  storageFull(5002),
  invalidResource(5003),

  // Validation errors (6000-6999)
  validationError(6000),
  invalidSchema(6001),
  invalidData(6002),
  missingRequired(6003),

  // State errors (7000-7999)
  stateError(7000),
  invalidState(7001),
  concurrentModification(7002),
  stateCorrupted(7003),

  // Newly added errors
  invalidResponse(1005),
  tokenLimitExceeded(1006),
  invalidConfiguration(2005),
  invalidOutput(1007),
  invalidFunction(1008),
  invalidTool(1009),
  invalidMessage(1010),
  invalidHistory(1011),
  invalidFormat(1012),
  authorizationError(4004),
  resourceConflict(5004),
  internalError(5005),
  externalError(5006),
  userError(5007),
  systemError(5008),
  inputError(1013),
  outputError(1014),
  functionError(1015),
  toolError(1016),
  messageError(1017),
  historyError(1018),
  schemaError(6004),
  formatError(1019),
  providerError(2006),
  modelError(2007),
  apiKeyError(2008),
  requestError(1020),
  responseError(1021),
  timeoutError(1022),
  serverError(3005),
  clientError(3006);

  final int code;
  const ErrorCode(this.code);
}

class MurmurationException implements Exception {
  final String message;
  final ErrorCode code;
  final int? statusCode;
  final Map<String, dynamic>? errorDetails;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final List<String> recoverySteps;

  MurmurationException(
    this.message, {
    required this.code,
    this.statusCode,
    this.errorDetails,
    this.originalError,
    this.stackTrace,
    this.recoverySteps = const [],
  });

  @override
  String toString() {
    final buffer =
        StringBuffer('MurmurationException: $message (Code: ${code.code})');
    if (statusCode != null) {
      buffer.write(' (Status: $statusCode)');
    }
    if (errorDetails != null) {
      buffer.write('\nDetails: ${jsonEncode(errorDetails)}');
    }
    if (originalError != null) {
      buffer.write('\nOriginal error: $originalError');
    }
    if (stackTrace != null) {
      buffer.write('\nStack trace:\n$stackTrace');
    }
    if (recoverySteps.isNotEmpty) {
      buffer.write('\nRecovery steps:');
      for (final step in recoverySteps) {
        buffer.write('\n- $step');
      }
    }
    return buffer.toString();
  }

  MurmurationException withRecoverySteps(List<String> steps) {
    return MurmurationException(
      message,
      code: code,
      statusCode: statusCode,
      errorDetails: errorDetails,
      originalError: originalError,
      stackTrace: stackTrace,
      recoverySteps: steps,
    );
  }
}

class ModelNotSupportedException extends MurmurationException {
  ModelNotSupportedException(String message)
      : super(message, code: ErrorCode.invalidModel);
}

class InvalidConfigurationException extends MurmurationException {
  InvalidConfigurationException(
    String message, {
    ErrorCode code = ErrorCode.invalidConfig,
    Map<String, dynamic>? errorDetails,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code,
          errorDetails: errorDetails,
          stackTrace: stackTrace,
        );
}

class RateLimitException extends MurmurationException {
  RateLimitException(String message,
      {int? statusCode, Map<String, dynamic>? errorDetails})
      : super(message,
            code: ErrorCode.rateLimitExceeded,
            statusCode: statusCode,
            errorDetails: errorDetails,
            recoverySteps: [
              'Wait for a few minutes before retrying',
              'Check your API quota and limits',
              'Consider upgrading your plan if limits are too restrictive'
            ]);
}

class AuthenticationException extends MurmurationException {
  AuthenticationException(String message,
      {int? statusCode, Map<String, dynamic>? errorDetails})
      : super(message,
            code: ErrorCode.authenticationError,
            statusCode: statusCode,
            errorDetails: errorDetails,
            recoverySteps: [
              'Verify your API key is correct',
              'Check if your API key has expired',
              'Ensure you have the necessary permissions'
            ]);
}

class TokenLimitException extends MurmurationException {
  TokenLimitException(String message,
      {int? statusCode, Map<String, dynamic>? errorDetails})
      : super(message,
            code: ErrorCode.resourceExhausted,
            statusCode: statusCode,
            errorDetails: errorDetails,
            recoverySteps: [
              'Reduce the size of your input',
              'Split your request into smaller chunks',
              'Consider using a model with higher token limits'
            ]);
}

class NetworkException extends MurmurationException {
  NetworkException(String message,
      {int? statusCode, Map<String, dynamic>? errorDetails})
      : super(message,
            code: ErrorCode.networkError,
            statusCode: statusCode,
            errorDetails: errorDetails,
            recoverySteps: [
              'Check your internet connection',
              'Verify the API endpoint is accessible',
              'Try again after a few moments'
            ]);
}

class ValidationException extends MurmurationException {
  ValidationException(
    String message, {
    ErrorCode code = ErrorCode.validationError,
    Map<String, dynamic>? errorDetails,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
    message,
    code: code,
    errorDetails: errorDetails,
    originalError: originalError,
    stackTrace: stackTrace,
  );
}

class StateException extends MurmurationException {
  StateException(String message, {Map<String, dynamic>? errorDetails})
      : super(message,
            code: ErrorCode.stateError,
            errorDetails: errorDetails,
            recoverySteps: [
              'Reinitialize the state',
              'Check for concurrent modifications',
              'Verify state consistency'
            ]);
}
