# Projects of chats

A project is to chats what a contact is in Messages: a circle with an
emoji, its conversations, what its agent is told (instructions), what it
remembers, its routines and its files. The concept picked on 2026-10-24 is
the "iMessage way" artifact, https://claude.ai/artifact/KGEud9jpw3Rq4Jn9xho4hL
(12 states). Asked for by J in Yab Alpha: his routine's chat was three
screens deep in Settings › AI › Routines.

## Model

- `Project` (Sources/Fast/Services/Chat/Projects.swift): `id` (`prj-` and eight letters),
  `name`, `emoji`, `tint` (one of `Project.tints`), `instructions`,
  `memoryOn`, `pinned`, `archived`, `created`, `updated`, `order`. One file a
  project in `projects/`, written a second after a change, as chats are.
- `Chat.project` and `Routine.project`: optional, so old chats read as they
  were. `Chats.move(ids, to:)`; deleting a project takes its chats back to
  Chats and its routines run on without it.
- What a chat in a project is told, in this order (`Agents.brief`):
  the project's instructions, then its memory, then the conversation.
- Memory: `memory/projects/<id>.md`, written after a turn the way the shared
  memory is, a fact a line; seen and forgotten one by one on the card.
- Files: `agent/project/<id>/files/`, shared by every chat in it.
- Sync: `SyncProject` records and `SyncChat.project` (docs/sync.md); memory
  and files stay on the Mac.

## The Mac's chat column

| What | Where | Code |
| --- | --- | --- |
| Chats as rows of 74 (face, name, when, two lines, the unread dot) | the list | `ChatListRowBody`, `ChatHistoryRow` |
| Pinned projects, three a row in circles of 72, a bubble with what is new or the typing dots | over the rows | `ChatPinnedProjects` |
| A project not pinned, a row among the chats by its latest | the list | `ProjectListRow`, `ChatListEntry.merge` |
| A project open as a group chat, "New chat in ‹Project›" at its foot | the list's place | `ChatProjectScreen` |
| Its card: Chat, Routine, Files, Pinned; Instructions, Memory, Files; Archive, Delete | its name | `ChatProjectCard` |
| Moving a chat: right click › Move to Project, ⌃⌘P, two fingers across a row (Project, Pin, Archive), the row dragged onto a circle | rows, the chat | `ChatMoves`, `ChatSwipe` |
| A chat in a project: the circle on the agent's face, "‹Project› · model" under its name, ‹ back to the project | the chat's head | `ChatHead`, `ChatFace`, `ChatName.status` |
| A new chat's project pill, which changes it | the field | `ChatProjectPill` |
| New Project, as New Group: face, name, instructions, chats ticked | the folder-plus in the list's head, New Project… | `ChatNewProjectSheet` |
| A routine's news at the column's top, its project's circle, a click opens its chat | the column | `ChatBanners`, `Routines.finished` |
| ⌘T's Chats finds projects first: ↩ opens, ⌘↩ asks in it | ⌘T › Chats | `Browser.projectActions` |

Keys: ⌃⌘P moves the chat in the column (Raycast's ⌃⌘M is Mute Call here).
The pinned projects take no ⌘1-⌘9: those are the tabs'.

Not in v1: a project tied to a space, a working folder on disk (files live
in the project), a coordinator with subagents.

## Command field

Projects are indexed in plain Cmd+T and in Chats, including with More Commands
in the Field off. A name or its first three letters opens the project before
matching history; Cmd+Return starts a chat in it. New Project, Move to Project,
About Project, Rename, Pin/Unpin, Archive/Unarchive, Delete, Files, Routine and
Memory On/Off use the same current project and states in the Actions list.
Removed and archived destinations are rejected at execution. Private and
Small Window fields do not expose personal project destinations.

File context actions and individual memory facts are intentionally local to
the selected file/fact in the project card. The command field opens that card
or its files; it does not guess which fact or file to remove. The destructive
project command retains its confirmation and is not promoted through aliases
to default Return.

## Verification and delivery

The current source completes Mac steps 1–9 of PLAN-chat-projects.md. Runtime,
visual and Mac–iPhone acceptance are pending until the combined release QA
runs and the owner reviews the prepared app. iPhone 0.1.10 shipped its own UI;
this does not prove the live pair with this Mac source.

`qa/pending/chat-projects-mac.json` retains model, presentation, command and
sync suites; the ready-app probe uses a stand-in Claude to check instructions,
chat creation, moving, a scheduled routine, deletion, restart and field routes.
Its screenshots are fixture evidence, not reporter-profile or visual acceptance.
`evals/chat-projects/shots.py` captures light and dark states on that same app.
No separate per-session build is required. The selected 12-state design is
archived at `docs/design/chat-projects-v3.html` for comparison.
