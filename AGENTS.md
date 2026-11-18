# Working on Yab

Rules for everyone who changes Yab, people and coding agents alike.
CONTRIBUTING.md covers how to send a change; this file covers how to make one.

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
- Visible changes (menus, layout, icons, colors, motion, copy) need a
  maintainer's yes on a picture before the code: open an issue with the
  screen as it is and your proposal.

## Incremental build failures

Yab Dev uses an optimized debug build in `.build/dev-optimized`; release and
`YAB_WMO=1` use whole-module optimization. Never combine `-c release` with
`-no-whole-module-optimization`. For `unable to open dependencies file`,
read the actual command and output-file map before retrying, and fix a mode
mismatch in `build.sh` instead of clearing caches. See
https://github.com/swiftlang/swift/issues/70995.
