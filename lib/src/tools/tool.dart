import '../schema/schema_field.dart';

class Tool {
  final String name;
  final String description;
  final Map<String, SchemaField> parameters;
  final Future<dynamic> Function(Map<String, dynamic>) execute;

  const Tool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });
}

class FunctionCall {
  final String name;
  final Map<String, dynamic> parameters;

  const FunctionCall({
    required this.name,
    required this.parameters,
  });
}
