import 'validation_result.dart';
import '../exceptions.dart';

abstract class SchemaField<T> {
  final String description;
  final List<T>? enumValues;
  final T? defaultValue;
  final bool required;
  final String? pattern;
  final T? minimum;
  final T? maximum;
  final int? minLength;
  final int? maxLength;
  final List<T>? examples;

  const SchemaField({
    required this.description,
    this.enumValues,
    this.defaultValue,
    this.required = true,
    this.pattern,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
    this.examples,
  });

  bool isValidType(Object? value);
  bool validate(T? value);
  T? convert(Object? value);

  ValidationResult<T> validateAndConvert(Object? value) {
    try {
      if (!isValidType(value) && value != null) {
        return ValidationResult.failure('Invalid type: expected ${T.toString()}');
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

  @override
  String toString() {
    return 'SchemaField(type: ${T.toString()}, description: $description)';
  }
}

class StringField extends SchemaField<String> {
  const StringField({
    required super.description,
    super.enumValues,
    super.defaultValue,
    super.required = true,
    super.pattern,
    super.minLength,
    super.maxLength,
    super.examples,
  });

  @override
  bool isValidType(Object? value) => value is String;

  @override
  bool validate(String? value) {
    if (value == null) return !required;

    if (enumValues != null && !enumValues!.contains(value)) {
      throw ValidationException(
        'Value must be one of: ${enumValues!.join(', ')}',
        errorDetails: {'value': value, 'allowed': enumValues},
      );
    }

    if (pattern != null) {
      final regex = RegExp(pattern!);
      if (!regex.hasMatch(value)) {
        throw ValidationException(
          'Value does not match pattern: $pattern',
          errorDetails: {'value': value, 'pattern': pattern},
        );
      }
    }

    if (minLength != null && value.length < minLength!) {
      throw ValidationException(
        'Value length must be at least $minLength',
        errorDetails: {'value': value, 'minLength': minLength},
      );
    }

    if (maxLength != null && value.length > maxLength!) {
      throw ValidationException(
        'Value length must be at most $maxLength',
        errorDetails: {'value': value, 'maxLength': maxLength},
      );
    }

    return true;
  }

  @override
  String? convert(Object? value) => value?.toString();
}

class NumberField extends SchemaField<num> {
  const NumberField({
    required super.description,
    super.enumValues,
    super.defaultValue,
    super.required = true,
    super.minimum,
    super.maximum,
    super.examples,
  });

  @override
  bool isValidType(Object? value) => value is num;

  @override
  bool validate(num? value) {
    if (value == null) return !required;

    if (enumValues != null && !enumValues!.contains(value)) {
      throw ValidationException(
        'Value must be one of: ${enumValues!.join(', ')}',
        errorDetails: {'value': value, 'allowed': enumValues},
      );
    }

    if (minimum != null && value < minimum!) {
      throw ValidationException(
        'Value must be at least $minimum',
        errorDetails: {'value': value, 'minimum': minimum},
      );
    }

    if (maximum != null && value > maximum!) {
      throw ValidationException(
        'Value must be at most $maximum',
        errorDetails: {'value': value, 'maximum': maximum},
      );
    }

    return true;
  }

  @override
  num? convert(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}

class BooleanField extends SchemaField<bool> {
  const BooleanField({
    required super.description,
    super.defaultValue,
    super.required = true,
    super.examples,
  });

  @override
  bool isValidType(Object? value) => value is bool;

  @override
  bool validate(bool? value) {
    if (value == null) return !required;
    return true;
  }

  @override
  bool? convert(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return null;
  }
}

class ListField<T> extends SchemaField<List<T>> {
  final SchemaField<T> itemField;
  final bool uniqueItems;

  const ListField({
    required super.description,
    required this.itemField,
    super.defaultValue,
    super.required = true,
    super.minLength,
    super.maxLength,
    this.uniqueItems = false,
    super.examples,
  });

  @override
  bool isValidType(Object? value) => value is List;

  @override
  bool validate(List<T>? value) {
    if (value == null) return !required;

    if (minLength != null && value.length < minLength!) {
      throw ValidationException(
        'List length must be at least $minLength',
        errorDetails: {'length': value.length, 'minLength': minLength},
      );
    }

    if (maxLength != null && value.length > maxLength!) {
      throw ValidationException(
        'List length must be at most $maxLength',
        errorDetails: {'length': value.length, 'maxLength': maxLength},
      );
    }

    if (uniqueItems) {
      final uniqueSet = value.toSet();
      if (uniqueSet.length != value.length) {
        throw ValidationException(
          'List must contain unique items',
          errorDetails: {'length': value.length, 'uniqueLength': uniqueSet.length},
        );
      }
    }

    return true;
  }

  @override
  List<T>? convert(Object? value) {
    if (value == null) return null;
    if (value is! List) return null;

    final result = <T>[];
    for (final item in value) {
      final converted = itemField.convert(item);
      if (converted != null) {
        result.add(converted);
      }
    }
    return result;
  }
}

class MapField extends SchemaField<Map<String, dynamic>> {
  final Map<String, SchemaField> properties;
  final bool additionalProperties;

  const MapField({
    required super.description,
    required this.properties,
    super.defaultValue,
    super.required = true,
    this.additionalProperties = false,
    super.examples,
  });

  @override
  bool isValidType(Object? value) => value is Map;

  @override
  bool validate(Map<String, dynamic>? value) {
    if (value == null) return !required;

    for (final entry in properties.entries) {
      final field = entry.value;
      final fieldValue = value[entry.key];
      final result = field.validateAndConvert(fieldValue);
      if (!result.isSuccess) {
        throw ValidationException(
          'Invalid value for ${entry.key}: ${result.error}',
          errorDetails: {'field': entry.key, 'error': result.error},
        );
      }
    }

    if (!additionalProperties) {
      for (final key in value.keys) {
        if (!properties.containsKey(key)) {
          throw ValidationException(
            'Unknown property: $key',
            errorDetails: {'key': key},
          );
        }
      }
    }

    return true;
  }

  @override
  Map<String, dynamic>? convert(Object? value) {
    if (value == null) return null;
    if (value is! Map) return null;

    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return result;
  }
}
