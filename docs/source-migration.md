# Source migration checklist

Track the Mac app migration inside `Sources/Fast/`. Use `App/` for startup, navigation, and screens, `Components/` for UI grouped by feature and component, and `Services/` for app capabilities and their data. Preserve Swift package targets during file moves.

## Completed batches

- [x] Push the pre-migration checkpoint to `yab2/main` (`66edc24`).
- [x] Move `ChatProjectScreen.swift` to `App/Screens/Chat/` (`1f43558`). The SDK 26.5 compatibility preview passed 32 tests before and after. The project draft appeared and closing chat restored page focus in both runs.
- [x] Move `ChatComposer.swift` to `Components/Chat/ChatComposer/` (`633a283`). The preview passed 42 tests and the project flow. In the standalone composer, the first close left focus on the window. A repeat with initial page focus confirmed restored page focus.
- [x] Move `ChatColumn.swift` and `ChatRestoration.swift` to `Components/Chat/ChatColumn/` (`bd06bcb`). The preview passed 49 tests across eight suites. Both the project field and standalone composer displayed a typed draft and returned focus to the page on close.
- [x] Organize the Chat project components (`bd8bf98`). The card owns its folder, the pill belongs to the composer, and the project views are shared across callers. All three files moved byte-for-byte. The SDK 26.5 preview passed 49 tests across eight suites and displayed the project details card. Both drafts appeared on both runs. Project chat restored page focus twice. Standalone composer focus returned to the window on the first run and to the page on the repeat.
- [x] Group ChatFlight, ChatMotion, and ChatZoom under `Components/Chat/ChatMotion/` and ChatMovement under `Components/Chat/ChatColumn/` (`35e3487`). Four byte-for-byte moves. One SDK 26.5 compatibility build passed, followed by 6 tests in ChatMotionTests and ChatMovementTests.
- [x] Finish Chat from baseline `a95f6bd`: 19 byte-for-byte moves in one SDK 26.5 compatibility preview build. 74 tests across 8 relevant suites passed. Project chat and the standalone composer displayed their drafts and restored page focus on close.
- [x] Migrate Bookmarks from baseline `bef1e7f`. Five byte-for-byte moves. One SDK 26.5 compatibility build passed, followed by 32 tests across five bookmark suites covering the bar, field, dates, suggestions, and Spotlight.

## Remaining work

- [ ] Investigate intermittent page-focus restoration after closing the standalone composer. The initial page-focus check passed on both runs.
- [x] Inventory the remaining top-level Swift files with Chat in their names. The proposed batches below cover all 24 files present at the start of the motion batch.
- [x] Finish the remaining Chat-owned files in one batch.
- [ ] Verify the standard Yab Dev build with `./build.sh`, launch it, and repeat the Chat flow. Verification so far used the SDK 26.5 compatibility preview. The standard build was blocked by the missing Foundation Models compiler plug-in in Command Line Tools and pending license acceptance in full Xcode.
- [x] Inventory the remaining Mac app feature areas. Track their migration below.
- [ ] Review remaining files at the root of `Sources/Fast/` and document any intentional exceptions.

## Chat batch inventory

Names below are Swift source filenames without the extension. The final ownership review also identified Projects and ArtifactCard.

- [x] **File cards and previews** → `Components/Chat/ChatFileCard/`: ChatFileCard, ChatQuickLook.
- [x] **Transcript and status lines** → `Components/Chat/ChatTranscript/`: ChatTranscript, ChatNotes, ChatProblem, ChatSubagent.
- [x] **Result controls** → individual folders under `Components/Chat/`: ChatResultCard, ChatCopied, ChatWidget, ArtifactCard.
- [x] **Project interactions** → `Components/Chat/` for ChatNewProjectSheet and ChatProjectMoves, `App/` for ChatProjectCommands (command routing).
- [x] **Routine notices** → `Components/Chat/ChatRoutineBanner/`: ChatRoutineBanner.
- [x] **Conversation storage and item parsing** → `Services/Chat/`: Chat, ChatItem, ChatItemDetails, ChatPublished, Projects.
- [x] **Web tab activity** → ChatBusy stays with browser tab activity detection.
- [x] **Integrations** → MailChat stays with Mail, and SyncChats stays with sync services.

## Mac app feature inventory

