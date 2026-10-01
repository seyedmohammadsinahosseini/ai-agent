# Changelog

All notable changes to AI Terminal are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The project does not yet publish stable semantic-version tags, so current work remains under **Unreleased**.

## [Unreleased]

### Added

- Deterministic C++ read-only allowlist with unknown-command confirmation by default.
- Strict server-side Plan-mode policy for redirection, pipelines, chaining, substitutions, nested expressions, multiline commands, and unknown commands.
- Workspace policy with normalized working directories and common path-escape blocking.
- Native desktop token-file loading.
- Trusted Host middleware and explicit local CORS origin configuration.
- Short-lived, one-use WebSocket execution tickets.
- Exact command binding between a confirmed execution and its stored assistant suggestion.
- Windows Job Object process-tree ownership.
- POSIX process-group termination for Stop and timeout.
- Persistent execution output, exit code, and stopped state for confirmed WebSocket runs.
- Full user/assistant conversation context with aggregate bounds.
- Explicit untrusted-data framing for attachment text.
- Context-upload deletion endpoint and stale scratch cleanup.
- Filename hardening for path traversal, Windows reserved names, and excessive component length.
- Request, command, attachment, context, and output size limits.
- Python unit and FastAPI/native/WebSocket integration tests.
- Native risk-classifier and PTY smoke tests through CTest.
- Flutter tests for Plan/Build switching and risk-value mapping.
- AI Terminal product icons and a reproducible Pillow generation script.
- Root project documents: roadmap, architecture, changelog, and decision records.

### Changed

- Windows execution now launches non-interactive PowerShell directly instead of nesting commands in `cmd.exe /C`.
- Only explicitly recognized read-only commands may auto-run.
- Build mode requires a valid writable working directory.
- Confirmed execution uses the workspace captured when the command was proposed.
- Native and UI output retention is bounded.
- The desktop client no longer requests the long-lived token over HTTP.
- The local token is no longer printed at server startup.
- API key saving fails closed when the OS credential store is unavailable.
- Chat requests include assistant turns, proposed commands, and bounded command output.
- Model selection is reset when its provider/model is removed.
- Attachment sending waits for upload completion.
- Context uploads are discarded after use or removal.
- Windows executable name, resource metadata, window title, web metadata, and icons now use the AI Terminal identity.
- Flutter package version aligned with the current pre-release server version.
- Security and workspace claims in the UI and documentation now distinguish path guarding from OS sandboxing.

### Fixed

- Plan-mode write bypass through output redirection such as `echo ... > file`.
- Default-safe behavior for unknown commands.
- Missing assistant turns in provider conversation history.
- Loss of output from user-confirmed WebSocket execution after reopening a chat.
- Race allowing a message to be sent before attachment upload completed.
- Stale model selection after a provider was removed.
- WebSocket command-start race that could attach output to the wrong message.
- Stop behavior that could leave descendant processes running intentionally.
- Unbounded synchronous output capture and live UI output accumulation.
- Context scratch files accumulating after normal use.
- Placeholder Flutter project metadata in desktop and web builds.
- MSVC C2589 build failure caused by the Windows SDK `min` macro colliding with `std::min`.

### Security

- Replaced wildcard CORS with an explicit local allowlist.
- Added DNS-rebinding-oriented Host validation.
- Restricted web token bootstrap to loopback and allowed/same origins by default.
- Removed the long-lived token from WebSocket URLs.
- Added constant-time bearer-token comparison.
- Added command/message integrity verification before confirmed execution.
- Added fail-closed secret storage with an explicit development-only plaintext override.
- Added bounded prompt construction and upload handling.
- Added prompt-injection-oriented handling for attachments and terminal output.
- Added permanently blocked patterns for catastrophic disk, boot, protection, and recovery operations.

### Documentation

- Rewritten README with accurate setup, security, privacy, configuration, testing, and limitation sections.
- Added a prioritized roadmap with explicit release gates.
- Added a complete component, trust-boundary, and data-flow architecture document.
- Added consolidated architectural decision records.
- Updated Windows setup instructions for direct PowerShell execution and private token handling.

## Release history

No tagged release has been published from this repository yet. When the first release is tagged, move the relevant entries from `Unreleased` into a dated version section and add compare links.
