import '../schema_field.dart';

class StringSchemaField extends SchemaField<String> {
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final List<String>? enumValues;

  const StringSchemaField({
    required String description,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.enumValues,
    bool required = true,
  }) : super(
    description: description,
    required: required,
  );

  @override
  bool isValidType(Object? value) =>
    value == null || value is String;

  @override
  bool validate(String? value) {
    if (value == null) return !required;
    if (minLength != null && value.length < minLength!) return false;
    if (maxLength != null && value.length > maxLength!) return false;
    if (pattern != null && !RegExp(pattern!).hasMatch(value)) return false;
    if (enumValues != null && !enumValues!.contains(value)) return false;
    return true;
  }

  @override
  String? convert(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }
}
