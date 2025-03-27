class ValidationResult<T> {
  final T? value;
  final String? error;
  final StackTrace? stackTrace;
  final bool isSuccess;
  final List<String> errors;
  final Map<String, dynamic>? data;

  ValidationResult.success(this.value, [this.data])
      : error = null,
        stackTrace = null,
        isSuccess = true,
        errors = const [];

  ValidationResult.failure(
    this.error, {
    this.stackTrace,
    this.data,
  })  : value = null,
        isSuccess = false,
        errors = error != null ? [error] : const [];

  bool get isValid => isSuccess;
}
