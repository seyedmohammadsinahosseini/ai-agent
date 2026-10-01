# AI Terminal Roadmap

This roadmap describes intended direction, not a promise of dates or scope. Security and correctness take priority over feature count.

## Status legend

- **Complete** — implemented and covered by the current codebase.
- **In progress** — implementation has started but the release gate is not met.
- **Planned** — accepted direction with no complete implementation yet.
- **Research** — requires prototyping or an architectural decision before commitment.

## Current baseline

### Complete

- Flutter Windows/web chat interface.
- Local FastAPI service with bearer authentication.
- Strict Host and CORS configuration.
- Native token-file loading for the desktop client.
- One-use WebSocket execution tickets.
- OpenAI, Anthropic, Gemini, and custom OpenAI-compatible providers.
- Provider-native tool/function calling with compatibility fallback.
- Native C++ risk classification.
- Read-only allowlist; unknown commands require confirmation.
- Server-side Plan-mode enforcement.
- Workspace normalization and common path-escape blocking.
- Direct PowerShell execution through Windows ConPTY.
- Windows Job Object and POSIX process-group termination.
- Streaming output, Stop, timeout, and output bounds.
- SQLite chat history and confirmed-output persistence.
- OS keyring storage with fail-closed behavior.
- Bounded context uploads, cleanup, and filename hardening.
- Python unit/integration tests and native CTest coverage.
- Product metadata and generated application icons.

### In progress

- Native Windows validation across supported Windows and Python versions.
- Flutter widget and end-to-end coverage beyond core interactions.
- Adversarial PowerShell and command-obfuscation corpus.
- Consistent application packaging and versioning.

## P0 — Release foundation

These items block the first public test release.

### Windows compatibility matrix

- Test Windows 10 22H2 and current Windows 11.
- Test supported Python versions and matching `.pyd` builds.
- Validate ConPTY quoting, Unicode, long paths, and process-tree termination.
- Validate keyring behavior with Windows Credential Manager.
- Validate native token discovery under standard and custom `AITERM_HOME` paths.

**Exit criteria:** automated or documented evidence for every supported configuration.

### Continuous integration

- Add Python tests on supported Python versions.
- Add Linux native-engine build and CTest.
- Add Flutter format, analyze, and test jobs.
- Add a Windows native-engine and Flutter build job.
- Add secret scanning, dependency review, and artifact retention.
- Require passing checks before merge.

**Exit criteria:** clean checkout to tested artifacts without manual source edits.

### API contract and migrations

- Publish an OpenAPI snapshot for compatibility review.
- Add schema migration infrastructure for SQLite.
- Add migration/version metadata for local app state.
- Define backward compatibility rules between client and server versions.
- Add startup diagnostics for incompatible native modules.

**Exit criteria:** upgrades preserve supported local state or fail with a clear recovery path.

### Security baseline

- Write a formal threat model covering browser, local process, provider, uploaded content, and command output boundaries.
- Add a responsible disclosure policy.
- Add automated dependency vulnerability scanning.
- Expand risk and Plan-mode bypass regression tests.
- Add tests for Windows path forms, reparse points, symlinks, ADS, and quoting.
- Review local bootstrap behavior against DNS rebinding and browser changes.

**Exit criteria:** no open critical/high finding in the defined pre-release threat model.

### Project governance

- Choose and add a software license.
- Define contribution and review rules.
- Add issue and pull-request templates.
- Define supported platforms and version policy.

## P1 — Enforceable execution boundary

This is the highest-priority architectural milestone after the release foundation.

### Brokered operations

- Introduce structured file tools for common create/read/update/move/delete operations.
- Resolve and validate paths after symlink/reparse-point traversal.
- Prefer structured operations over arbitrary shell commands for normal tasks.
- Preserve command-line mode for advanced workflows behind stronger consent.

### Windows sandbox research

Evaluate and document one enforceable production design:

- AppContainer/low-privilege worker with a broker;
- a dedicated restricted local account;
- Windows Sandbox or Hyper-V isolation;
- a disposable VM/container boundary where platform constraints permit it.

The chosen design must address filesystem, registry, process, device, and network access—not only the working directory string.

