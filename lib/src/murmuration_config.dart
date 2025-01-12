import 'logger.dart';

class MurmurationConfig {
  final String apiKey;
  final String model;
  final bool debug;
  final bool stream;
  final MurmurationLogger logger;

  // Configuration for the Murmuration API client.
  MurmurationConfig({
    required this.apiKey,
    this.model = 'gemini-1.5-flash-latest',
    this.debug = false,
    this.stream = false,
    MurmurationLogger? logger,
  }) : logger = logger ?? MurmurationLogger();
}
