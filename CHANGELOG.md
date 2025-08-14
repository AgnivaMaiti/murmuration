# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.2] - 2025-08-14

### Fixed
- Updated Anthropic SDK integration to use the official `anthropic_sdk_dart` package
- Fixed dependency issues in pubspec.yaml
- Added missing dependencies: `path` and `crypto` packages
- Moved `flutter_dotenv` to main dependencies as it's used in the main package
- Fixed various analyzer warnings and improved type safety

### Changed
- Updated example code to work with the new Anthropic SDK
- Improved error handling in the Anthropic client
- Updated documentation and tutorials to reflect the new SDK usage

## [3.1.1] - 2025-08-14

### Added
- New state management with `state_synchronizer.dart`
- Enhanced caching system in `lib/src/cache/`
- Example implementation in `example.dart`
- Environment variable template (`.env.example`)

## [3.1.0] - 2025-08-14

### Added
- Full support for Anthropic Claude models (Opus, Sonnet, Haiku)
- Comprehensive API key handling documentation
- Example code for secure API key management in Flutter/Android
- Environment variable support for API keys in non-Android contexts
- Rate limiting and error handling for Anthropic API
- Documentation for multi-provider usage patterns

## [3.0.0] - 2025-03-27

### Added
- Support for multiple LLM providers (OpenAI, Google, Anthropic)
- Enhanced tool system with better type safety and validation
- Improved state management with thread safety
- Comprehensive error handling system
- New logging and monitoring capabilities
- Security improvements
- Resource management features
- Message history management
- Schema validation system

### Changed
- Completely restructured package architecture
- Improved API design for better usability
- Enhanced type safety throughout the package
- Better error handling and reporting
- More efficient resource management

### Deprecated
- None

### Removed
- None

### Fixed
- Various bug fixes and improvements

### Security
- Added secure API key handling
- Added input sanitization
- Added rate limiting
- Added access control mechanisms

## [2.0.0] - 19-01-2025

### Breaking Changes

- Introduced new schema system with abstract `SchemaField` class and type-specific implementations
- Implemented immutable state management system with `ImmutableState` class
- Redesigned message history system with thread safety and memory management
- Added new validation system with `ValidationResult` class
- Changed Agent class to use builder pattern for construction
- Introduced immutable `MurmurationConfig` with expanded options
- Modified core classes' constructors

### Added

- Enhanced error handling with `MurmurationException` class
- Improved logging system with structured logging capabilities
- Thread-safe caching mechanism for message history
- Type-safe schema validation for input/output
- Memory management features for long-running conversations
- Example implementation of murmuration for a chatbot and text classifier

### Changed

- Improved function call handling and parameter parsing
- Enhanced thread safety throughout the framework
- Upgraded progress tracking system
- Optimized streaming response handling
- Better type safety implementation across all components

### Security

- Added better input validation and sanitization
- Improved error message safety to prevent information leakage
- Enhanced thread-safety for concurrent operations

## [1.0.1] - 13-01-2025

### Updated

- Enhanced the README file for better clarity and usability.

### Fixed

- Minor typos and formatting issues in the documentation.

## [1.0.0] - 13-01-2025

### Added

- Initial release of the Murmuration framework.
- Support for orchestrating multi-agent interactions using Google's Generative AI models.
- Comprehensive documentation including installation, quick start, key features, core concepts, and best practices.
- Features for agent management, function registration, tool integration, state management, progress tracking, and streaming support.
- Error handling and debugging capabilities.
- API reference for configuration options and agent functions.
- Guidelines for contributing to the project.