At baseline `bef1e7f`, 1,089 Swift files were directly under `Sources/Fast/`. This is a feature-level inventory of that target. Each row names representative entry points to check for callers and shared ownership before moving a feature. Large areas can have several independently verified batches.

- [x] **Bookmarks** — bookmark storage and Spotlight, bookmarks bar, native menu, and command-field destination. Agent tools and browser import adapters stay with their respective owners.
- [ ] **Library and discovery** — History, LibraryPage, HomeTab, HomeLibraryList, Diary, DayThreads, Recall, and suggestions.
- [ ] **Files and downloads** — DownloadRequest, DownloadFile, Hoard, FileShelf, DockProgress, SaveFile, and download notifications.
- [ ] **Reading and documents** — Reader, PageTranslation, PDFDesk, PDFFill, PageSave, Capture, Find, and selection controls.
- [ ] **Navigation and command field** — AddressBar, Omnibox, Query, FieldViews, Places, MenuCommands, Calculator, and search providers.
- [ ] **Tabs and workspace layout** — TabBar, Stage, Side, column layout, Spaces, Split, Switcher, pins, tab dragging, and sleep.
- [ ] **Links and small windows** — Links, LinkRoutes, LinkPeek, PeekSurface, LinkWindow, and SmallWindowSettings.
- [ ] **Profiles and data portability** — Profile, Accounts, Import, Exports, browser-specific importers, and sign-in continuity.
- [ ] **Mail, calendars, and calls** — MailDesk, MailPage, MailChat, Meetings, Invites, Calls, and provider connections.
- [ ] **Agents and assistants** — AgentTask, Agents, AssistantHost, provider runners, approvals, AI model selection, and agent tools.
- [ ] **Automation and integrations** — Routines, Memory, Skills, MCP, SystemIntents, CLI, and remote tasks.
- [ ] **Sync and devices** — SyncCenter, SyncChats, SyncPhone, SyncTasks, and device pairing.
- [ ] **Web engines and navigation policy** — Engine, ChromiumPage, WebKitPage, process lifecycle, networking, and engine switching.
- [ ] **Developer tools** — DevWorkbench, DevConsole, DevNet, DevElements, DevSources, recorder, and inspection.
- [ ] **Extensions and customization** — Extensions, native/Chromium extension bridges, Boosts, Userscripts, live folders, and Store.
- [ ] **Privacy, credentials, and site controls** — SitePermissions, Shield, SafeBrowsing, vaults, passwords, passkeys, certificates, and private browsing.
- [ ] **Forms, wallet, and payments** — FormFill, FormDraft, Wallet, PayFlow, and payment sheets.
- [ ] **Media and sharing** — Float, DocumentPiP, PlayerBand, NowPlayingArtwork, Share, Clipboard, and image actions.
- [ ] **Settings, input, and appearance** — SettingsWindow, Prefs, shortcuts, mouse gestures, RadialMenu, shared controls, icons, and themes.
- [ ] **App lifecycle and onboarding** — AppStartup, BrowserWindows, Session, Welcome, Updater, crash recovery, and feedback.
- [ ] **Diagnostics and feature-specific tools** — Bench, feature benches, watchdogs, traces, and seasonal experiences such as Wrapped. Check build-script paths before moving these.

## Checklist for each batch

For folder-only work, group related moves within the same Swift target into one batch. Use `git mv`, check for old paths with `rg`, and confirm pure renames with `git diff --cached --summary` (100% similarity). Build once for the whole batch and run the suites that exercise the moved files. Repeat the interactive flow once per batch when requested or when the change affects visible behavior.

- [ ] Record the files, destination, and baseline commit. Identify a working flow to repeat. Capture a fresh baseline when the flow changes.
- [ ] Move the files within the same target. Check source-path references in scripts, docs, and build tooling.
- [ ] Run the design check on moved Swift files, build the app, and run the affected test suites.
- [ ] When verifying a UI flow, launch the rebuilt app in an isolated test profile. For Chat, start with keyboard focus on the page, open the project, type and verify a visible draft, close chat, and verify focus returns to the page. Repeat with the standalone composer when affected.
- [ ] Record the build configuration, test count, runtime result, and any outstanding issue. Commit the scoped changes locally and add the commit hash to Completed batches.
