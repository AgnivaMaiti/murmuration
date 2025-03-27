import 'dart:async';
import '../exceptions.dart';
import '../schema/output_schema.dart';
import '../schema/validation_result.dart';
import 'dart:convert';

class Tool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final OutputSchema? outputSchema;
  final Duration timeout;
  final bool requiresAuth;
  final List<String> tags;
  final Map<String, dynamic> metadata;

  const Tool({
    required this.name,
    required this.description,
    required this.parameters,
    this.outputSchema,
    this.timeout = const Duration(seconds: 30),
    this.requiresAuth = false,
    this.tags = const [],
    this.metadata = const {},
  });

  Future<String> execute(Map<String, dynamic> args) async {
    throw UnimplementedError('Tool must implement execute method');
  }

  Future<String> executeWithTimeout(Map<String, dynamic> args) async {
    try {
      final result = await execute(args).timeout(timeout);
      if (outputSchema != null) {
        final validationResult = await _validateOutput(result);
        if (!validationResult.isSuccess) {
          throw ValidationException(
            'Tool output validation failed',
            errorDetails: {
              'tool': name,
              'output': result,
              'error': validationResult.error,
            },
          );
        }
      }
      return result;
    } on TimeoutException {
      throw MurmurationException(
        'Tool execution timed out',
        code: ErrorCode.timeout,
        errorDetails: {
          'tool': name,
          'timeout': timeout.inSeconds,
          'parameters': args,
        },
      );
    } catch (e, stackTrace) {
      if (e is MurmurationException) rethrow;
      throw MurmurationException(
        'Tool execution failed: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
        errorDetails: {
          'tool': name,
          'parameters': args,
        },
      );
    }
  }

  ValidationResult validateParameters(Map<String, dynamic> args) {
    final missingParams = <String>[];
    final invalidParams = <String, String>{};

    for (final entry in parameters.entries) {
      final paramName = entry.key;
      final paramSchema = entry.value;
      final required = paramSchema['required'] ?? false;

      if (required && !args.containsKey(paramName)) {
        missingParams.add(paramName);
        continue;
      }

      if (args.containsKey(paramName)) {
        final value = args[paramName];
        final type = paramSchema['type'];
        final pattern = paramSchema['pattern'];
        final minimum = paramSchema['minimum'];
        final maximum = paramSchema['maximum'];
        final minLength = paramSchema['minLength'];
        final maxLength = paramSchema['maxLength'];

        if (!_validateParameterType(value, type)) {
          invalidParams[paramName] = 'Invalid type. Expected $type';
          continue;
        }

        if (pattern != null &&
            value is String &&
            !RegExp(pattern).hasMatch(value)) {
          invalidParams[paramName] = 'Value does not match pattern: $pattern';
          continue;
        }

        if (minimum != null && value is num && value < minimum) {
          invalidParams[paramName] = 'Value must be >= $minimum';
          continue;
        }

        if (maximum != null && value is num && value > maximum) {
          invalidParams[paramName] = 'Value must be <= $maximum';
          continue;
        }

        if (minLength != null && value is String && value.length < minLength) {
          invalidParams[paramName] = 'Length must be >= $minLength';
          continue;
        }

        if (maxLength != null && value is String && value.length > maxLength) {
          invalidParams[paramName] = 'Length must be <= $maxLength';
          continue;
        }
      }
    }

    if (missingParams.isNotEmpty || invalidParams.isNotEmpty) {
      return ValidationResult.failure(
        'Parameter validation failed',
        data: {
          if (missingParams.isNotEmpty) 'missingParams': missingParams,
          if (invalidParams.isNotEmpty) 'invalidParams': invalidParams,
        },
      );
    }

    return ValidationResult.success(args);
  }

  bool _validateParameterType(dynamic value, String type) {
    switch (type) {
      case 'string':
        return value is String;
      case 'number':
        return value is num;
      case 'integer':
        return value is int;
      case 'boolean':
        return value is bool;
      case 'array':
        return value is List;
      case 'object':
        return value is Map;
      default:
        return false;
    }
  }

  Future<ValidationResult> _validateOutput(String output) async {
    try {
      if (outputSchema == null) {
        return ValidationResult.success(output);
      }

      Map<String, dynamic> outputMap;
      try {
        outputMap = jsonDecode(output) as Map<String, dynamic>;
      } catch (e) {
        return ValidationResult.failure(
          'Output validation error: Invalid JSON format',
          data: {'output': output},
        );
      }

      final result = outputSchema!.validateAndConvert(outputMap);
      if (!result.isSuccess) {
        return ValidationResult.failure(
          'Output validation failed',
          data: {'error': result.error},
        );
      }

      return ValidationResult.success(result.value);
    } catch (e) {
      return ValidationResult.failure(
        'Output validation error: $e',
        data: {'output': output},
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'parameters': parameters,
      if (outputSchema != null) 'outputSchema': outputSchema!.toJson(),
      'timeout': timeout.inSeconds,
      'requiresAuth': requiresAuth,
      'tags': tags,
      'metadata': metadata,
    };
  }

  @override
  String toString() {
    return 'Tool(name: $name, description: $description)';
  }
}

class ToolRegistry {
  static final Map<String, Tool> _tools = {};
  static final Map<String, Set<Tool>> _taggedTools = {};

  static void register(Tool tool) {
    _tools[tool.name] = tool;
    for (final tag in tool.tags) {
      _taggedTools.putIfAbsent(tag, () => {}).add(tool);
    }
  }

  static void unregister(String name) {
    final tool = _tools.remove(name);
    if (tool != null) {
      for (final tag in tool.tags) {
        _taggedTools[tag]?.remove(tool);
        if (_taggedTools[tag]?.isEmpty ?? false) {
          _taggedTools.remove(tag);
        }
      }
    }
  }

  static Tool? getTool(String name) => _tools[name];

  static Set<Tool> getToolsByTag(String tag) => _taggedTools[tag] ?? {};

  static List<Tool> getAllTools() => _tools.values.toList();

  static void clear() {
    _tools.clear();
    _taggedTools.clear();
  }
}
