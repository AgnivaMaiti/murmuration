import 'dart:async';
import '../exceptions.dart';
import '../logging/logger.dart';
import '../schema/output_schema.dart';
import '../schema/validation_result.dart';
import 'tool.dart';
import 'dart:convert';

class ToolChain {
  final String name;
  final String description;
  final List<Tool> tools;
  final OutputSchema? outputSchema;
  final Duration timeout;
  final bool requiresAuth;
  final List<String> tags;
  final Map<String, dynamic> metadata;
  final MurmurationLogger _logger;

  const ToolChain({
    required this.name,
    required this.description,
    required this.tools,
    required MurmurationLogger logger,
    this.outputSchema,
    this.timeout = const Duration(seconds: 60),
    this.requiresAuth = false,
    this.tags = const [],
    this.metadata = const {},
  }) : _logger = logger;

  Future<String> execute(Map<String, dynamic> args) async {
    if (tools.isEmpty) {
      throw InvalidConfigurationException(
          'Tool chain must have at least one tool');
    }

    String currentOutput = '';
    final startTime = DateTime.now();

    try {
      for (var i = 0; i < tools.length; i++) {
        final tool = tools[i];
        final toolStartTime = DateTime.now();

        try {
          _logger.info(
            'Executing tool ${i + 1}/${tools.length}: ${tool.name}',
            {
              'chain': name,
              'tool': tool.name,
              'toolIndex': i + 1,
              'totalTools': tools.length,
              'input': args,
            },
          );

          final toolArgs = _prepareToolArgs(tool, args, currentOutput);
          final validationResult = tool.validateParameters(toolArgs);

          if (!validationResult.isSuccess) {
            throw ValidationException(
              'Tool parameter validation failed',
              errorDetails: {
                'tool': tool.name,
                'error': validationResult.error,
                'data': validationResult.data,
              },
            );
          }

          currentOutput = await tool.executeWithTimeout(toolArgs);

          _logger.info(
            'Tool execution completed',
            {
              'chain': name,
              'tool': tool.name,
              'toolIndex': i + 1,
              'totalTools': tools.length,
              'duration': DateTime.now().difference(toolStartTime),
            },
          );
        } catch (e, stackTrace) {
          _logger.error(
            'Tool execution failed',
            e,
            stackTrace,
            {
              'chain': name,
              'tool': tool.name,
              'toolIndex': i + 1,
              'totalTools': tools.length,
              'duration': DateTime.now().difference(toolStartTime),
            },
          );
          rethrow;
        }
      }

      if (outputSchema != null) {
        final validationResult = await _validateOutput(currentOutput);
        if (!validationResult.isSuccess) {
          throw ValidationException(
            'Chain output validation failed',
            errorDetails: {
              'chain': name,
              'output': currentOutput,
              'error': validationResult.error,
            },
          );
        }
      }

      _logger.info(
        'Chain execution completed',
        {
          'chain': name,
          'duration': DateTime.now().difference(startTime),
          'toolCount': tools.length,
        },
      );

      return currentOutput;
    } catch (e, stackTrace) {
      if (e is MurmurationException) rethrow;
      throw MurmurationException(
        'Chain execution failed: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
        errorDetails: {
          'chain': name,
          'duration': DateTime.now().difference(startTime),
          'toolCount': tools.length,
        },
      );
    }
  }

  Map<String, dynamic> _prepareToolArgs(
    Tool tool,
    Map<String, dynamic> chainArgs,
    String previousOutput,
  ) {
    final toolArgs = Map<String, dynamic>.from(chainArgs);

    // Add previous output if tool accepts it
    if (tool.parameters.containsKey('input')) {
      toolArgs['input'] = previousOutput;
    }

    // Add chain metadata if tool accepts it
    if (tool.parameters.containsKey('metadata')) {
      toolArgs['metadata'] = metadata;
    }

    return toolArgs;
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
      'tools': tools.map((t) => t.toJson()).toList(),
      if (outputSchema != null) 'outputSchema': outputSchema!.toJson(),
      'timeout': timeout.inSeconds,
      'requiresAuth': requiresAuth,
      'tags': tags,
      'metadata': metadata,
    };
  }

  @override
  String toString() {
    return 'ToolChain(name: $name, tools: ${tools.length})';
  }
}
