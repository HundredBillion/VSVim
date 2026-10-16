# VSVim review workspace

VSVim helps developers read and review proposed code changes while coding
agents work. These terms distinguish the code being reviewed from agent
activity and review decisions.

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
