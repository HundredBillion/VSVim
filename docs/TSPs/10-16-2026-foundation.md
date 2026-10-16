# VSVim Isolated Foundation Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:executing-plans to implement this TSP task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an independently runnable VSVim configuration with isolated state, reproducible plugin loading, and the existing svgtree and Sprite APIs.

**Architecture:** A small launcher chooses VSVim's application namespace before starting Neovim. A Lua entry point loads pinned plugins and user overrides. This is milestone 1a of the release PRD; it is a working editor foundation, not the finished batteries-included release.

**Tech Stack:** POSIX shell, Lua, Neovim 0.13 nightly, Git, lazy.nvim (plugin manager only), svgtree.nvim, sprite.nvim. Python 3 is a development test dependency only.

## Global constraints

- Support macOS and Linux.
- Snacks is not a VSVim dependency.
- Preserve an existing Neovim configuration and separate VSVim configuration, state, and plugin data.
- Retain Neovim modes and leader mappings.
- Every essential action has a terminal-safe mapping.
- The reviewer is LLM-agnostic from its first release; this task adds no reviewer or provider defaults.
- Do not modify sibling plugin repositories in this TSP.
- Do not count this foundation as completion of the full release PRD.

## Scope and delivery order

This TSP implements isolated launch, pinned plugin installation, explorer access,
basic editing defaults, user overrides, and an installation guide. It deliberately
does not install the existing Snacks-dependent SCM panel. Milestone 1b must
replace that renderer before SCM is bundled; that is required release work, not
a dropped feature. Search/completion/language tooling, native Sprite editor
launching, and visual matching get focused follow-on plans. No fake commands for
unimplemented follow or review features are exposed.

## Source and runtime evidence

Inspected on 2026-10-16:

| Decision | Evidence and compatibility |
| --- | --- |
| Namespace with `NVIM_APPNAME=vsvim` | Installed Neovim 0.12.2 help, `share/nvim/runtime/doc/starting.txt`, NVIM_APPNAME section, documents separate standard directories. Public reference: https://neovim.io/doc/user/starting/#%24NVIM_APPNAME. VSVim runtime acceptance targets 0.13 nightly. |
| Bootstrap lazy.nvim | Official installation: https://lazy.folke.io/installation. Use its documented runtime-path and setup pattern, but pin the manager and fail clearly instead of accepting partial bootstrap. |
| Plugin commits and configuration | https://lazy.folke.io/spec and https://lazy.folke.io/configuration. Remote stable tag resolved to `332b4cbc8bf61589b6ff58ce42fca80173154669`. |
| svgtree | Local clean checkout `13567cc93a71a49eedcf5b82b68fda93874b286e`; existing `setup`, `SvgTreeToggle`, and native mapping configuration. Verify the commit is fetchable from its remote during installation. |
| sprite.nvim | Local clean checkout `05adda83c090da78f4faf30bdae3b678990d2b0e`; existing Lua API and separate `bin/sprite-nvim` executable. Loading the plugin alone does not activate its native grid adapter. |

The original Homebrew Neovim 0.12.2 binary failed because it referenced
Tree-sitter 0.26 while Homebrew linked 0.27. On 2026-10-16, upgrading Neovim
through Homebrew installed 0.12.6 linked against Tree-sitter 0.27. Both
`nvim --version` and a clean headless Lua Tree-sitter parse now pass. No ABI
symlink workaround was used. The foundation's proposed Lua code still requires
its own implementation checks.

The svgtree remote was fetched on the same date: tag `v2.0.0` and remote master
both resolve to the pinned `13567cc93a71a49eedcf5b82b68fda93874b286e`. The local
checkout and installed Neovim plugin match that revision. Its full image-capable
test suite requires Neovim 0.13 nightly; stable Neovim uses supported fallbacks.

## Files and interfaces

| File | Responsibility |
| --- | --- |
| `bin/vsvim` | Start Neovim with VSVim's init and namespace; forward arguments and exit status. |
| `init.lua` | Validate runtime, add distro runtime path, invoke setup. |
| `lua/vsvim/init.lua` | Bootstrap pinned manager, configure plugins/defaults, load external user overrides. |
| `tests/launcher_test.py` | Verify launch isolation and argument fidelity using a fake executable. |
| `tests/smoke.lua` | Verify a real installed editor's identity, plugins, mappings, and override behavior. |
| `README.md` | Explain clone-and-run setup, prerequisites, customization, and current limits. |

