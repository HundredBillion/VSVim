# Project-aware language servers Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:subagent-driven-development (recommended) or dmi-superpowers:executing-plans to implement this TSP task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opening a supported project automatically provisions and starts compatible language tooling without blocking setup notifications.

**Architecture:** Replace eager Mason auto-enablement with a project-scoped lifecycle module. Language profiles resolve the target environment separately from the server host and provision isolated server dependencies. Neovim remains the LSP client; Mason supplies compatible prebuilt packages where appropriate.

**Tech Stack:** Existing Neovim 0.13 nightly, Lua, vim.system, Mason, npm, RubyGems/Bundler, Go tools, rustup.

## Global constraints

- Source PRD: `docs/PRDs/10-19-2026-project-aware-lsp.md`, approved by the user.
- Cover Ruby, Python, TypeScript/JavaScript, Rust, Go, and Lua.
- Do not modify project manifests, lockfiles, dependencies, or process-wide runtime environment to switch projects.
- Installing or upgrading application language runtimes is out of scope. An unavailable required runtime becomes a quiet, inspectable failure.
- Background setup and recovery do not display modal messages or require Enter to continue.
- Permit at most one automatic recovery attempt per unchanged environment after failure; explicit retry or a relevant configuration change permits a new attempt.
- Headless startup does not download tooling merely by loading VSVim.
- Use asynchronous subprocesses with bounded timeouts; stale callbacks cannot attach to a different project or revive cancelled work.
- Explicit user/project settings override inferred defaults.
- Cache compatible installations and deduplicate simultaneous provisioning requests.
- Preserve definition navigation and mouse behavior in the existing LSP module.
- No publishing, merging, release installation, or restarting the live editor is authorized by this implementation plan.

## Grounded decisions

The existing `lua/vsvim/lsp.lua` is the single setup entry point. Its eager
Mason installation and automatic enablement currently bypass runtime selection.
Keep its navigation functions, replacing only setup ownership.

Installed Ruby LSP 0.26.11 requires Ruby >=3.0. The Mason wrapper has an absolute
Homebrew shebang. Use Ruby 2.7.5 with a verified Solargraph 0.52.0 fallback;
modern Ruby can use a compatible Ruby LSP bundle. Resolve complete transitive
dependencies under the selected Ruby, using a standalone managed Gemfile and
compatible Bundler when direct RubyGems installation cannot resolve old Ruby
dependencies. Launch isolated tools without running bundle install in the
application. Ruby LSP's application bundle composition must not mutate the
application or fail because of unavailable application dependencies; use the
documented standalone launch mode if needed, or a verified compatible fallback.

The installed TypeScript language server 6.0.2 requires Node >=22.22.2, whereas
4.3.4 requires Node >=18. Pyright 1.1.414 requires Node >=14. These requirements
were read from official npm version metadata. Shell Node has now been upgraded
to 26.12.0, but tests must still cover older project runtimes. Select the server
host separately from the TypeScript SDK or Python interpreter.

Prefer native toolchain selection for Rust and Go. Respect explicit Rust
toolchain overrides and project files. For Go, obtain the effective selected
toolchain in the project directory and choose compatible gopls; do not assume
the version used to build gopls equals the module's target version. For Lua,
respect LuaLS configuration and only inject Neovim library/runtime defaults for
Neovim configuration projects, including VSVim itself.

Primary sources: RubyGems version pages and npm version metadata in the PRD;
installed Neovim `runtime/doc/lsp.txt` for `vim.lsp.start`, `cmd_env`, `cmd_cwd`,
callbacks and per-buffer reuse; official language-server/toolchain docs linked
from the PRD. Confirm API behavior against the installed dependency before use.

## File structure

- Modify `lua/vsvim/lsp.lua`: retain navigation; delegate setup to the lifecycle.
- Create `lua/vsvim/lsp/manager.lua`: per-project state, provisioning ownership,
  callback cancellation, quiet transport startup, recovery, and status commands.
- Create `lua/vsvim/lsp/environment.lua`: asynchronous resolution and common
  runtime/file discovery helpers. Split ecosystem-specific implementation into
  focused sibling modules if needed; keep the caller interface below small.
