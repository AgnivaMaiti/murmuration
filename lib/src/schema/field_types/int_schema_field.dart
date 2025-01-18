import '../schema_field.dart';

class IntSchemaField extends SchemaField<int> {
  final int? min;
  final int? max;

  const IntSchemaField({
    required String description,
    List<int>? enumValues,
    int? defaultValue,
    bool required = true,
    this.min,
    this.max,
  }) : super(
          description: description,
          enumValues: enumValues,
          defaultValue: defaultValue,
          required: required,
        );

  @override
  bool isValidType(Object? value) =>
      value == null ||
      value is int ||
      (value is String && int.tryParse(value) != null);

  @override
  bool validate(int? value) {
    if (value == null) return required != true;
    if (enumValues != null && !enumValues!.contains(value)) return false;
    if (min != null && value < min!) return false;
    if (max != null && value > max!) return false;
    return true;
  }

  @override
  int? convert(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}
