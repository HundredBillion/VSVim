# Sprite pane-address compatibility

Restore native editor and sidebar operation with Sprite Terminal 0.6.0+.
Sprite owns the protocol. Consumers pass the complete SPRITE_PANE string,
including its window identity, unchanged. Surface IDs remain numeric.

The installed sprite.nvim predates the fix already merged in upstream
75ec417 and documented in d1cb10e. Reuse that fix. Do not add numeric-pane
compatibility or modify Sprite. SVGTree and SCM already delegate connection
ownership to sprite.nvim; verify that boundary through the actual plugin API.

Acceptance:
- Native grid launch, discovery, dock open, and focus preserve pane addresses.
- SVGTree sends SVG assets and icon-bearing rows through the real plugin API.
- SCM sends repository/file rows and can close and reopen its native dock.
- Host refusal still yields the terminal fallback, and a subsequent native open works.
- VSVim launcher, minimap, Markdown and Follow test hosts use addressed panes.
- CI dependencies and usage guidance identify the compatible adapter.
- Push review branches/PRs for all four repositories and update the installed
  adapter to the existing upstream fix without interrupting the user's editor.

Design choices: keep protocol ownership in sprite.nvim; duplicating parsers in
consumers would create drift. A shared test host exercises socket traffic;
stubbing sprite.open would miss the reported failure. Older Sprite versions
are outside this compatibility target. Routine review gates are pre-approved
by the user's workspace instructions; no new architecture decision is needed.
