class MurmurationException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  MurmurationException(this.message, [this.originalError, this.stackTrace]);

  @override
  String toString() => 'MurmurationException: $message'
      '${originalError != null ? '\nCaused by: $originalError' : ''}'
      '${stackTrace != null ? '\n$stackTrace' : ''}';
}
