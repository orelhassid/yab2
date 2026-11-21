# Development projects in Yab2

Product proposal for review. The first version assumes one developer on a Mac, one local repository per development project, and Claude Code or Codex already connected through Yab.

## What opening a project should feel like

Choose Development in Yab’s Space Switcher and select Yab Browser in the sidebar. Overview tells you what changed since your last visit, which feature is in progress, and whether anyone needs your decision. The manager conversation is open on the left. Pick a different project and its own conversation, draft, and work appear.

For example, ask “Can we show download progress in the Dock?” The manager finds the existing Downloads feature and shows its current definition. Select **Discuss** to refine the behavior or **Build** to start the agreed task. Ask “What about canceled downloads?” while the agent works. That message goes to the same manager, attached to Downloads. The manager can steer the running task. When the change is ready, the message offers **Review changes**, which opens the relevant diff and checks on the right. Days later, opening Downloads still explains what was decided and what shipped.

## Inventory and checklist

Checked against the Mac source at `d641485`. Checked items have an implementation in the checkout. This inventory is a source review.

| Area | Already in Yab2 | Work to plan |
| --- | --- | --- |
| Projects | [Project records](../Sources/Fast/Services/Chat/Projects.swift), pins, archive, instructions, optional memory, project-owned files, and [command-field routes](../Sources/Fast/App/Commands/Chat/ChatProjectCommands.swift) | Link a local checkout to a project. Add the workspace entry, one stable manager chat, and per-project view state. |
| Shell | [YabDesign](../Sources/YabDesign/Design.swift), shared [buttons](../Sources/YabDesign/Buttons.swift), [resizable chat column](../Sources/Fast/Components/Chat/ChatColumn/ChatColumn.swift), native Home and browser tabs | Use the existing Space Switcher to enter Development. The outer sidebar lists projects. Each selected project occupies the tab content, with manager chat and tool tabs side by side. |
| Conversation | [Composer](../Sources/Fast/Components/Chat/ChatComposer/ChatComposer.swift), [stored chats](../Sources/Fast/Services/Chat/Chat.swift), [typed transcript items](../Sources/Fast/Services/Chat/ChatItem.swift), inline widgets, artifact cards, subagent reports | Replace the development project's [new-chat entry](../Sources/Fast/App/Screens/Chat/ChatProjectScreen.swift) with resume-manager. Add feature references, decisions, and actions that open the corresponding record on the right. |
| Execution | [Claude launch and session handling](../Sources/Fast/Agents.swift), [Codex app-server](../Sources/Fast/CodexServer.swift), parent/child sessions, steer, stop, and resume | Bind each run to a project, task, repo, and permission scope. Handle repeated Build requests, provider handoff, and recovery. |
| Models and tools | [Provider setup](../Sources/Fast/AgentPlans.swift), [model choices and effort](../Sources/Fast/ModelChoice.swift), [model compatibility checks](../Sources/Fast/AgentCatalog.swift), [Yab skills](../Sources/Fast/Skills.swift), MCP tools | Add project defaults, automatic selection with a short reason, and an inventory of the tools each runner can actually use. |
| Execution history | Tool calls, edits, plans, and subagent reports in the transcript. [Remote task records](../Sources/SyncKit/TaskRecords.swift) also exist for device-to-device execution. | Give product features and tasks their own identities, owners, states, and evidence. Derive Overview, Activity, and Changelog from the same changes. |
| Product and code | Project attachments, memory, and [artifact previews](../Sources/Fast/Components/Chat/ArtifactCard/ArtifactCard.swift) provide inputs | Build Roadmap, feature detail, canonical Spec, Pitch Deck, Design System, and repository tree/diff review. |

- [x] Reuse the existing project ID, visual identity, command field, and native design primitives.
- [x] Reuse the chat transcript, composer, provider launchers, model catalog, and run controls.
- [ ] Add the repository link, manager identity, project records, and recovery rules.
- [ ] Prove scoped editing, interruption, and review with each provider.
- [ ] Connect the project screens and chat to the same records and actions.

## Screens and components

