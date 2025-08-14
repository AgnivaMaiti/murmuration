# Secure API Key Handling in Murmuration

When working with Murmuration and LLM providers (Anthropic, OpenAI, Google), it's crucial to handle API keys securely. This document outlines best practices for managing API keys in your applications.

## Why Secure API Key Handling is Important

- **Prevents unauthorized usage**: Exposed API keys can be used by malicious actors, leading to unexpected charges
- **Protects your account**: Compromised keys may lead to service termination or abuse
- **Maintains user trust**: Proper security practices protect your users' data and privacy
- **Compliance**: Many organizations have security requirements for handling sensitive data

## Best Practices for API Key Management

### 1. Never Hardcode API Keys

❌ **Never** do this in your code:
```dart
// UNSAFE! This exposes your API key in version control
final config = MurmurationConfig(
  apiKey: 'sk-your-api-key-here',
  provider: LLMProvider.anthropic,
);
```

### 2. Recommended Approaches

#### For Mobile/Desktop Apps

##### Option A: Environment Variables (Recommended)

1. Use the `--dart-define` flag when running your app:
   ```bash
   # For development
   flutter run --dart-define=ANTHROPIC_API_KEY=your_key_here \
               --dart-define=OPENAI_API_KEY=your_key_here \
               --dart-define=GEMINI_API_KEY=your_key_here
   ```

2. Access the variables in your code:
   ```dart
   final apiKey = const String.fromEnvironment('ANTHROPIC_API_KEY');
   final config = MurmurationConfig(
     apiKey: apiKey,
     provider: LLMProvider.anthropic,
     modelConfig: ModelConfig(
       modelName: 'claude-3-opus-20240229',
       temperature: 0.7,
     ),
   );
   ```

##### Option B: `flutter_dotenv` Package

1. Add the package to `pubspec.yaml`:
   ```yaml
   dependencies:
     flutter_dotenv: ^5.1.0
   ```

2. Create a `.env` file in your project root (add it to `.gitignore`):
   ```env
   # API Keys (replace with your actual keys)
   ANTHROPIC_API_KEY=your_anthropic_api_key
   OPENAI_API_KEY=your_openai_api_key
   GEMINI_API_KEY=your_gemini_api_key
   
   # Optional: Configuration
   DEFAULT_MODEL=claude-3-opus-20240229
   REQUEST_TIMEOUT=60
   ```

3. Load the environment variables in `main.dart`:
   ```dart
   import 'package:flutter_dotenv/flutter_dotenv.dart';
   
   Future<void> main() async {
     await dotenv.load(fileName: ".env");
     runApp(MyApp());
   }
   ```

4. Access the variables:
   ```dart
   final apiKey = dotenv.env['ANTHROPIC_API_KEY']!;
   ```

#### For Web Applications

For web applications, environment variables are embedded in the JavaScript bundle. Consider these approaches:

1. **Backend API**: Create a backend service that makes API calls with the API key
2. **Environment-specific builds**: Use different build configurations for development and production
3. **Secure storage**: For client-side storage, use secure mechanisms like HTTP-only cookies or secure local storage

#### For Production

1. **Backend Proxy**: Create a backend service that makes API calls with the API key
2. **Secret Management Services**:
   - AWS Secrets Manager
   - Google Cloud Secret Manager
   - Azure Key Vault
   - HashiCorp Vault

3. **Environment Variables in CI/CD**:
   - GitHub Secrets
   - GitLab CI/CD Variables
   - Bitbucket Pipelines

### 3. Additional Security Measures

1. **Key Rotation**:
   - Rotate API keys regularly
   - Implement key versioning
   - Have a rollback strategy

2. **Access Control**:
   - Use the principle of least privilege
   - Create separate API keys for different environments
   - Set appropriate rate limits

3. **Monitoring**:
   - Monitor API usage for unusual patterns
   - Set up alerts for unexpected usage spikes
   - Log all API calls (without sensitive data)

### 4. Example: Secure Configuration

```dart
class Config {
  static String get anthropicApiKey => const String.fromEnvironment(
    'ANTHROPIC_API_KEY',
    defaultValue: '',
  );

  static String get openaiApiKey => const String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static String get geminiApiKey => const String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static bool get isProd => const bool.fromEnvironment('dart.vm.product');
}
```

## Common Pitfalls

1. **Committing `.env` files**: Always add `.env` to your `.gitignore`
2. **Logging sensitive data**: Be careful not to
   ```
   OPENAI_API_KEY=your_key_here
   GEMINI_API_KEY=your_key_here
   ANTHROPIC_API_KEY=your_key_here
   ```

3. Load and use the environment variables:
   ```dart
   import 'package:flutter_dotenv/flutter_dotenv.dart';

   Future<void> main() async {
     await dotenv.load(fileName: ".env");
     final apiKey = dotenv.env['ANTHROPIC_API_KEY']!;
     
     final config = MurmurationConfig(
       apiKey: apiKey,
       provider: LLMProvider.anthropic,
       // ...
     );
     // ...
   }
   ```

#### Option C: Backend Service (Production)

For production applications, the most secure approach is to never include API keys in your app bundle. Instead:

1. Create a backend service that makes API calls on behalf of your app
2. Authenticate your app users with your backend
3. Have your backend manage the LLM provider API keys

## Example: Secure Configuration with Environment Variables

```dart
import 'package:flutter/material.dart';
import 'package:murmuration/murmuration.dart';

void main() {
  // Get API key from environment
  const apiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  
  if (apiKey.isEmpty) {
    throw Exception('API key not provided. Set ANTHROPIC_API_KEY environment variable.');
  }

  // Initialize Murmuration with the API key
  final config = MurmurationConfig(
    apiKey: apiKey,
    provider: LLMProvider.anthropic,
    modelConfig: ModelConfig(
      modelName: 'claude-3-opus-20240229',
      temperature: 0.7,
      maxTokens: 1000,
    ),
  );

  runApp(MyApp(config: config));
}

class MyApp extends StatelessWidget {
  final MurmurationConfig config;

  const MyApp({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murmuration Demo',
      home: ChatScreen(config: config),
    );
  }
}
```

## Securing API Keys in Version Control

1. **Add sensitive files to .gitignore**:
   ```
   # Environment variables
   .env
   *.env
   
   # Configuration files with secrets
   config/*.json
   ```

2. **Use git-secret or similar tools** for encrypting sensitive files

3. **Never commit API keys** in code, configuration files, or documentation

## Production Deployment

For production apps, consider:

1. Using a backend service to proxy API calls
2. Implementing user authentication
3. Setting up rate limiting and usage quotas
4. Using API key rotation
5. Monitoring for unusual activity

## Troubleshooting

- **Missing API key errors**: Verify the environment variable is correctly set and accessible
- **Permission issues**: Ensure your API key has the necessary permissions
- **Rate limiting**: Implement proper error handling and retries in your code
