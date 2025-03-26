import 'dart:convert';
import '../exceptions.dart';

enum MessageRole { system, user, assistant, function, tool }

class Message {
  final MessageRole role;
  final String content;
  final Map<String, dynamic>? functionCall;
  final String? name;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;
  final String? correlationId;
  final List<String>? tags;
  final Map<String, dynamic>? context;

  Message({
    required this.role,
    required this.content,
    this.functionCall,
    this.name,
    this.metadata,
    DateTime? timestamp,
    this.correlationId,
    this.tags,
    this.context,
  }) : timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    MessageRole? role,
    String? content,
    Map<String, dynamic>? functionCall,
    String? name,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
    String? correlationId,
    List<String>? tags,
    Map<String, dynamic>? context,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      functionCall: functionCall ?? this.functionCall,
      name: name ?? this.name,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp ?? this.timestamp,
      correlationId: correlationId ?? this.correlationId,
      tags: tags ?? this.tags,
      context: context ?? this.context,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };

    if (functionCall != null) {
      json['function_call'] = Map<String, dynamic>.from(functionCall!);
    }

    if (name != null) {
      json['name'] = name!;
    }

    if (metadata != null) {
      json['metadata'] = Map<String, dynamic>.from(metadata!);
    }

    if (correlationId != null) {
      json['correlation_id'] = correlationId!;
    }

    if (tags != null) {
      json['tags'] = List<String>.from(tags!);
    }

    if (context != null) {
      json['context'] = Map<String, dynamic>.from(context!);
    }

    return json;
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    try {
      return Message(
        role: MessageRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => throw ValidationException(
            'Invalid message role: ${json['role']}',
            errorDetails: {'role': json['role']},
          ),
        ),
        content: json['content'] as String,
        functionCall: json['function_call'] as Map<String, dynamic>?,
        name: json['name'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        correlationId: json['correlation_id'] as String?,
        tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
        context: json['context'] as Map<String, dynamic>?,
      );
    } catch (e, stackTrace) {
      throw ValidationException(
        'Failed to parse message: $e',
        errorDetails: {'json': json},
        stackTrace: stackTrace,
      );
    }
  }

  factory Message.fromJsonString(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      return Message.fromJson(data);
    } catch (e, stackTrace) {
      throw ValidationException(
        'Failed to parse message JSON string: $e',
        errorDetails: {'jsonString': jsonString},
        stackTrace: stackTrace,
      );
    }
  }

  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() {
    return 'Message(role: $role, content: $content, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          role == other.role &&
          content == other.content &&
          functionCall == other.functionCall &&
          name == other.name &&
          metadata == other.metadata &&
          timestamp == other.timestamp &&
          correlationId == other.correlationId &&
          tags == other.tags &&
          context == other.context;

  @override
  int get hashCode => Object.hash(
        role,
        content,
        functionCall,
        name,
        metadata,
        timestamp,
        correlationId,
        Object.hashAll(tags ?? []),
        Object.hashAll(context?.entries ?? []),
      );
}