- Create `tests/lsp_environment.lua` and `tests/lsp_lifecycle.lua`: behavior
  through resolution and lifecycle interfaces, with controlled process/installer
  adapters at external boundaries rather than mocks of implementation methods.
- Modify `tests/lsp_setup.lua`: updated entry-point lifecycle checks.
- Modify `tests/lsp_servers.lua`: actual automatic provisioning and navigation.
- Modify `tests/integration_test.py`: include new focused checks.
- Modify `README.md`: automatic selection, compatibility limits, status/retry.
- Update `CONTEXT.md` with project environment, server host, and language target
  terminology; add an ADR for isolated provisioning and quiet failure ownership.

### Task 1: Automatic project-scoped language setup

**Blocked by:** None

**Files:** `lua/vsvim/lsp.lua`, new `lua/vsvim/lsp/*.lua`,
`tests/lsp_environment.lua`, `tests/lsp_lifecycle.lua`, `tests/lsp_setup.lua`.

**Interfaces:**
- Consumes: installed Neovim LSP APIs and default server configs from pinned
  nvim-lspconfig; external runtime and installer processes.
- Produces: `require('vsvim.lsp.manager').setup()`;
  `ensure(bufnr, force)` to resolve/provision/attach, where force explicitly
  permits headless provisioning and resets the failure budget;
  `status()` returning project entries with root, language/server, state,
  runtime, reason, and log path. These are also the integration-test seam.
- Internal ecosystem seam: `environment.resolve(context, done)` with
  `context={root, server, bufnr, config, report}` and
  `done(plan, error_message)`. A plan contains the final `config` overrides
  (including executable argv and process environment) and a runtime description.
  Resolution includes provisioning missing managed tooling. Report callbacks
  expose resolving/installing state. `environment.fingerprint(root, server)`
  returns a stable identity from relevant configuration/environment/tool paths.
- User interface: `:VSVimLspStatus` opens an inspectable scratch buffer;
  `:VSVimInstallLsp` explicitly retries tooling for supported loaded buffers.
  Existing headless real-server tests can call `ensure(bufnr, true)`.

- [ ] **Step 1: Red/green the Lua tracer through the setup entry point.**
  Existing setup eagerly installs six packages on UIEnter. Replace that
  expectation with no download for an empty UI and automatic setup for an opened
  supported file. Start with these headless assertions and a controlled resolver:

```lua
local lsp = require('vsvim.lsp')
lsp.setup()
assert(#vim.api.nvim_list_uis() == 0)
assert(vim.fn.exists(':VSVimLspStatus') == 2)
assert(next(require('vsvim.lsp.manager').status()) == nil)
```

  Run `nvim-nightly --headless -u NONE --cmd 'set rtp^=.' -l tests/lsp_setup.lua`.
  Observe the missing status interface fail before implementing it. Then add
  lifecycle ownership and route setup to it. Keep unrelated navigation intact.

- [ ] **Step 2: Resolve/provision one ecosystem at a time, red/green.**
  Through `environment.resolve`, test and implement Ruby runtime resolution and
  legacy fallback; Python interpreter/virtualenv and Node host; TypeScript Node
  host and workspace SDK; Rust selected toolchain and sources; Go workspace and
  effective toolchain; Lua project-specific defaults. Assert process argv,
  project root, environment, and resulting settings. Use actual temporary
  project marker files and executable fixture processes at external seams.
  Preserve explicit config values. Test missing and conflicting runtime
  requirements. New installation paths must live under VSVim managed storage.

  Run each cycle with
  `nvim-nightly --headless -u NONE --cmd 'set rtp^=.' -l tests/lsp_environment.lua`.
  Add a failure per ecosystem before adding that ecosystem's behavior.

- [ ] **Step 3: Red/green asynchronous lifecycle failures.**
  Add cases for duplicate buffer opens, independent projects, changed version
  files, stale resolution callbacks, deleted directories, startup timeout,
  installer timeout/failure, offline cached reuse, server crashes, and explicit
  retry. Assert no background `vim.notify`/blocking prompt and at most two total
  automatic attempts per unchanged environment. A runtime mismatch is a
  preflight failure, not an endlessly restarted language server.

  Record real exit/error codes in status and a dedicated language log. Scope
  notification suppression to managed processes via their transport callbacks;
  do not globally replace `vim.notify` or suppress unrelated editor warnings.
  Guard attachment against the current buffer's name/root/filetype and each
  entry's generation. Reuse only clients with matching environment identity.

  Run `nvim-nightly --headless -u NONE --cmd 'set rtp^=.' -l tests/lsp_lifecycle.lua`.

