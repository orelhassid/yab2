# Working on Yab

Rules for everyone who changes Yab, people and coding agents alike.
CONTRIBUTING.md covers how to send a change; this file covers how to make one.

## Commits in Yab2

For work in the `orelhassid/yab2` fork, make a local commit automatically
after completing the requested changes and running the checks they need.
Stage only changes that belong to the task, including individual hunks when
a file contains unrelated edits. Leave existing staged changes out of the
commit. Report the commit hash when handing back the task. Push only when
the user asks.

## Build and test

- `./build.sh` builds Yab Dev, ad hoc signed, with no update feed, no
  telemetry, no Store and no sync. That is the build to work on.
- `swift test --filter Suite` runs one suite. Run the suites your change
  touches before you send it.
- `scripts/swift-parse-check` runs from `.githooks/pre-commit`
  (`git config core.hooksPath .githooks`) and stops a commit with a Swift
  syntax error. It does not check types: after changing a signature or an
  optional, find every caller.
- `./design-check --file PATH` checks a Swift file against the design
  system (shared frames, buttons, key marks). Fix what it reports.

## Reuse the native sidebar

Use All Tabs as the reference when changing a Space sidebar. Group rows with
`SidebarSection` and `SidebarSectionHeader`. Use `SideRow` for browser tabs
and `SidebarTabButton` for other selectable destinations. Both use
`SidebarTabRow`. Use `Quiet` for a New action, `SpaceName` for the Space
switcher and `SidebarSectionDivider` for a section divider. Locate the
existing sidebar search control before adding a search field.

Configure these components with content and actions. If a Space needs a
variation, extend the shared component and check both the Space and All Tabs.
When a maintainer corrects a recurring UI pattern, record the specific rule
and its owning component here or in the relevant project skill.

Give navigation and catalog list rows a leading icon. Providers, plugins,
and skills use the brand mark when available or the shared symbol for the
item type.

Browser pages and Development share the native `TabWindowHeader`,
`TabWindowSwitcher` and strip variant of `SidebarTabButton`. Embedded
workspaces leave header rendering to their native host in every layout.
Check split, chat-only and full view when changing that boundary.

## Shared local preview

All chats working in this checkout share `build/Yab Sidebar Preview.app` and its `spaces-preview` profile. Reuse the running instance for interactive review. When an update is needed, build from the shared checkout and refresh that same app after checking for another session's active build or UI test. Keep isolated automated tests in their own test profiles and close any temporary test app when the run ends.

## How much proof a change needs

Pick the lowest level that fits:

1. **None.** Docs, copy, colors, spacing, constants. Commit.
2. **Compile.** A small code change with nothing to look at: build it and
   run the suites around it.
3. **Before and after.** A reported bug, visible behavior, motion,
   performance, anything a release note will claim: show the broken state
   and the fixed one (screenshots, a recording, numbers).

Never call a bug fixed without having run the scenario that showed it.

## Menu actions stay discoverable in the command field

A new or renamed menu action is not done until the same action is indexed
in the command field (`Command` in `Sources/Fast/Query.swift`): its names
and aliases, when it is available, its toggle state and its shortcut. An
exact match must show above history and web suggestions. Add tests for the
real composed order of `Browser.offers`.

## Settings stay changeable by Yab's own agent

A new or renamed row in `SettingsIndex.swift` must be classified in
`Sources/Fast/NativeActions.swift`; `NativeControlTests`
(`everySettingsRowIsClassified`) fails until it is. Plain switches go in
`NativeSetting.all`; lists and per-site settings are native actions with
undo; the person's own decisions (privacy, passwords, AI consent,
permissions) go in `NativeActions.controlled`.

## Writing

- American English in the app, docs and commits. No em dashes: use a comma,
  a colon or a new sentence.
- No explanatory captions under settings, titles or pickers; a second line
  only for data.
- For new user-facing features, get a maintainer's approval on a picture
  before implementation. Changes to existing features, including layout,
  styling, copy and interaction refinements, can proceed directly.

## Incremental build failures

Yab Dev uses an optimized debug build in `.build/dev-optimized`; release and
`YAB_WMO=1` use whole-module optimization. Never combine `-c release` with
`-no-whole-module-optimization`. For `unable to open dependencies file`,
read the actual command and output-file map before retrying, and fix a mode
mismatch in `build.sh` instead of clearing caches. See
https://github.com/swiftlang/swift/issues/70995.

## Theme ownership

Resolve window chrome from the active Space. In Development, the selected
project supplies that look. Pass the resolved tone into each hosting root,
including the Trail, sidebar, popovers and embedded workspace. Use the
shared palette for controls and interaction states. Check a light and a
dark project with the Trail visible when changing these surfaces.

## Project chat

Use Codex as the visual reference for Development chat: plain assistant
replies, rounded user messages, and a two-row composer with controls below
the draft. Use T3 as a reference for provider and integration behavior.
Development uses the shared native chat composer, transcript, and provider
settings. Keep project drafts and conversation IDs with their project.
Verify composer changes in the project pane as well as the browser column.
For a live check, mention a file in a temporary project, read it with Codex,
and switch projects and back to verify the conversation.
Show project providers as horizontal tabs backed by the shared provider
registry. Keep model choices and chat IDs scoped to the project and provider.
When changing Codex access, test the composer switch in a temporary source
folder and verify both the edited file and the test result on disk.

Keep Development environment settings and plugin availability shared across projects. Put project-specific settings in the project tab strip. Space and project header switchers share the tab control and popover.
