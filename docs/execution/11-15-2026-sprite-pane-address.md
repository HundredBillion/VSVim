# Sprite pane-address compatibility verification

## Acceptance evidence

| Requirement | Evidence |
| --- | --- |
| Preserve pane address on native launch, discovery, dock open and focus | Existing upstream adapter/session fix 75ec417; session_integration_spec exercises embedded launch; new dock_host_spec exercises real Session.current and socket requests, numeric Surface target, and wrong-window refusal. Adapter suite: 20,820 checks, zero failures. |
| SVGTree delivers SVG icons in native right dock | scripts/test-native-pane-address.lua verifies right dock, file row and referenced transmitted SVG asset through real plugin API. It fails with pre-fix session/adapter and passes with the fix. Full scripts/test.sh passes. |
| SCM delivers Git rows and reopens | tests/sprite_pane_address_test.lua opens a temporary Git repository and verifies native file rows, focus and reopening. It fails with pre-fix session/adapter and passes fixed. All 14 headless tests pass. |
| Refusal falls back and subsequent native open recovers | Both consumer tests explicitly refuse discovery, observe terminal buffers, clear refusal, and observe new native rows. |
| VSVim tests use full pane addresses | Launcher 2, minimap/protocol 8, Markdown 3, Follow 3 tests pass. Protocol check fails four cases against the old permissive fake host and passes the new host. |
| CI and usage guidance identify matching adapter | SVGTree and SCM pin 92b815273ab08f977fb07ccee719a554ebef2371; YAML parsed and pins checked. READMEs require Sprite 0.6.0+ and sprite.nvim v0.5.0+; runtime code already tracks main. |
| Push all four repositories | Open PRs: sprite.nvim #15, svgtree.nvim #31, scm.nvim #13, VSVim #25. |
| Update installed adapter without interrupting editor | Clean installed checkout fast-forwarded 7edbe16 to d1cb10e and VSVim lazy lock updated. Read-only live host probe changed from unavailable to eligible=true with svg-assets-v1 and owned-dock-v1. Restart VSVim to load the new adapter. |

Independent review identified that callback errors could leave test exit status
successful. The fixture now records only accepted messages, records async
validation errors, and asserts synchronously in messages() and after close()
cleanup. A malformed-message self-test proves rejection and assertion failure.
Focused independent re-review passed; consumer pins include the fix.

Sprite's production source was unchanged. Graphical painting was not inspected;
tests prove asset/row delivery and the live probe proves host eligibility.
Remote CI was running when these records were written. Python 3.14/pynvim emitted
transport ResourceWarnings in the passing Markdown suite.

The native VSVim profiles previously omitted required follow.nvim and attempted
a network install during startup. Copying the cached dependency into those
isolated profiles made their startup deterministic.
