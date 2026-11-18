# Source migration checklist

Track the Mac app migration inside `Sources/Fast/`. Use `App/` for startup, navigation, and screens, `Components/` for UI grouped by feature and component, and `Services/` for app capabilities and their data. Preserve Swift package targets during file moves.

## Completed batches

- [x] Push the pre-migration checkpoint to `yab2/main` (`66edc24`).
- [x] Move `ChatProjectScreen.swift` to `App/Screens/Chat/` (`1f43558`). The SDK 26.5 compatibility preview passed 32 tests before and after. The project draft appeared and closing chat restored page focus in both runs.
- [x] Move `ChatComposer.swift` to `Components/Chat/ChatComposer/` (`633a283`). The preview passed 42 tests and the project flow. In the standalone composer, the first close left focus on the window. A repeat with initial page focus confirmed restored page focus.
- [x] Move `ChatColumn.swift` and `ChatRestoration.swift` to `Components/Chat/ChatColumn/` (`bd06bcb`). The preview passed 49 tests across eight suites. Both the project field and standalone composer displayed a typed draft and returned focus to the page on close.

## Remaining work

- [ ] **Suggested next batch:** inspect `ChatProjectCard.swift`, `ChatProjectPill.swift`, and `ChatProjectViews.swift` and their callers. Choose one component and its private subviews to move together.
- [ ] Inventory the remaining Chat files. Assign each to its owning screen, component, or service and record the resulting batches here.
- [ ] Complete the remaining Chat batches using the checks below.
- [ ] Verify the standard Yab Dev build with `./build.sh`, launch it, and repeat the Chat flow. Verification so far used the SDK 26.5 compatibility preview. The standard build was blocked by the missing Foundation Models compiler plug-in in Command Line Tools and pending license acceptance in full Xcode.
- [ ] Inventory the remaining Mac app features and add a checkbox per batch before moving each feature.
- [ ] Review remaining files at the root of `Sources/Fast/` and document any intentional exceptions.

## Checklist for each batch

- [ ] Record the files, destination, and baseline commit. Identify a working flow to repeat. Capture a fresh baseline when the flow changes.
- [ ] Move the files within the same target. Check source-path references in scripts, docs, and build tooling.
- [ ] Run the design check on moved Swift files, build the app, and run the affected test suites.
- [ ] Launch the rebuilt app in an isolated test profile. For Chat, start with keyboard focus on the page, open the project, type and verify a visible draft, close chat, and verify focus returns to the page. Repeat with the standalone composer when affected.
- [ ] Record the build configuration, test count, runtime result, and any outstanding issue. Commit the scoped changes locally and add the commit hash to Completed batches.
