import '../schema_field.dart';

class StringSchemaField extends SchemaField<String> {
  final int? minLength;
  final int? maxLength;
  final Pattern? pattern;

  const StringSchemaField({
    required String description,
    List<String>? enumValues,
    String? defaultValue,
    bool required = true,
    this.minLength,
    this.maxLength,
    this.pattern,
  }) : super(
          description: description,
          enumValues: enumValues,
          defaultValue: defaultValue,
          required: required,
        );

  @override
  bool isValidType(Object? value) => value == null || value is String;

  @override
  bool validate(String? value) {
    if (value == null) return required != true;
    if (enumValues != null && !enumValues!.contains(value)) return false;
    if (minLength != null && value.length < minLength!) return false;
    if (maxLength != null && value.length > maxLength!) return false;
    if (pattern != null && !RegExp(pattern.toString()).hasMatch(value)) {
      return false;
    }
    return true;
  }

  @override
  String? convert(Object? value) {
    if (value == null) return null;
    return value.toString();
  }
}