Use a single compact header. The project icon and name align with seven tool tabs. Shared navigation owns project selection, active tool, keyboard focus, and narrow-window overflow. Each screen supplies the content below the strip. Roadmap, a document, and a code diff each open inside their destination, with Back restoring the previous selection and scroll. Keep the left conversation and its draft in place while navigating. At narrow widths, let the user switch between chat and the current tool, preserving both. Use the existing Yab palette, type, frames, buttons, focus treatment, and motion.

Illustrative Overview with a project already underway:

```text
 Development ▾  │ Project manager       │ Overview   Product   Tasks   Agents   Code   Preview   Terminal
                │ Yab Browser           │
 Projects       │                       │ Yab Browser
 › Yab Browser  │ Dock progress is      │ Needs your review
   Sunday       │ ready for review.     │   Dock progress on cancel     Review diff
   Webistory    │ [Review changes]      │
   Agada        │                       │ On the roadmap
                │                       │   Downloads           2 of 3 tasks done
                │                       │
                │ [Downloads ×]         │ Since your last visit
                │ Message manager…      │   Dock progress           Checks passed
```

| Screen | What the developer sees and can do |
| --- | --- |
| Projects | Choose Development from the Space Switcher. The sidebar lists projects. Select a row to open its workspace inside the tab content. **Open folder** connects a checkout. Opening it again resolves to its existing project. Offer existing chat projects **Connect repository** and keep their prior conversations accessible in history. |
| Manager chat | One visible conversation per project. The composer has attachments, a removable feature/file context chip, Auto with override, and send or steer. The transcript shows decisions, proposals, worker summaries, and review actions. Detailed tool output expands on demand. |
| Overview | Project home. Put decisions needing attention first, then active features and changes since the last visit. Each row opens its source. For a new repo, offer **Use existing spec** or **Draft from repository**. Show the proposed draft for editing. |
| Product / Roadmap | Group features into lanes by product outcome, with dependencies and progress visible. **Suggest features** proposes cards with a reason and a reference to the spec, backlog, or repo. Accept, edit, dismiss, reorder, or link to an existing feature. Acceptance adds it to the roadmap. **Build** is a separate action. |
| Product / Feature detail | Show the user problem, expected behavior, scope, acceptance criteria, dependencies, decisions, tasks, and related runs. **Discuss** targets the manager composer. **Build** starts or resumes work. **Review changes** opens the evidence for this feature. |
| Product / Spec | One editable product definition with an outline. Link features to the requirement they address. The manager proposes a section edit with a diff. Accepting it updates the same document a developer can open in their editor. |
| Product / Pitch Deck | Ordered slides for the audience, problem, product, and supporting evidence. Draft from the Spec, edit individual slides, and present. Track the spec revision used so a later change can be reviewed before updating a slide. |
| Product / Design System | A reference for the selected project's actual tokens, components, and examples. Each entry links to its source. For Yab2, start with YabDesign. A different repository can point to its own library or design document. |
| Tasks | Three views. **Tasks** shows actionable work grouped by feature, including owner, status, and blockers. **Activity** records starts, decisions, edits, and checks in time order. **Changelog** groups accepted product changes and distinguishes released work when release evidence exists. Open any entry to reach the feature, run, or diff. |
| Agents / Team | Show the manager and workers, provider/model, assignment, status, and controls to inspect, steer, or stop. **Active Tools** shows each skill, plugin, or MCP connection, its source, and whether it is available to the selected runner. Team initially means the developer and their agents. |
| Code / Files | Repository tree and file preview, branch, changed files, diff, and check output. Open here from a task with its changes already selected. **Ask about selection** returns a path and line range to the manager. Provide **Open in editor** for manual edits. |
| Preview | Open the project's configured app URL in a browser tab. Each project keeps its own address. |
| Terminal | A project-scoped shell pane. The design prototype simulates command input and keeps a separate history for each project. |

Implement a small shared set of components. The Space Switcher, project sidebar, and project tool tab bar each handle a different level of navigation. A context chip, proposal card, run summary, and review card connect chat with project records. A feature card and dependency row serve Roadmap. A document outline and revision diff serve Spec and Deck. Task rows, event rows, and a changed-file list serve Overview and the detail screens. A card in chat and its counterpart on the roadmap should call the same action with the same record ID.

## How the manager keeps continuity

