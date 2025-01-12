// Class for logging messages and errors.
class MurmurationLogger {
  final bool enabled;
  final void Function(String)? onLog;
  final void Function(String)? onError;

  const MurmurationLogger({
    this.enabled = false,
    this.onLog,
    this.onError,
  });

  void log(String message) {
    if (enabled && onLog != null) {
      onLog!(message);
    }
  }

  void error(String message) {
    if (enabled && onError != null) {
      onError!(message);
    }
  }
}
