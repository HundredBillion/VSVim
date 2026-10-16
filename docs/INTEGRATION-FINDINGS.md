# Integration findings

Inspected 2026-10-16. These findings inform focused implementation plans; they
do not claim completed integrations.

## Codex follow

Installed CLI: `codex-cli 0.142.5`. `codex app-server --help` exposes stdio,
Unix-socket, and WebSocket transports and protocol schema generation.

The [official app-server documentation](https://learn.chatgpt.com/docs/app-server)
describes fileChange items containing paths and diffs, item lifecycle events,
and turn diff updates. It distinguishes reading stored threads from resuming
and subscribing to them. These are promising inputs for a follow adapter but
do not prove that an arbitrary independently running CLI session can be observed
live without changing its ownership.

Before planning the follow implementation, generate the installed CLI's schema
into a temporary directory and exercise two clients against a disposable session.
Verify event visibility, whether attach affects the coding session, reconnect
behavior, and changes made through shell commands rather than structured file
tools. Do not read unrelated user conversations or start paid model work merely
to inspect protocol metadata. A successful app-server launch alone is insufficient.

## Reviewer providers

The reviewer is provider-neutral at initial release. No provider is selected by
these findings. Its plan must validate multiple backends against identical
explanation, proposal, and approval behavior. A coding-agent transport is not
automatically a safe reviewer backend: tools must not write the project before
developer approval, regardless of the provider's default agent permissions.

## Local runtime

The original Homebrew Neovim 0.12.2 executable failed in the dynamic loader:
it referenced Tree-sitter 0.26 while the linked library was 0.27.1. On
2026-10-16, `brew upgrade neovim` installed Neovim 0.12.6 and its dependencies.
The new binary links against Tree-sitter 0.27; version output and a clean
headless Lua parse both pass. The existing local Neovim wrapper remains intact.

## SVGTree version

Fetched `HundredBillion/svgtree.nvim` on 2026-10-16. Remote master and tag
`v2.0.0` resolve to `13567cc93a71a49eedcf5b82b68fda93874b286e`, matching the
project checkout, installed plugin, existing user lockfile, and VSVim plan.
No plugin update or local source modification was necessary.

Verification: `SVGTREE_API_CHECKOUT=/Users/davidlee/Projects/sprite.nvim bash
scripts/test.sh` passed the complete headless suite using installed Neovim
0.13.0-dev-761+g0639f6e41a. The terminal-session check also passed separately
with repaired Homebrew Neovim 0.12.6. These are automated behavior checks,
not a claim of fresh screenshot-based visual acceptance.