### Capability policy

- Declare required capabilities per operation: workspace read, workspace write, network, package installation, process control, registry, or system administration.
- Make capabilities visible in confirmation UI.
- Deny undeclared capabilities at the broker boundary.
- Add per-chat or per-task capability grants with expiration.

### Recovery and undo

- Route deletions through Recycle Bin where possible.
- Add pre-change snapshots for supported file operations.
- Surface a user-visible change list before execution.
- Add best-effort rollback for brokered operations.

**Exit criteria:** normal file workflows are enforceably limited to granted capabilities and have a tested recovery story.

## P2 — Privacy, audit, and policy depth

### Secret and sensitive-data handling

- Redact likely tokens, passwords, private keys, and connection strings from output before later provider requests.
- Add user-visible disclosure when content will leave the machine.
- Allow per-message exclusion of command output from provider context.
- Add provider-specific retention/privacy notes.

### Audit trail

- Add a structured append-only local audit log.
- Record policy decisions, command hashes, confirmations, execution IDs, exit status, and stop/timeout events.
- Never write provider API keys or the local bearer token to logs.
- Add export and retention controls.

### Policy engine evolution

- Split lexical classification from semantic capability policy.
- Add signed policy versions and test fixtures.
- Build a larger adversarial corpus for PowerShell, cmd, WSL, interpreters, aliases, and encoded payloads.
- Add property/fuzz testing for parsers and path checks.

### Provider-output isolation

- Separate model text, tool arguments, attachment data, and terminal output in the internal message model.
- Prevent untrusted file/output text from being promoted into higher-priority instructions.
- Add provider adapter contract tests using recorded sanitized fixtures.

## P3 — Product readiness

### Desktop lifecycle

- Start, monitor, and stop the local service from the desktop app.
- Verify server/native-engine version compatibility at startup.
- Add a clear diagnostics screen for ports, token path, keyring, native engine, and provider status.
- Prevent accidental multiple conflicting server instances.

### Packaging and updates

- Produce a signed MSIX or equivalent Windows installer.
- Package the matching Python runtime and native engine, or replace that boundary with a self-contained service binary.
- Add code signing for executable and installer artifacts.
- Design a signed update channel with rollback.
- Publish checksums and provenance/SBOM artifacts.

### Conversation and workspace experience

- Add chat rename UI and search.
- Add project/workspace profiles.
- Add explicit command history and audit views.
- Add diff previews for supported file changes.
- Add export/import with secret-safe defaults.

### Attachments

- Add safe, bounded extraction for PDF and Office formats.
- Add MIME verification rather than trusting extensions.
- Add archive inspection with decompression-bomb protection.
- Make attachment retention visible and configurable.

### Voice input

- Replace the demo with opt-in speech-to-text.
- Prefer on-device transcription where practical.
- Clearly disclose provider use, retention, and microphone state.
- Add permission and cancellation tests.

## P4 — Provider and agent quality

- Add provider health checks and clearer model capability metadata.
- Add streaming model responses where supported.
- Add retry/backoff with idempotency awareness.
- Add cost/token estimates before large requests.
- Add user-controlled context windows and summarization.
- Add multi-step planning without granting automatic multi-command execution.
- Require a fresh policy decision and user-visible state for every executed step.

## Release gates

### First public test release

- P0 release foundation complete.
- Windows native build validated.
- No known critical/high security finding in the documented threat model.
- Signed or clearly marked test artifacts.
- Upgrade and uninstall instructions.

### Security-focused beta

- Enforceable execution-boundary design selected and implemented for normal file operations.
- Structured audit log and output secret redaction available.
- Recovery/undo path tested.
- Expanded adversarial and fuzz suites running in CI.

### Stable release

- Signed installer and update channel.
- Supported-platform matrix and compatibility policy.
- Brokered/sandboxed normal operations.
- Documented incident response and disclosure process.
- No demo-only control presented as a production feature.

## Explicit non-goals

- Running as a remotely exposed multi-user service.
- Silent execution of arbitrary model-generated commands.
- Bypassing OS security controls or antivirus.
- Storing provider keys in the repository or application config files.
- Claiming that lexical command inspection is a complete sandbox.
