import '../exceptions.dart';

class Message {
  final String role;
  final String content;
  final DateTime timestamp;

  Message({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) {
    try {
      return Message(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to parse message from JSON',
        e,
        stackTrace,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          role == other.role &&
          content == other.content &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(role, content, timestamp);
}