Runtime selection: `VSVIM_NVIM` is an optional executable path; default
`nvim-nightly`. Never fall back silently to stable Neovim.

Runtime variables: `VSVIM_ROOT` is set by the launcher to the checkout root;
`NVIM_APPNAME` is set to `vsvim`. Neither replaces HOME or XDG base directories.
User configuration is `stdpath('config') .. '/user.lua'`. Plugin data and the
manager lockfile live beneath VSVim's data directory, not the working project.

### Task 1: Isolated launcher

**Blocked by:** None.

**Files:** Create `bin/vsvim`, `tests/launcher_test.py`.

**Interfaces:** Consumes `VSVIM_NVIM` or `nvim-nightly` on PATH and arbitrary Neovim arguments. Produces
a child process with `NVIM_APPNAME=vsvim`, absolute `VSVIM_ROOT`, and an explicit
VSVim init path. Preserves the working directory and exit status.

- [ ] Create `tests/launcher_test.py`:

```python
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class LauncherTest(unittest.TestCase):
    def test_isolation_arguments_and_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / 'nvim-nightly'
            executable.write_text('''#!/usr/bin/env python3
import json, os, sys
print(json.dumps({'args': sys.argv[1:], 'app': os.environ['NVIM_APPNAME'],
                 'root': os.environ['VSVIM_ROOT'], 'cwd': os.getcwd(),
                 'home': os.environ['HOME']}))
sys.exit(23)
''')
            executable.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       NVIM_APPNAME='existing-app', VSVIM_NVIM=str(executable))
            result = subprocess.run(
                ['sh', str(ROOT / 'bin/vsvim'), 'file with spaces.lua', '+set number'],
                env=env, cwd=root, text=True, capture_output=True)
            self.assertEqual(result.returncode, 23, result.stderr)
            record = json.loads(result.stdout)
            self.assertEqual(record['app'], 'vsvim')
            self.assertEqual(Path(record['root']), ROOT)
            self.assertEqual(record['args'], ['-u', str(ROOT / 'init.lua'),
                                            'file with spaces.lua', '+set number'])
            self.assertEqual(Path(record['cwd']).resolve(), root.resolve())
            self.assertEqual(record['home'], os.environ['HOME'])

if __name__ == '__main__':
    unittest.main()
```

- [ ] Run `python3 tests/launcher_test.py`; confirm failure because the launcher is absent.
- [ ] Create `bin/vsvim`:

```sh
#!/bin/sh
set -eu
self=$0
case "$self" in
  /*) ;;
  */*) self="$PWD/$self" ;;
  *) self=$(command -v "$self") ;;
esac
while [ -L "$self" ]; do
  link=$(readlink "$self")
  case "$link" in
    /*) self=$link ;;
    *) self="$(dirname "$self")/$link" ;;
  esac
done
VSVIM_ROOT=$(CDPATH= cd -- "$(dirname "$self")/.." && pwd -P)
export VSVIM_ROOT
export NVIM_APPNAME=vsvim
exec "${VSVIM_NVIM:-nvim-nightly}" -u "$VSVIM_ROOT/init.lua" "$@"
```

- [ ] Run `chmod +x bin/vsvim`, then `python3 tests/launcher_test.py` and `sh -n bin/vsvim`; expect one passing test and no shell syntax error.
- [ ] Commit those two files as `feat: add isolated VSVim launcher`.

### Task 2: Pinned editor and explorer startup

**Blocked by:** Task 1 and a working Neovim executable.

**Files:** Create `init.lua`, `lua/vsvim/init.lua`, `tests/smoke.lua`.

**Interfaces:** Consumes `VSVIM_ROOT`, `NVIM_APPNAME`, Git, and Neovim 0.13 nightly.
Produces `require('vsvim').setup()`, configured svgtree, leader-e and Ctrl-b
explorer mappings, and a post-defaults `user.lua` customization point.

- [ ] Create `tests/smoke.lua`:

