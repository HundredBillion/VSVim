# VSVim review workspace

VSVim helps developers read and review proposed code changes while coding
agents work. These terms distinguish the code being reviewed from agent
activity and review decisions.

## Markdown documents

**Markdown source**:
The editable Markdown text of an open document, including unsaved changes.
_Avoid_: Code mode when referring to the document's text

**Markdown preview**:
The rendered, read-only presentation of the same open document.
_Avoid_: Preview buffer, rendered file

## Language

**Target branch**:
The branch into which the proposed change would merge. An existing PR's target
takes precedence over the repository's default branch.
_Avoid_: Default branch when referring to an arbitrary PR target

**Review baseline**:
The current merge-base revision from which the proposed code changes are compared;
it updates automatically when relevant branch state changes.
_Avoid_: Last agent edit, session starting point

**Local review**:
A review of the proposed code including local changes that may not yet be
published on the Git host.

**Published review**:
A review of the PR revision available on the Git host.

**Coding agent**:
The selected agent session producing changes to the project.
_Avoid_: Reviewer when referring to the implementation session

**Reviewer conversation**:
A separate, on-demand LLM conversation for understanding code and proposing
changes, initiated by developer review requests or questions. Its provider is
chosen independently of the coding agent.
_Avoid_: Coding session

**Reviewer provider**:
The developer-selected backend that supplies the reviewer model, independently
of the agent producing project changes.
_Avoid_: Coding agent when referring to the reviewer backend

**Proposal**:
A set of file additions, edits, or deletions presented for developer approval
before application.
_Avoid_: Applied fix when a proposal is still pending

**Hunk approval**:
The developer's permission to apply a selected portion of a proposed text
change, without approving the proposal's remaining changes.
_Avoid_: Proposal approval when only one hunk was approved

**Following**:
Navigation that tracks the selected coding agent's current known location.

**Paused following**:
A reading state in which agent activity continues to be tracked without
agent-driven navigation. The comparison continues to hot reload while the
developer's reading position is preserved where possible.
_Avoid_: Paused agent, frozen comparison

**Outdated comment**:
A comment whose referenced code has changed and whose continued relevance
needs assessment; it is not evidence that the concern was addressed.
_Avoid_: Resolved comment

**Resolved comment**:
A comment whose concern has explicitly been marked addressed.
_Avoid_: Outdated comment

**Publication**:
Sending a review comment or reply to the Git host through a developer action.
_Avoid_: Application when referring to sending a comment

**Application**:
Making an approved proposal's changes to local working files.
_Avoid_: Publication when referring to changing local code


## Minimap language

**Minimap**:
A miniature view of source code showing file structure, changes, occurrences,
and selection alongside the main editor.
_Avoid_: Overview ruler when referring to the miniature code itself

**File-change baseline**:
The file revision against which the minimap displays current in-memory edits.
It is distinct from the merge-base review baseline.
_Avoid_: Review baseline when referring to the minimap comparison

**Viewing rectangle**:
The outlined minimap region corresponding to source lines currently visible in
the target editor.
_Avoid_: Selected section when referring to the visible viewport

**Selected section**:
The blue minimap region corresponding to rows containing selected text.
_Avoid_: Viewing rectangle when referring to selected text

**Occurrence box**:
A grey minimap region marking a source row containing the selected whole word.
_Avoid_: Reference when no symbol relationship is implied

**Preserved selection**:
Selected text retained while minimap browsing moves the viewing position away
from it, and restored when keyboard editing resumes.
_Avoid_: Active selection when the editor is temporarily browsing elsewhere


**Minimap action acknowledgment**:
The latest processed connection-monotonic navigation ID echoed in minimap state
when host and provider negotiate `grid-minimap-ack-v1`. It acknowledges processed
input even when folds/clamping leave the actual viewport unchanged. It is
separate from source generation and state revision.
_Avoid_: viewport equality, paint completion, one acknowledgment per state


## Language tooling

**Project language environment**:
The resolved project root, runtime, language server and configuration used for
one project's language features. It does not mutate the editor's global PATH.

**Server host runtime**:
The runtime executing the language server, which can differ from the language
version or interpreter used to analyze the application.

**Managed tooling cache**:
VSVim-owned server dependencies, keyed by effective runtime and server release.
Application dependencies and runtime installation remain project responsibilities.

**Language setup state**:
Resolving, installing, starting, ready or unavailable, exposed by
`:VSVimLspStatus` together with the project log and failure reason.
