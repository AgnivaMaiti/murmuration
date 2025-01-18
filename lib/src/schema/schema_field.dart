import 'validation_result.dart';

abstract class SchemaField<T> {
  final String description;
  final List<T>? enumValues;
  final T? defaultValue;
  final bool required;

  const SchemaField({
    required this.description,
    this.enumValues,
    this.defaultValue,
    this.required = true,
  });

  bool isValidType(Object? value);
  bool validate(T? value);
  T? convert(Object? value);

  ValidationResult<T> validateAndConvert(Object? value) {
    try {
      if (!isValidType(value) && value != null) {
        return ValidationResult.failure('Invalid type');
      }

      final converted = convert(value);
      if (!validate(converted)) {
        return ValidationResult.failure('Validation failed');
      }

      return ValidationResult.success(converted);
    } catch (e, stackTrace) {
      return ValidationResult.failure('Conversion error: $e', stackTrace);
    }
  }
}
