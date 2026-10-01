# AI Terminal Architectural Decisions

This file is the project's consolidated architectural decision record (ADR) log. It records decisions that materially affect security, compatibility, deployment, or long-term maintenance.

## How to use this file

Each decision has:

- **Status** — Proposed, Accepted, Superseded, or Rejected.
- **Date** — decision date.
- **Context** — the problem and constraints.
- **Decision** — the selected approach.
- **Consequences** — benefits, costs, and follow-up work.

Do not silently rewrite an accepted decision when architecture changes. Add a new decision and mark the previous one Superseded.

---

## ADR-001 — Local-only single-user service

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

The application executes commands with the current user's permissions and stores local provider credentials. A remotely exposed or multi-user service would require account isolation, authorization, tenant boundaries, TLS termination, audit controls, and a different execution model.

### Decision

FastAPI binds to `127.0.0.1` by default and is designed as a local single-user companion service for the desktop application. Trusted Host and explicit CORS policies reinforce this assumption.

### Consequences

- The deployment and threat model remain understandable.
- Local browser-origin attacks still require protection.
- A non-loopback bind is a development override, not a supported production topology.
- Remote/multi-user support requires a new architecture, not a configuration toggle.

---

## ADR-002 — BYOK provider model

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Users may prefer different commercial or local models. Operating a central proxy would make the project responsible for provider credentials, billing, availability, and user content.

### Decision

Users bring their own provider keys. The service calls OpenAI, Anthropic, Gemini, or a user-configured OpenAI-compatible endpoint directly.

### Consequences

- The project does not operate a central credential or inference service.
- Provider behavior, model availability, cost, and retention vary by provider.
- The UI and documentation must disclose what content is sent.
- Provider adapters and contract tests are required because APIs differ.

---

## ADR-003 — Native provider tool calling with one command per turn

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Parsing free-form model text into executable commands is unreliable. Modern providers expose structured function/tool calling, but some compatible endpoints do not support it.

### Decision

Define one `run_command` tool that accepts exactly one command and one explanation. Use each built-in provider's native tool shape. Retry a custom compatible provider once with a strict JSON response contract only when it explicitly rejects tool parameters.

### Consequences

- Structured arguments are more reliable than text scraping.
- The tool call remains untrusted and must pass all policy layers.
- Multi-step work requires separate reviewed turns; the model does not receive blanket multi-command authority.
- Minimal providers remain usable through a constrained fallback.

---

## ADR-004 — Native C++ engine for deterministic risk and PTY execution

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Risk decisions must be independent from model output. Windows command execution also requires ConPTY and process lifecycle control.

### Decision

Keep deterministic risk classification and PTY/ConPTY execution in a C++17 module exposed to Python through pybind11.

### Consequences

- Model/provider code cannot redefine the classifier's result.
- Windows ConPTY and Job Object APIs can be used directly.
- Native builds must match the active Python ABI.
- Packaging and cross-platform CI are more complex.
- C++ tests are mandatory for classifier and PTY changes.

---

## ADR-005 — Explicit read-only allowlist; unknown commands require confirmation

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

A denylist cannot enumerate every command, alias, interpreter, script, or obfuscation technique. Treating unmatched input as safe creates an unsafe default.

### Decision

Only complete commands matching an explicit read-only allowlist are `SAFE`. Known writes are `CONFIRM`, privileged/obfuscated/high-impact commands are `DANGEROUS`, catastrophic operations are `BLOCKED`, and all unmatched commands default to `CONFIRM`.

### Consequences

- Unknown commands cannot silently auto-run.
- False positives and extra confirmations are expected.
- The allowlist must remain conservative.
- An allowlist is still not a semantic sandbox; interpreters and scripts require additional boundaries.

---

## ADR-006 — Plan mode is a server-side hard gate

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

A UI toggle or system prompt can be bypassed by a modified client, provider error, or prompt injection.

### Decision

Plan mode is enforced by the server using a complete-command read-only allowlist. Redirection, chaining, pipelines, substitutions, nested expressions, multiline commands, environment/home expansion, and unknown commands are rejected before execution.

### Consequences

- A modified UI cannot turn Plan mode into Build mode execution.
- Some legitimate read-only shell compositions are rejected.
- Users must switch to Build mode and confirm ambiguous commands.

---

## ADR-007 — Workspace path guard is defense in depth, not a sandbox

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Starting a shell in a directory does not prevent it from accessing other paths. Lexical path inspection can block common mistakes but cannot control arbitrary system calls, scripts, reparse points, registry access, or network access.

### Decision

Validate and normalize the working directory immediately before execution and block common explicit escapes. Do not claim this is an OS sandbox. Track an enforceable broker/AppContainer/VM boundary as future work.

### Consequences

- Common path escapes are stopped early.
- Build mode requires a writable workspace.
- Advanced executables may still act outside the folder with the user's permissions.
- UI and documentation must state the limitation.
- Normal operations should eventually move to structured brokered tools.

---

## ADR-008 — Direct PowerShell execution and process-tree ownership

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Nesting PowerShell commands inside `cmd.exe /C` adds quoting ambiguity. Terminating only the immediate shell may leave descendants running.

### Decision

On Windows, launch non-interactive PowerShell directly through ConPTY and assign the process to a kill-on-close Job Object. On POSIX development hosts, launch through `forkpty` and terminate the process group.

