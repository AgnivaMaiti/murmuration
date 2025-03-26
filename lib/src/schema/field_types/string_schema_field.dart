import '../schema_field.dart';

class StringSchemaField extends SchemaField<String> {
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  
  @override
  List<String>? get enumValues => _enumValues;
  final List<String>? _enumValues;

  const StringSchemaField({
    required String description,
    this.minLength,
    this.maxLength,
    this.pattern,
    List<String>? enumValues,
    bool required = true,
  }) : _enumValues = enumValues,
       super(
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
    if (_enumValues != null && !_enumValues!.contains(value)) return false;
    return true;
  }

  @override
  String? convert(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }
}
