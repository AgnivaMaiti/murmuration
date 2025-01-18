import 'schema_field.dart';
import 'validation_result.dart';

class OutputSchema {
  final Map<String, SchemaField> fields;
  final bool strict;

  const OutputSchema({
    required this.fields,
    this.strict = true,
  });

  ValidationResult validateAndConvert(Map<String, dynamic> data) {
    final validatedData = <String, dynamic>{};
    final errors = <String>[];

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

    for (final entry in data.entries) {
      final field = fields[entry.key];
      if (field != null) {
        final result = field.validateAndConvert(entry.value);
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

  bool get isValid => fields.isNotEmpty;
}
