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

The Homebrew Neovim 0.12.2 executable fails in the dynamic loader due to a missing
Tree-sitter 0.26 dylib; the local Tree-sitter directory is 0.27.1. Planning and
shell-level tests can continue. Real Neovim checks require a repaired or isolated
runtime; no plugin can fix a failure that occurs before Neovim starts.