```lua
assert(vim.env.NVIM_APPNAME == 'vsvim')
assert(vim.fn.stdpath('data'):match('/vsvim$'))
assert(vim.fn.stdpath('state'):match('/vsvim$'))
assert(vim.g.mapleader == ' ')
assert(vim.fn.exists(':SvgTreeToggle') == 2)
assert(type(require('sprite').available) == 'function')
assert(vim.fn.maparg('<leader>e', 'n') ~= '')
assert(vim.fn.maparg('<C-b>', 'n') ~= '')
assert(not package.loaded.snacks)
assert(vim.g.vsvim_override_loaded == true)
assert(vim.o.shiftwidth == 4)
print('VSVim smoke passed')
```

- [ ] In a temporary XDG environment, run the smoke command below before implementation; verify nonzero exit or missing expected marker rather than trusting headless startup alone.
- [ ] Create `init.lua`:

```lua
local version = vim.version()
if version.major == 0 and version.minor < 13 then
  error('VSVim requires Neovim 0.13 nightly; set VSVIM_NVIM to its executable')
end
if not (vim.ui and vim.ui.img) then
  error('VSVim requires a nightly build with vim.ui.img for SVGTree')
end
local root = assert(vim.env.VSVIM_ROOT, 'Start VSVim with bin/vsvim')
vim.opt.runtimepath:prepend(root)
require('vsvim').setup()
```

- [ ] Create `lua/vsvim/init.lua`:

```lua
local M = {}

function M.setup()
  vim.g.mapleader = ' '
  vim.g.maplocalleader = '\\'
  vim.opt.number = true
  vim.opt.termguicolors = true
  vim.opt.mouse = 'a'
  vim.opt.expandtab = true
  vim.opt.shiftwidth = 2
  vim.opt.tabstop = 2
  vim.opt.ignorecase = true
  vim.opt.smartcase = true
  local data = vim.fn.stdpath('data')
  local manager = data .. '/lazy/lazy.nvim'
  if not vim.uv.fs_stat(manager) then
    vim.fn.mkdir(data .. '/lazy', 'p')
    local pending = manager .. '.install-' .. vim.fn.getpid()
    local function run(args)
      local result = vim.system(args, { text = true }):wait()
      if result.code ~= 0 then
        vim.fn.delete(pending, 'rf')
        error('VSVim plugin bootstrap failed: ' .. (result.stderr or ''))
      end
    end
    run({ 'git', 'clone', '--filter=blob:none',
      'https://github.com/folke/lazy.nvim.git', pending })
    run({ 'git', '-C', pending, 'checkout', '--detach',
      '332b4cbc8bf61589b6ff58ce42fca80173154669' })
    local ok, err = vim.uv.fs_rename(pending, manager)
    if not ok then
      vim.fn.delete(pending, 'rf')
      if not vim.uv.fs_stat(manager .. '/lua/lazy/init.lua') then
        error('VSVim plugin bootstrap failed: ' .. tostring(err))
      end
    end
  end
  vim.opt.runtimepath:prepend(manager)
  require('lazy').setup({
    {
      'HundredBillion/sprite.nvim',
      commit = '05adda83c090da78f4faf30bdae3b678990d2b0e',
      lazy = false,
    },
    {
      'HundredBillion/svgtree.nvim',
      commit = '13567cc93a71a49eedcf5b82b68fda93874b286e',
      lazy = false,
      dependencies = { 'HundredBillion/sprite.nvim' },
      opts = { native = { mappings = {
        ['<Space>e'] = 'close', ['<C-b>'] = 'close',
      } } },
    },
  }, {
    root = data .. '/lazy',
    lockfile = data .. '/lazy-lock.json',
    checker = { enabled = false },
    change_detection = { enabled = false },
  })
  vim.keymap.set('n', '<leader>e', '<cmd>SvgTreeToggle<cr>', { desc = 'Explorer' })
  vim.keymap.set('n', '<C-b>', '<cmd>SvgTreeToggle<cr>', { desc = 'Explorer' })
  local user = vim.fn.stdpath('config') .. '/user.lua'
  if vim.uv.fs_stat(user) then
    dofile(user)
  end
end

return M
```

- [ ] Run the following isolated real-editor check. On the first run plugin install requires network; subsequent startup must use the installed copies. Inspect both exit status and the success marker.