- [ ] **Step 4: Run focused verification and commit.**

```sh
nvim-nightly --headless -u NONE --cmd 'set rtp^=.' -l tests/lsp_setup.lua
nvim-nightly --headless -u NONE --cmd 'set rtp^=.' -l tests/lsp_environment.lua
nvim-nightly --headless -u NONE --cmd 'set rtp^=.' -l tests/lsp_lifecycle.lua
git diff --check
git add lua/vsvim/lsp.lua lua/vsvim/lsp tests/lsp_setup.lua tests/lsp_environment.lua tests/lsp_lifecycle.lua
git commit -m 'fix: provision language servers for project environments'
```

  Record the actual failing/passing outputs and any compatibility limitations
  in the task report. Task review covers both spec compliance and code quality.

### Task 2: Real server proof and documentation

**Blocked by:** Task 1, including its clean task review.

**Files:** `tests/lsp_servers.lua`, `tests/integration_test.py`, `README.md`,
`CONTEXT.md`, `docs/adr/0005-project-language-environments.md`; production modules
only for fixes exposed by the real behavior checks.

**Interfaces:**
- Consumes: `manager.ensure(bufnr, true)` and `manager.status()` from Task 1.
- Produces: real-server verification for every bundled language family,
  updated integration runner and user documentation, durable audit findings.

- [ ] **Step 1: Exercise actual automatic setup and cross-file definitions.**
  Update existing real-server cases to call the lifecycle rather than manually
  enabling a global server. Do not install application gems into a Ruby test
  project; it should require no edits to application Gemfiles or lockfiles.
  Test server attachment and a definition jump through `vsvim.lsp.definition`.
  Check the Ruby 2.7.5 fallback in addition to a modern Ruby fixture.

```lua
local manager = require('vsvim.lsp.manager')
manager.ensure(vim.api.nvim_get_current_buf(), true)
assert(vim.wait(180000, function()
  return #vim.lsp.get_clients({bufnr=0}) > 0
end, 50), vim.inspect(manager.status()))
```

  Run `VSVIM_TEST_LANGUAGE=LANG ./bin/vsvim --headless
  '+lua dofile("tests/lsp_servers.lua")' '+qa!'` for `lua`, `ruby`, `python`,
  `go`, `rust`, `typescript`, `javascript`. Capture complete output and exit
  status in separate evidence files. Verify initialization, actual definition
  responses, and source/lockfile immutability; an attached process alone is not
  sufficient. Run the Argon mismatch reproduction before and verify legacy
  navigation using the selected installed Ruby 2.7.5 after the change.

- [ ] **Step 2: Integrate deterministic checks and document behavior.**
  Add the environment/lifecycle checks to the existing Python integration
  runner using its established isolated-plugin fixture. Document automatic
  selection, managed cache, headless rules, status and explicit retry, supported
  runtime limits, and separation of host runtime from language target. Remove
  obsolete Homebrew-Ruby and manual-bundle-install guidance.
  Add glossary definitions and record the provisioning/failure ownership ADR.

- [ ] **Step 3: Verify the branch and commit.**

```sh
python3 -m unittest discover -s tests -p '*test.py'
git diff --check
git add README.md CONTEXT.md docs/adr tests
git commit -m 'test: verify automatic language setup across bundled ecosystems'
```

  Inspect the full suite result; do not label skipped or unavailable runtime
  checks as passing. Run an independent whole-branch review and address
  substantive findings with covering tests before reporting completion.

## Review focus

Check the actual commands that launch servers, not only selected version
strings. Test project isolation, cache identity, bounded asynchronous failure,
runtime selection precedence, cancellation, and preservation of explicit
settings. Keep the native rendering CPU bottleneck and historical host crashes
separate from the LSP compatibility fix. No runtime upgrade may be silently
introduced as a substitute for compatible server selection.
