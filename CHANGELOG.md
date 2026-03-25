# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Customizable hold and toggle dictation shortcuts with modifier-only key support
- Clipboard preservation — original clipboard restored after pasting transcribed text
- Audio normalization to 16kHz mono before upload for consistent transcription quality
- HTTP/2 curl fallback option for transcription (Settings > Advanced)
- Configurable sound volume for recording start/stop sounds
- Configurable shortcut start delay (0–500ms) to prevent accidental triggers

### Changed
- Switch transcription model from whisper-large-v3 to whisper-large-v3-turbo for faster voice processing
- Rewrite post-processing prompt to eliminate LLM commentary leaking into output
- Improve spoken number list detection (e.g. "one ... two ... three" formats as 1. 2. 3.)
- Recording overlay adapts UI for hold vs toggle mode
- Makefile hardened for paths with spaces and improved DMG creation

### Fixed
- Custom vocabulary overriding unrelated words in transcription
- Hotkey event consumption across key state transitions

## [0.1.0] - 2026-02-25

### Added
- macOS menubar voice-to-text dictation app with global hotkey
- Groq Whisper transcription with delayed transcribing indicator
- LLM-powered post-processing with customizable system and context prompts
- Screenshot capture for context (optional, toggle in Settings)
- Recording overlay with liquid glass effect
- Pipeline debug panel and run log with audio playback
- In-app auto-updates with build tag tracking
- Microphone selection in setup flow and settings
- Launch-at-login support
- Styled DMG with drag-to-Applications install experience
- Developer ID code signing, notarization, and stapling
- GitHub star card in settings showing both grahac/freeflow and zachlatta/freeflow
- Dynamic menu bar waveform icon
- Alternative base URL setting for API
- Custom system prompt and context prompt settings
- Recent GitHub stargazers display in settings

### Fixed
- Data race on isRecording read from audio tap thread
- Microphone crash handling
- Shell injection vulnerability in update script
- Spazzy update download progress bar
- Silent CoreData errors and partial store cleanup
- Force unwrap crashes in avatar URL construction and other locations
- Audio device listener cleanup on deinit
- Temp audio file cleanup when no audio recorded
- App icon shape for macOS conventions

### Changed
- Screenshots made optional (removed screen recording requirement from setup)
- Moved API key storage from Keychain to app-private settings file
- Reduced audio and screenshot bandwidth ~20x
- Improved post-processing prompt to prevent hallucinated insertions
- More idiomatic Swift UI patterns
- Dynamic notch size detection
- Fork attribution showing both upstream and fork repositories

### Security
- Pinned CI action SHAs and hardened signing workflow
- Fixed shell injection in update script

[Unreleased]: https://github.com/grahac/freeflow/compare/build-20260225-025611-94e75f9...HEAD
[0.1.0]: https://github.com/grahac/freeflow/commits/build-20260225-025611-94e75f9