### Consequences

- PowerShell is the single documented Windows command language.
- Quoting has one fewer parser layer.
- Stop and timeout target descendants as well as the shell.
- Native Windows quoting and Job Object behavior require dedicated compatibility tests.

---

## ADR-009 — Native token-file loading and one-use WebSocket tickets

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

An unauthenticated, wildcard-CORS token endpoint allows a malicious website to read the local bearer token. Browsers cannot reliably add a bearer header to WebSocket handshakes, and placing the long-lived token in a query string leaks it to URLs/logs.

### Decision

- Native clients read the private token file directly.
- The optional web client uses a loopback and same-origin constrained bootstrap.
- Protected HTTP routes use the bearer token.
- WebSocket execution uses a random, one-use ticket with a 30-second lifetime.

### Consequences

- The long-lived token is not exposed in WebSocket URLs.
- Browser origin/Host handling is security-sensitive and must be tested.
- The token does not protect against a process already compromised under the same OS user.
- Remote preview requires explicit insecure-development configuration.

---

## ADR-010 — Provider keys use OS keyring and fail closed

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Silently writing provider keys to a JSON file when keyring is unavailable contradicts the product's security claims.

### Decision

Store provider keys through the OS credential store using Python `keyring`. If no secure backend is available, saving fails. A plaintext JSON fallback exists only behind `AITERM_ALLOW_PLAINTEXT_KEY_FALLBACK=1` for isolated development.

### Consequences

- Production does not silently downgrade secret storage.
- Headless Linux development may require keyring setup or explicit insecure fallback.
- The UI must display clear key-storage errors.
- Existing plaintext development files require careful migration/removal.

---

## ADR-011 — Local SQLite chat history with JSON assistant metadata

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

The sidebar and reopened chats need durable local state. Assistant turns evolve faster than a fixed relational column set.

### Decision

Use Python's built-in SQLite for local chats/messages. Store stable message columns relationally and extensible assistant execution metadata in a JSON object. Use WAL mode and a busy timeout.

### Consequences

- No external database dependency is required.
- Confirmed execution output can be attached to the exact assistant turn.
- JSON metadata avoids a migration for every optional display field.
- Formal schema migrations are still required before stable releases.
- Output must be bounded before persistence.

---

## ADR-012 — Confirmed commands are bound to stored assistant suggestions

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

A client could otherwise request a harmless command, display it for confirmation, and submit a different command with `user_confirmed=true`.

### Decision

Every confirmed REST or WebSocket execution must include the chat ID and assistant-message ID. The submitted command must exactly match the `suggested_command.command` stored on that message.

### Consequences

- Confirmation is tied to the text the user reviewed.
- Command edits require a new chat proposal and policy decision.
- Message IDs become part of the execution integrity model.
- This does not prove a human clicked the UI; local authentication and typed confirmation remain relevant.

---

## ADR-013 — Full but bounded conversation context

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Sending only user messages makes follow-up requests lose assistant explanations, proposed commands, and execution results. Sending unlimited history creates cost, latency, privacy, and memory risks.

### Decision

Send both user and assistant turns, including bounded command/output context. Limit messages, per-message size, aggregate provider context, attachment text, and output. Keep recent context when truncation is necessary.

### Consequences

- Follow-up conversations are coherent.
- Provider requests remain bounded.
- Old context may be truncated.
- Command output may contain secrets, so a redaction layer remains required.

---

## ADR-014 — Uploaded content and terminal output are untrusted data

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Files and terminal output can contain prompt-injection instructions. Treating them as equivalent to trusted system instructions can influence tool use.

### Decision

Mark attachment text as untrusted data, keep it at user-message priority, add explicit prompt instructions not to follow embedded directions, and rely on independent execution policy for final authorization.

### Consequences

- Basic prompt-injection resistance improves.
- Semantic prompt isolation is not guaranteed.
- Provider adapters should eventually represent data and instructions in separate structured channels where supported.
- Execution policy remains mandatory even if prompting improves.

---

## ADR-015 — Bounds and cleanup are part of the security model

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

A local service can still be exhausted by oversized uploads, histories, outputs, or pending authentication artifacts. Temporary context files can accumulate after cancellation or crashes.

### Decision

Apply explicit bounds to request messages, command size, provider context, uploads, extracted text, captured output, live UI output, ticket lifetime, and pending ticket count. Delete context uploads after use/removal and purge stale scratch files.

### Consequences

- Memory and disk use are more predictable.
- Truncation must be visible and tested.
- Limits may need tuning for large legitimate projects.
- Rich document/archive support requires format-specific anti-abuse controls.

---

## ADR-016 — Canonical root documentation and unreleased-first changelog

- **Status:** Accepted
- **Date:** 2026-10-01

### Context

Duplicate or inconsistently cased documentation names cause stale content and cross-platform Git problems, especially on Windows. The repository has no published stable tag.

### Decision

Use canonical cross-platform root names:

- `README.md`
- `ROADMAP.md`
- `ARCHITECTURE.md`
- `CHANGELOG.md`
- `DECISIONS.md`

Keep current work under `Unreleased` until a real tag is published. Existing secondary architecture paths should point to the canonical root document rather than duplicate it.

### Consequences

- GitHub and Windows checkouts have one authoritative file per document.
- Links are predictable and case-stable.
- Releases require an explicit changelog promotion step.
