# Automatic project-aware language servers

## Problem statement

Opening a supported project should provide working language features without
requiring developers to select servers, install compatible server releases,
repair environment variables, or dismiss repeated setup notifications.

VSVim currently installs global Mason server packages and starts them without a
consistent check of the project's environment. In Argon, the Mason Ruby LSP
executable selects Homebrew Ruby 4.0.7 even though the project requires and has
Ruby 2.7.5 installed. Six startup failures were recorded on October 19. Selecting
Ruby 2.7.5 alone is insufficient: the installed Ruby LSP requires Ruby 3.0 or
newer. Compatibility requires choosing the server as well as its runtime.

The user approved coverage of Ruby, Python, TypeScript/JavaScript, Rust, Go, and
Lua, with background setup, isolated environments, cached tooling, bounded
recovery, and inspectable failures that do not block editing.

## Solution

VSVim resolves the environment for the project containing the opened file,
selects compatible language tooling, installs missing server components into
its managed storage, and attaches automatically. Existing explicit project and
user settings take precedence over inferred defaults.

Setup runs asynchronously. Developers can keep editing while tooling installs
or indexes. A language status command exposes the selected project, runtime,
server, setup state, and any failure, with a path to its log. Background setup
and recovery do not display modal messages or require Enter to continue.

## User stories

1. As a developer, I want opening a supported source file to start its language
   features automatically.
2. As a developer maintaining older projects, I want compatible tooling selected
   without upgrading my application or changing its dependencies.
3. As a developer switching projects, I want each project to retain its own
   runtime and server environment.
4. As a Python developer, I want imports and diagnostics to use my project's
   interpreter and virtual environment.
5. As a TypeScript or JavaScript developer, I want analysis to use my project's
   TypeScript SDK when present and an appropriate Node runtime for the server.
6. As a Rust developer, I want the server and source components to work with my
   selected Rust toolchain.
7. As a Go developer, I want analysis to respect workspace, module, and toolchain
   requirements.
8. As a Lua developer, I want analysis to respect my Lua configuration without
   injecting Neovim globals into unrelated applications.
9. As a Neovim configuration author, I want LuaJIT and Neovim API definitions
   available automatically.
10. As a developer, I want successful installations reused on subsequent opens.
11. As a developer with multiple files open, I want concurrent requests to share
    an installation rather than start duplicate downloads.
12. As a developer working offline, I want cached working tooling retained and
    unavailable features explained without interrupting editing.
13. As a developer, I want bounded recovery from transient failures without
    repeated startup attempts for a known incompatible configuration.
14. As a developer, I want runtime or configuration changes to trigger a fresh
    resolution without restarting the editor.
15. As a developer, I want to inspect language setup status and retry explicitly
    when necessary, without needing these commands in the normal workflow.

## Behavioral requirements

| Language | Project context | Result |
| --- | --- | --- |
| Ruby | Version declarations and selected installed runtime | Compatible Ruby server under that runtime; a verified legacy fallback for Ruby 2.7.5 |
| Python | Explicit analysis settings, project virtual environment, Python version | Pyright configured for the correct interpreter, imports, and language target |
| TypeScript / JavaScript | Node requirements, project settings, installed TypeScript SDK | Compatible language-server host and project SDK, with a managed fallback for standalone files |
| Rust | Explicit toolchain selection, rust-toolchain files, Cargo workspace | Compatible rust-analyzer and required source components under the selected toolchain |
| Go | go.work, go.mod, toolchain directives, selected Go executable | Compatible gopls configured for the project workspace and toolchain |
| Lua | Explicit LuaLS configuration and project type | Correct Lua target; LuaJIT and Neovim APIs only for Neovim configuration projects |

The version of the server's host runtime and the language version being
analyzed are distinct. VSVim must not assume they have identical versions.
Compatibility decisions use declared package requirements and verified server
behavior, rather than selecting an arbitrary latest release.

## Implementation decisions

- Extend the existing language-server setup through one lifecycle boundary for
  resolution, provisioning, attachment, status, and recovery. Keep language
  detection and configuration rules specific to each ecosystem.