1. Resolve the project and any explicit feature or file reference. Match a follow-up to active work. If two features plausibly match, offer their names in the composer. Keep project-wide questions at project scope.
2. Record the feature brief and decisions separately from provider transcripts. Give a worker the approved scope, relevant spec sections, paths, acceptance criteria, and previous result. Opening an unrelated file to inspect it must never silently redirect an in-flight task.
3. In **Auto**, prefer the current capable runner for a follow-up. For a new task, use the project's preference for planning, implementation, or review, filtered by connected providers, available models, and required tools. Use the project default to break ties. Show the reason in run details and allow a one-run override. When another provider takes over, give it a saved brief and identify the handoff in Activity.
4. Persist one active run per task before launching. A second Build opens that run. Start with one writer per checkout. Queue another write and allow read-only review alongside it. Consider isolated Git worktrees when parallel implementation becomes necessary.
5. On reopen, reconcile the recorded run with the provider. Show its current state, or **Interrupted** with the last event and diff. Retrying creates a linked attempt. A successful process exit makes the result available for review. Acceptance records the product change, and release evidence records shipment.

**Storage proposal.** Keep machine-specific repository access, manager chat ID, run IDs, and view state in Yab's local profile. Keep the canonical Spec in a selected repo document and read external edits back into the workspace. Store feature briefs and approved product artifacts as reviewable repo documents with stable IDs. Keep operational task events local for the first version. Resolve document edits against their source revision before saving. Disconnecting or deleting a project must preserve its external checkout. Existing chat-only projects can opt into the workspace.

**Technical dependency.** Yab can already give a full-access session a working folder. The project files fallback is a Yab-owned directory. Codex's current launch path selects read-only or full-machine access, and Claude's full-access path depends on its permission mode. A working directory alone does not constrain writes. Before enabling Build, demonstrate repository-scoped operation and approval handling for each provider. Verify that a missing or moved checkout leads to reconnect, never execution in a fallback directory. [Launch and folder selection](../Sources/Fast/Agents.swift)

## Delivery checklist

| Milestone | Acceptance scenario |
| --- | --- |
| 1. Approve the pictures | Review three frames in the Yab shell: returning to Overview, refining a roadmap feature, and reviewing its diff beside chat. Include a narrow-window state. Get maintainer approval before implementing the feature. |
| 2. Open and resume a project | Connect two existing repositories. Switch between them, quit, and reopen. Each restores its manager, draft, and records. Old chat projects still open, and reconnecting a moved repo preserves its project identity. |
| 3. Ship one feature through the workspace | Deliver Overview, basic Spec, a roadmap list and feature detail, Tasks, and a minimal Code review. On a fixture repo, ask for a change, discuss it, build, steer, review the diff and checks, and accept it. Repeat with Claude Code and Codex. Repeated Build, stop/retry, and restart must preserve one task history. |
| 4. Make daily work easier | Add suggested roadmap lanes, prioritization, Activity and Changelog filters, Agents and Active Tools, and model overrides. Verify that the same decision appears once across chat, feature detail, and history. Exercise a provider handoff with a saved brief. |
| 5. Complete Product | Add Pitch Deck and Design System. Verify that manual deck edits survive a spec update and that design references open the correct repo files. |

For each new menu action, add the matching command-field entry and test its composed order. Classify any new Settings rows. Use the project, transcript, and provider suites around the changes, then exercise the complete workflow with isolated test projects. The first release is ready when a developer can return to a project, understand its state, and take one feature from request through review without choosing a chat or a model.

## Reference decisions

Use T3 Code for the pattern of controlling local coding agents, handing off a task, and reviewing Git changes. Use the supplied Codex image for the quiet composer and immediate project context. The supplied Remy frames are the reference for roadmap lanes, feature definitions, and the transition from definition to Build. [T3 Code](https://t3.codes/) · [T3 Code repository](https://github.com/pingdotgg/t3code) · [Remy](https://goremy.ai/)

Borrow BoardUI's compact context strip and accessible model override. Use the OpenUI idea of rendering structured answers as interactive components for suggestions, choices, and reviews. Render project actions with Yab controls and stable project records. [BoardUI Composer Panel](https://www.boardui.com/components/composer-panel) · [OpenUI](https://www.openui.com/)
