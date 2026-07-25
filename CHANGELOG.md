# Changelog

All notable PromptHalo changes are documented here.

## 0.3.0 — 2026-07-26

### Added

- Chinese and English interface
- System-language default with manual language selection
- Five rewritten long starter prompts in Chinese and English
- Lightweight core self-test runner
- Universal Apple silicon and Intel build pipeline

### Changed

- Default trigger changed from `Option + Space` to long-press Left `Option`
- Existing users on the old default are migrated once
- Interface-language changes no longer affect stored prompt content

### Verified

- Core self-tests: 6/6
- Universal binary architectures: arm64 and x86_64
- Left Option + slot 1 direct insertion into TextEdit

### Known limitations

- The public Alpha is not Apple-notarized
- Accessibility permission recovery still needs hardening
- Target-window changes are not yet blocked before paste
