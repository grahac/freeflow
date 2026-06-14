# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-06-14

Brings in upstream FreeFlow v1.0.0 and v1.1.0 (minus the screenshot-capture path, which this privacy fork does not ship).

### Added
- Model picker dropdowns in Settings for transcription, post-processing, fallback, and context models — including Qwen 3 32B and a custom model entry.
- Recording overlay display picker — show the overlay on the active window, the primary display, or a specific connected monitor.
- In-pill error notifications so transient network or provider failures are visible without opening the Run Log.
- Configurable network timeouts via `defaults write com.zachlatta.freeflow <key> -float N` for `transcription_timeout_seconds`, `post_processing_timeout_seconds`, and `context_request_timeout_seconds` — useful for slow or local models.

### Improved
- Retried dictations now place the successful transcript on the clipboard and update Paste Again.
- Paste Again preserves the latest raw transcript earlier in the dictation flow, so it survives later cleanup or paste failures.
- Post-processing handles reasoning-model output more cleanly, including Qwen thinking tags and providerless model aliases.

### Fixed
- Transcription no longer hangs indefinitely when a provider accepts the connection but never returns a response (added a hard timeout).
- Duplicate in-pill error notifications are no longer dismissed by an older timer.
- Permission polling now stops once permissions are granted.

## [0.4.2] - 2026-05-22

### Added
- "Paste Again" keyboard shortcut — bind a key to re-paste your last dictation in a single keypress. Settings adds a third shortcut row alongside Hold to Talk / Tap to Toggle, the setup wizard gets an optional step, and the menu bar dropdown gains a submenu so you can bind it without opening Settings.
- Dictated text is now marked as transient on the clipboard, so clipboard managers (Maccy, Raycast, Paste, Clipy, Flycut, etc.) skip it instead of polluting your clipboard history with every dictation.
- DMG install window has a branded background behind the FreeFlow → Applications drag.

### Improved
- Post-processing now preserves spoken instructions verbatim. Phrases like "write a message to John saying X" used to occasionally get drafted into a message by the LLM; they now transcribe as the literal spoken sentence.

### Fixed
- Clipboard restore no longer leaves the dictated transcript stranded on the clipboard when browsers, iCloud Universal Clipboard, or background apps bump the pasteboard change count between dictation and restore.

## [0.4.1] - 2026-05-14

### Added
- Recent transcripts list in the menu bar, with "Copy" and "Copy literal" actions.
- Debug Settings tab with controls for the debug overlay.
- Minimalist menu-bar recording overlay (drop-down style, configurable).
- "Open Run Log" and "Check for Updates" entries in the menu bar.
- Friendly modifier names in shortcut UI (Cmd ⌘, Right Option ⌥, etc.).
- Per-repo contributor avatar rows on the welcome and Settings screens for both grahac/freeflow and zachlatta/freeflow.

### Improved
- Transcribing spinner appears sooner and the recording overlay has cleaner state transitions.
- Trailing space added automatically after sentence-ending punctuation when pasting.
- Friendlier one-line messages for transcription submission errors.
- Setup wizard restores prior app state when closed without completing.
- App is no longer auto-terminated by macOS mid-dictation.
- Refreshed dev-build app icons.

### Fixed
- Auto-updates now pull from `grahac/freeflow` instead of upstream `zachlatta/freeflow`, so privacy-fork installs no longer revert to the screenshot-capture build on update.
- Allow both dictation shortcuts to be disabled together.
- Edit-mode self-collision when a toggle binding overlaps the manual modifier.
- Hang in "Check for Updates" caused by the alert running off the main thread.

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
