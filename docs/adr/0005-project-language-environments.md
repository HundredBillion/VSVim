# 0005: Project language environments own server setup

Status: Accepted

## Context

Argon requires installed Ruby 2.7.5, but the previous global Mason executable
selected Homebrew Ruby 4.0.7. Selecting Ruby 2.7 alone also fails for modern Ruby
LSP. Compatibility therefore includes the server release and its host runtime.

## Decision

The project lifecycle resolves, provisions, starts, observes and retries servers.
Ecosystem resolvers select runtimes and settings; explicit user configurations
take precedence. Managed dependencies remain outside application bundles.
Ruby 2.7 uses Solargraph 0.52.0; modern Ruby uses Ruby LSP 0.26.11.
The manager owns asynchronous generations, shared setup, bounded subprocesses,
one startup recovery attempt, status and project logs. Headless loading does
not provision without an explicit request. Managed protocol showMessage and
showMessageRequest handlers log messages and decline prompts; explicit handlers
and publishDiagnostics retain their normal behavior.

## Consequences

No runtime or application dependencies are installed. Unsupported combinations
remain unavailable with inspectable reasons. Successful installations are reused.
Rust source and analyzer components use rustup for an already installed toolchain.
Real integration exposed rust-analyzer creating Cargo.lock during discovery.
Defaults now use locked/offline Cargo arguments; projects without Cargo.lock
use cargo.noDeps for metadata discovery. Existing lockfiles retain dependency
discovery, and build-script support remains enabled. Definitions work in a dependency-free crate without a lockfile; missing
dependencies may require project preparation or explicit
configuration. These limits are preferable to silently editing project files.
The rendering CPU bottleneck and historical native crashes are separate issues.

## Evidence

Real checks exercise initialization, definition navigation and unchanged
manifests for Lua, Python, Ruby 2.7.5/3.3.5, Go, Rust, TypeScript and JavaScript.
Python resolves a module available only in the fixture virtual environment;
TypeScript selects a project SDK; Go selects a workspace and installed toolchain;
Rust honors rust-toolchain.toml. Deterministic lifecycle tests cover failure and
recovery without requiring network installations.

Sources: [Ruby LSP requirements](https://rubygems.org/gems/ruby-lsp/versions/0.26.11),
[Solargraph requirements](https://rubygems.org/gems/solargraph/versions/0.52.0),
[Pyright environments](https://github.com/microsoft/pyright/blob/main/docs/configuration.md),
[TypeScript SDK selection](https://github.com/typescript-language-server/typescript-language-server),
[rust-analyzer configuration](https://rust-analyzer.github.io/book/configuration),
[Go toolchains](https://go.dev/doc/toolchain),
[LuaLS settings](https://luals.github.io/wiki/settings/).