```sh
test_root=$(mktemp -d)
mkdir -p "$test_root/config/vsvim"
cat > "$test_root/config/vsvim/user.lua" <<'LUA'
vim.g.vsvim_override_loaded = true
vim.opt.shiftwidth = 4
LUA
export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_STATE_HOME="$test_root/state"
export XDG_CACHE_HOME="$test_root/cache"
./bin/vsvim --headless '+Lazy! sync' +qa
./bin/vsvim --headless '+lua local ok,e=pcall(dofile,"tests/smoke.lua"); if not ok then print(e); vim.cmd("cquit 1") end' +qa
```

Expected: plugin installation completes, then `VSVim smoke passed` with exit 0.
Run from a disposable shell so XDG variables do not affect later commands.

- [ ] In the same test environment, run with Git unavailable on PATH but Neovim available after installation; startup must not require a bootstrap fetch. On a fresh data directory with Git unavailable, expect the explicit bootstrap failure and no accepted partial manager directory.
- [ ] Open an interactive terminal and use `<Space>e` and Ctrl-b to open/close the explorer. Check normal file editing and ensure startup does not replace the user's real configuration.
- [ ] Commit as `feat: bootstrap pinned editor plugins and explorer` after the checks pass. If a pinned plugin commit is not remotely available, report the exact missing commit and resolve that dependency rather than substituting an unpinned branch.

### Task 3: Installation and milestone evidence

**Blocked by:** Tasks 1–2.

**Files:** Create `README.md`.

**Interfaces:** Documents the launcher and customization point delivered above;
introduces no additional runtime interface.

- [ ] Create `README.md` with this content:

```markdown
# VSVim

An independent Neovim distribution for reading and reviewing agent-written code.

This development milestone provides isolated startup and the svgtree explorer.
PR review, agent following, and the reviewer conversation are not implemented yet.

## Run from a checkout

Install Neovim 0.13 nightly and Git, then run `./bin/vsvim` from this checkout.
The launcher uses `nvim-nightly`; set `VSVIM_NVIM` to an alternate nightly executable.
The first launch downloads pinned plugins. Later launches reuse them.
The launcher can also be placed on PATH through a symlink to `bin/vsvim`.

VSVim uses the `vsvim` Neovim application namespace and leaves the ordinary
`nvim` configuration in place. Run `:echo stdpath('config')` to find VSVim's
configuration directory. Create `user.lua` there for settings loaded after defaults.

## Controls

Use normal Neovim editing modes. Space is the leader. Press Space then e,
or Ctrl-b, to toggle the explorer. `:SvgTreeToggle` is also available.

## Sprite

The Sprite plugin API is bundled, and svgtree chooses its native explorer when
the host supports it. This milestone does not yet launch Neovim through Sprite's
native grid adapter or implement the complete VS Code visual design.

## Development checks

Run `python3 tests/launcher_test.py` for launcher checks. The foundation technical
spec documents the isolated real-Neovim smoke test. A working Neovim binary is
required; a dynamic-library loader failure happens before VSVim can start.
```

- [ ] Run `python3 tests/launcher_test.py`, `sh -n bin/vsvim`, and `git diff --check`. Repeat the smoke test with the minimum supported Neovim and on Linux before claiming cross-platform runtime validation.
- [ ] Record actual platform/runtime versions and outcomes in the execution log. Mark unrun checks explicitly; do not treat the broken system runtime as a passed check.
- [ ] Commit as `docs: document isolated VSVim foundation`.

## Self-review and hardening

- PRD coverage: this slice covers installation isolation, explorer integration,
  starter hybrid controls, reproducibility, and user overrides. Milestone 1b
  retains SCM migration and the rest of the editing defaults. Milestones 2–6
  retain every review, provider, hosting, and visual requirement.
- Reviewed the bootstrap's interrupted-install behavior: install into a temporary
  sibling directory; only promote after checkout succeeds. Preserve stderr.
- Checked existing svgtree config and Sprite launcher source; do not confuse
  plugin API availability with native grid launching.
- Do not use tests that merely mirror table definitions. The launcher test
  observes actual process arguments and namespace; the smoke test exercises
  the installed plugins and the user override point.
- Proposed code in this document has not been executed. Execution must validate
  the runtime and pinned dependencies before treating it as production-ready.

## Execution handoff

Proceed inline with executing-plans. The user has already approved the product
and architecture and asked to advance; do not reopen the execution-style choice.
The first task uses a fake executable for process-level checks. The installed
Neovim 0.13 nightly runtime is available for Task 2; repaired Homebrew stable
is not the VSVim runtime.
