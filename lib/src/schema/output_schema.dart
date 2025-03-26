import 'schema_field.dart';
import 'validation_result.dart';
import '../exceptions.dart';

class OutputSchema {
  final Map<String, SchemaField> fields;
  final bool strict;
  final Set<String> _validatingFields;

  const OutputSchema({
    required this.fields,
    this.strict = true,
  }) : _validatingFields = {};

  ValidationResult validateAndConvert(Map<String, dynamic> data) {
    final validatedData = <String, dynamic>{};
    final errors = <String>[];
    _validatingFields.clear();

    // First pass: Check required fields and unknown fields
    for (final field in fields.entries) {
      if (field.value.required && !data.containsKey(field.key)) {
        errors.add('Missing required field: ${field.key}');
      }
    }

    if (strict) {
      for (final key in data.keys) {
        if (!fields.containsKey(key)) {
          errors.add('Unknown field: $key');
        }
      }
    }

    if (errors.isNotEmpty) {
      return ValidationResult.failure(errors.join(', '));
    }

    // Second pass: Validate and convert fields
    for (final entry in data.entries) {
      final field = fields[entry.key];
      if (field != null) {
        final result = _validateField(field, entry.value);
        if (result.isSuccess) {
          validatedData[entry.key] = result.value;
        } else {
          errors.add('${entry.key}: ${result.error}');
        }
      }
    }

    if (errors.isEmpty) {
      return ValidationResult.success(validatedData);
    } else {
      return ValidationResult.failure(errors.join(', '));
    }
  }

  ValidationResult _validateField(SchemaField field, dynamic value) {
    try {
      if (!field.isValidType(value) && value != null) {
        return ValidationResult.failure(
            'Invalid type: expected ${field.runtimeType}');
      }

      final converted = field.convert(value);
      if (!field.validate(converted)) {
        return ValidationResult.failure('Validation failed');
      }

      return ValidationResult.success(converted);
    } catch (e, stackTrace) {
      return ValidationResult.failure('Conversion error: $e', stackTrace);
    }
  }

  ValidationResult validateNestedField(String fieldName, dynamic value) {
    final field = fields[fieldName];
    if (field == null) {
      return ValidationResult.failure('Unknown field: $fieldName');
    }

    if (_validatingFields.contains(fieldName)) {
      return ValidationResult.failure(
          'Circular reference detected for field: $fieldName');
    }

    _validatingFields.add(fieldName);
    final result = _validateField(field, value);
    _validatingFields.remove(fieldName);

    return result;
  }

  bool get isValid => fields.isNotEmpty;

  @override
  String toString() {
    return 'OutputSchema(fields: ${fields.keys.join(', ')})';
  }
}