- Reuse the installed Neovim LSP client and Mason facilities where compatible.
  Replace automatic launch paths that bypass project resolution.
- Resolve environments per project root and language. Avoid process-wide PATH,
  GEM_HOME, virtual-environment, or toolchain mutations to switch projects.
- Prefer explicit configuration, then the project's selected environment, then
  compatible installed tooling and managed server packages. Do not silently use
  an incompatible global runtime when a project requirement is unmet.
- Keep server dependencies in managed storage. Do not edit project manifests,
  lockfiles, or install application dependencies to provision editor tooling.
- Reuse successful installations by effective runtime, server version, and
  platform. Deduplicate concurrent installations and retain a working cached
  installation if replacement setup fails.
- Track resolving, installing, starting, ready, and unavailable states. A
  missing runtime is unavailable, with the reason recorded in status and logs.
- Bound subprocess execution and retries. Permit at most one automatic recovery
  attempt per unchanged environment after failure; explicit retry or a relevant
  configuration change permits a new attempt.
- Ignore stale asynchronous results when a buffer, project, or environment has
  changed. Do not attach an old project's server to a newly selected project.
- Route failures from managed setup and startup into language status and logs.
  Preserve useful diagnostics about source code and explicit user commands.
- Headless startup does not download tooling merely by loading VSVim. Explicit
  provisioning and integration checks remain available.

## Testing decisions

Test externally visible behavior through the existing LSP setup lifecycle and
real-server cross-file navigation checks. Use deterministic local substitutes
for runtime discovery, installer failures, concurrent requests, and retries;
assert selected commands, environments, attachment, and user-visible behavior.

Required checks:

- Reproduce Argon's Ruby 2.7.5 mismatch before the fix, then verify a compatible
  server initializes and resolves a definition under that runtime.
- Check actual server initialization and cross-file definitions for all six
  language families, including JavaScript alongside TypeScript.
- Exercise conflicting requirements in two projects within one editor session.
- Verify Python virtual-environment imports, project TypeScript SDK selection,
  Rust toolchain selection, Go workspace/toolchain selection, and Lua targets.
- Verify explicit settings override automatic inference.
- Verify cached reuse and a single install for simultaneous buffer opens.
- Simulate unavailable runtimes, offline downloads, installer failures,
  server exits, deleted project directories, and stale asynchronous callbacks.
- Assert failures leave editing responsive and do not enter a blocking message
  prompt, suppress unrelated editor errors, or retry indefinitely.
- Assert provisioning leaves project manifests and lockfiles unchanged.

## Out of scope

- Installing or upgrading application language runtimes, package managers, and
  application dependencies.
- Supporting additional language families or every historical runtime release.
  Unsupported combinations must be reported quietly and accurately.
- Fixing the separately observed syntax-highlighting CPU bottleneck or native
  host crashes as part of language-server compatibility work.
- Publishing a new VSVim release or restarting the user's live editor without a
  separately verified implementation.

## Evidence and compatibility sources

- Local LSP log: six RubyVersionMismatch traces on October 19; the exact
  composed-bundle check exits 18 under Homebrew Ruby 4.0.7 for Argon.
- Ruby LSP 0.26.11 requires Ruby >= 3.0:
  https://rubygems.org/gems/ruby-lsp/versions/0.26.11
- Solargraph 0.52.0 declares Ruby >= 2.6; its complete dependency resolution and
  Ruby 2.7.5 behavior require integration verification before it is selected:
  https://rubygems.org/gems/solargraph/versions/0.52.0
- Pyright environment and language-target configuration:
  https://github.com/microsoft/pyright/blob/main/docs/configuration.md
- TypeScript server SDK selection:
  https://github.com/typescript-language-server/typescript-language-server
- Rust analyzer installation and toolchains:
  https://rust-analyzer.github.io/book/installation.html
- Go toolchain selection:
  https://go.dev/doc/toolchain
- LuaLS runtime settings:
  https://luals.github.io/wiki/settings/
