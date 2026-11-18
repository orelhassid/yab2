# Where an agent's question goes

An agent's question is asked where its answer acts. A question about the
whole chat ("Search your mail?", "Go to returns.shopco.com?") is asked of the
chat, in a macOS notification with buttons. It never lands on whatever tab
happens to be in front. A question about a page is asked at the foot of that
page. Money, words sent as the person and the Mac are answered inside Yab,
where the amount, the recipient and the text can be read.

## The bug this fixed

A chat from the column, ⌘J or D in mail has no tabs of its own. Before,
`Bench.askOnce` put its mail question on `agents.tabs(of:).last ?? browser.active`,
the tab the person was looking at, say X. From there:

- `Agents.ask` made X a guest tab (`tab.guest`), so the agent's face showed
  on X through `Tab.worker`.
- `Agents.answer` only cleared `guest` on a no to `.use`, so a yes to a mail
  question left X a guest.
- `finish` marked X unread (`AgentFeed.ended`) and hung the chat's answer on
  it before `leave` ran.
- The yes lived in `tab.approved` for 120 s. `Mcp.patient` called again,
  `askOnce` picked a tab again, and if another tab was in front by then, the
  same question came up a second time.

## Where each question goes

`AgentPermit.place` ([AgentPermit.swift](../Sources/Fast/AgentPermit.swift))
says where, by kind:

| Place | Kinds | Asked | Answer kept |
|---|---|---|---|
| `.chat` | `mailRead`, `mailChange`, `mailSite` | macOS notification with buttons; the chat's field while the column shows that chat | the root chat (`mailReading`, `mailChanges`, `mailSites`) |
| `.page` | `use`, `press`, `upload`, `signIn`, `address`, `unlockManager` | the foot of the tab the agent works in | `tab.approved`, once |
| `.send` | `sendMail`, `sendMails` | the app-owned FIFO in the window's corner; a notification only opens Yab | the outgoing operation and its joined callers |
| `.send` | `press` that pays or has an amount, `sendMessage`, `messages`, `saveSkill` | in Yab: the pay sheet with Touch ID or the chat's field; a notification only opens Yab | as before |
| `.mac` | `computer`, `folder`, `native` | over Yab; a notification only opens Yab | as before |

Only `.chat` questions get buttons in a notification: each is a yes for the
rest of one chat and can be taken back. Only a `.page` question makes the tab
a guest (`Agents.ask`), so a send or Mac question asked on one of the
person's tabs puts no face on it.

`send_message`, `ask`/`choose`, `computer_access` and
`FolderAccess` pick their tab with `Agents.askTab`: the task's own latest
tab; else the tab of yours its question, its last yes or no, or its send is
on, so the call that comes again finds the answer whatever is in front by
then; else the tab in front, never a private one. A question put on a tab
that isn't in front brings the column out with its chat (`Agents.showAsk`),
where the card stands in the field.

A pick (`ask` with options) on a tab of yours sets `Tab.asker`, not
`guest`: its card and choices stand at the page's foot and in the column,
but no face, no unread mark and no answer. `Tab.askedBy` (worker, permit or
asker) is who the card, the dock, the column and `handoff-wait` speak for.
`handBack` takes the asker for a question already gone from the tab, so the
task leaves `waiting`.

## Concurrent mail sends

`Agents.queueMail` keeps each immutable outgoing operation in `MailSendAsk`
([MailApprovalQueue.swift](../Sources/Fast/MailApprovalQueue.swift)). Each
has its own request id and monotonic arrival order. Identical outgoing
requests join it across sessions; different requests cannot own the same
draft simultaneously. The exact consent key includes recipient roles,
sender, schedule, content and attachment identities.

The app executes the approved snapshot once. The existing draft and account
are checked again before dispatch, and a changed draft requires another
review. A session ending detaches its receipt; the pending operation remains
answerable even with no caller left. Not Now declines that operation for all
joined callers. The existing Undo / Send Later operation retains its send
claim, so another CLI cannot schedule the held draft again.

`Mcp.patient` follows `mailAsk` in `handoff-wait`, then receives the stored
result. An assistant returning after approval finds its original tool-call
receipt before resolving a draft that may already have been renamed or
sent. These questions and their Sync records use the operation identity,
without occupying `Tab.permit` or a chat's read-consent permit.

## A chat's question

`Bench.askOnce` hands a `.chat` question to `Agents.askChat`:

1. A no said earlier (`root.declined`, by the permit's key) is heard once, as
   the same error `tab.declined` gave.
2. One question per chat at a time: while `root.permit` holds one, the next
   waits for it and doesn't replace it. Different chats ask separately.
3. Nobody there (`--no-person`, an unattended run): a no at once.
4. Otherwise `root.permit` is set, the asking session goes to `waiting`, and
   the call answers `["asking": true, "chat": root.id]`, with no `tab`.

`AgentNotices.ask` ([AgentAsk.swift](../Sources/Fast/AgentAsk.swift)) posts
`agent.permit.<chat id>`, with Yab in front too, since no tab shows it:
title "Claude needs you" (the plan's name), subtitle "<chat> · once for this
chat", body the question and what it looks for. Categories
`agent.mail.read` (Search, Not Now), `agent.mail.site` (Go, Not Now) and
`agent.mail.change` (Allow, Not Now) sit next to mail's and sites' in
`prepareCategories()`. The buttons don't bring Yab forward.

In `userNotificationCenter(_:didReceive:)`, `info["permit"]` goes to
`AgentNotices.answer`: the buttons call `Agents.answer(chat:yes:key:)`, a
click on the notification brings Yab forward with the card on screen
(`AgentNotices.show(chat:)`, see "A click on the notification"), and
dismissing it answers nothing. The key must match the question asked now, so
a late button on an answered or replaced question does nothing.

`Agents.answer(chat:yes:key:)` writes the yes into the root chat or the no
into `root.declined`, clears `root.permit`, removes the notification and
wakes the column. No tab is touched. The call that comes again finds the chat
allowed before it reaches `askOnce`, so switching tabs in between doesn't
matter.

The column shows `root.permit` in the field's place (`ChatPermitCard` in
[ChatComposer.swift](../Sources/Fast/Components/Chat/ChatComposer/ChatComposer.swift), fed by
`ChatFeed.permit`), with Return for the yes and Escape for Not Now (App.take).
An answer in either place closes both.

`Mcp.patient` and `handoff-wait` wait on `chat` when the answer carries it:
`waiting` while `root.permit` stands, `done` once it doesn't, `stopped` once
the asking session isn't live. After five minutes the agent hears "hasn't
answered yet" and the question stays.

## Another app's agent: once a session

An agent outside Yab (Claude Code in a terminal or the Claude app) can open
many `yab mcp` connections in one session: its own MCP server, and one per
command its shell runs. Each attaches as its own external session, so a yes
kept only on `root.mailReading` asked again for every one of them (October
21: four searches from one Claude Code session, four cards). `Mcp.attach`
now sends the client's own session, Claude Code's `CLAUDE_CODE_SESSION_ID`
(the same value in its MCP servers' and its shell's environment), as
`client`; `Agents.attach` keeps it on `Session.client` when it reads as an
id (`Agents.clientSession`).

A yes to reading mail (`Agents.grantMail`) is kept in `Agents.mailGrants` by
that id too, so every read verb (triage, search, list, recall, read, file)
of any connection naming the same session goes on with no card
(`Agents.mailGranted`). It is kept while Yab runs and lapses after
`mailGrantLife` (12 hours) unused; each read that uses it renews it. A
different session, or a client that names none, asks for itself. Only
reads: a change still asks once per connection, a send every time, and a
Not Now is heard once and grants nothing. The card says so: its yes is
"Allow for This Session" (`AgentPermit.forSession`), the notification's
category `agent.mail.read.session` with the same button, its subtitle
"once for this session" (`Session.askedOnce`). Yab's own chats keep Search
and "once for this chat". Tests: `Tests/FastTests/MailSessionGrantTests.swift`.

## With Mail you hand to Claude off

Yab's own chats get the mail tools whenever an account is in, Settings ›
Mail › Agents' Mail you hand to Claude off too (`handleAgentCaps`), so a
chat asked about mail asks for it instead of going to Gmail's pages for
want of them. Its first mail call, whatever it is, asks "Search your
mail?" of the chat (`Bench.mailAsks`), the consent's words on it: what it
looks for, who reads it on whose plan, under whose terms, and that Yab
keeps no copy. A yes is for that chat only (`root.mailReading`): the switch
stays off, since only the person turns it on (docs/casa.md, Consent). A
change asks for itself after it as usual. Another app's agent still gets
neither the tools nor a question while the switch is off.

## Finding you

Since October 21 every question has a home, the place it is read whole and
answered (the chat's field, the agent's tab's foot, the pay sheet, the Mac's
window), and Yab says it where you are, climbing only when you aren't
looking ([AgentAskCorner.swift](../Sources/Fast/AgentAskCorner.swift)):

1. **Its home in sight** (the column out with that chat, the agent's tab in
   front): only there. No sound, no notification, no iPhone.
2. **Yab in front, the home out of sight:** the page's bottom right
   corner holds it until it is answered (`AskStandView`, since October 22;
   the top right stays for notices and meetings). A chat's question and a
   send asked of a tab that isn't the agent's stand there whole, as the
   card below, never at the foot of someone else's page
   (`Agents.inCorner`, and `sendingInCorner` while its yes runs); a page
   question on another tab says "needs you" with Show, which no fling puts
   away any more. Return, ⌘Return for a send, and Escape answer the one in
   front from anywhere not typed into (`Agents.cornerKeyed`). The
   question's sound plays once, whether the queue or the card calls it
   first (`Agents.noticeID`). No banner.
3. **Yab behind:** the Mac says it at once (`AgentNotices.hold`), Time
   Sensitive, in the question's own sound, one group a chat
   (`threadIdentifier`), and the Dock's icon bounces
   (`requestUserAttention(.criticalRequest)`) until you come back. The
   banner carries the sound; Yab doesn't play it as well. A question that
   came while Yab was in front is said when Yab goes behind, quietly if it
   was heard already.
   Three minutes unanswered, it is said once more ("Waiting 3 min"), the
   old one taken off first so the new one is a banner and not a quiet
   update. A chat's mail question keeps its Search / Go / Allow and Not Now
   buttons; anything else opens Yab.
4. **The iPhone:** a local agent's question goes there at once, quiet
   while you are at the Mac: already `seen`, so opening Yab for iPhone
   shows it in its tray, answerable, with no notification. **Away from
   the Mac** (screen locked or asleep, or nothing typed or moved for two
   minutes, `AskPresence`) it rings there (`AssistantApprovals.presence`,
   `AssistantApprovalRecords.ring`), unless you had already opened it on
   the Mac; when you're back it is quiet again (seen), its card still
   answerable. An assistant in the cloud asks the iPhone, ringing, at once.

Answered anywhere, it goes everywhere: the corner, the notification
(`release`), the Dock, the iPhone. A question from Yab's last run is taken
out of Notification Center at launch.

The sound (`AskSound`): two soft notes, E6 then A6, a fourth up as a
question rises, made once into `~/Library/Sounds/Yab Question.aiff`, where
notifications find it by name; Yab plays the same file. None during a call,
and none at all with Settings › Agents › Sound for questions off
(`agentsAskSound`, `agents.ask-sound`): the banner then comes quiet.

Time Sensitive needs `com.apple.developer.usernotifications.time-sensitive`
in Yab's provisioning profile, which doesn't carry it yet: the App ID gets
the Time Sensitive Notifications capability on developer.apple.com, the
profile is made again, and then the entitlement goes into
`yab.entitlements`. Until then `interruptionLevel = .timeSensitive` is an
ordinary notification and a Focus keeps it quiet; the corner and the
iPhone still say it. A banner that stays on screen is the person's choice:
System Settings › Notifications › Yab › Persistent.

### A click on the notification

A click on a question's notification (its body, not a button) brings Yab
forward ready to answer (`AgentNotices.come`): Yab unhidden and active,
the window that holds the asking tab (else the one last in front) out of
the Dock and key, a new window if none is open. Then the card:

- Yab's own chat with a page in front: the column comes out with that
  chat, the card in its field.
- Another app's agent (`yab mcp`), work out of sight, or no page in front:
  the window's corner holds the card (`Agents.columnHolds`). The column is
  only drawn beside a page, so a chat shown in it with no page in front
  stays in the corner (`corneredAll`).
- A send or a chat's question asked on a tab of yours (`Agents.inCorner`):
  the corner, without switching tab or space. Any other tab's question:
  that tab, in its window and space (`BrowserWindows.reveal`).

The corner stands with no tab in front too (a space with nothing in it),
and `Agents.askTab` then picks a tab of yours nothing asks in, this
space's first, so `mail_send`, `send_message`, `ask`/`choose` and the rest
ask there instead of failing with "no tab to ask in". The eval is
`evals/mail/notice_click.py`, the tests `Tests/FastTests/NoticeClickTests.swift`.

Notifications turned down, or a bare binary: the corner says it all the
same. A Yab working out of sight (`Headless.hidden`) shows its window for a
chat's question, once a chat (`root.shownForAsk`).

## The card

Every question with a yes stands in one card, AgentAskCard ([AskCard.swift](../Sources/Fast/AskCard.swift)),
in the corner and in the chat's field alike, the iPhone tray's anatomy at
the Mac's sizes (picked 2026-10-22, claude.ai/artifact/AR1ksAvCJAozRoQo5rgoLh):

- **Head:** who or what it is about (`AskContent.Mark`: the person, the
  site, your mail, your Mac), with the agent's face on the corner of its
  mark (`AskFaceBadge`: the disc is the face, two upright eyes, cut out
  of the mark by a ring of the card), the plan and the chat's name under
  it, "1 of N" while more wait.
- **Body:** the thing itself, from the same detail the iPhone reads
  (`ApprovalDetailBuilder`): a mail as paper (To, Cc, Subject, six lines,
  Show All growing it in place), several mails as rows that open in the
  card (the person's mark travels from the row up into the head; ‹ back),
  a search as its search field with how far the yes reaches, a message's
  bubble, files, a sign-in's accounts (each row a yes), the button a press
  would press.
- **Foot:** Always Here (⌥ Never Here), Not Now with esc, the yes in the
  act's own words with ⌘↩ when it can't be taken back and ↩ when it can.
  The buttons never move while the card is up: every face of a button is
  laid out under the others (Not Now dimmed while a yes runs, the yes's
  ring and its -ing words), and the card grows upward from them.
- **After a yes:** a ring draws round the yes (0.6 s), then its -ing words
  while it runs. A mail held for Mail's Undo send folds round its two
  buttons into a small capsule in the corner, so the page stays free
  (`AskStand.sending`, `Agents.foldSent`, `AskToastView`): the person's
  mark travels in from the card's head, Undo with ⌘Z stands where Not Now
  was (`MailAgent.takeBack` for each of its drafts), and Send's place is a
  blue pill, "Sending to Anna" with the seconds rolling down. Then the
  pill turns green, "Sent to Anna", or grey, "Not sent", Undo goes, and
  the capsule closes round the mark and the pill before it leaves.
  Before this, nothing on screen said an agent's mail was still waiting.
  A failure stays on the card, the reason in red over the buttons; the
  yes keeps its word and tries again.
- **Answered elsewhere, or stopped:** the buttons give way to what
  happened ("Allowed on iPhone", "Claude stopped") for 1.2 s before the
  card goes (`AskStand.said`), so a card never vanishes without a word.
- **Several at once:** monotonic request arrival order, oldest in front,
  the rest indicated by the existing plate and counter (`Agents.corneredAll`).
  The answered card folds and leaves from its own anchor; animation completion
  mounts the next question. The question's space is retained during this
  handover, with Undo toasts above it. A toast has a separate layout identity,
  so a full card never moves to a new list index. Only the mounted head whose
  entrance has finished accepts approval clicks or keyboard confirmation.
- **The agent's own tab:** while it is in front, its question stands at
  the bottom right too (`Agents.inCorner`, `inFront`), and the working
  dock at its foot steps aside while it does, so every question is in one
  place and nothing runs under the card. Off the tab in
  front, a page's question waits on its page ("needs you", Show).
- **Choices (the ask tool):** the same card on the tab in front
  (`ChoiceAskCard`): the question, its choices by number (the digits pick
  from the page), Something else in your own words, Skip or Stop.

## Paying: a button first, then Touch ID

A payment asks in its own sheet in the chat field's place (`PaySheet`,
`PaySheetModel`, `PayFlow`). Its foot is a line over two buttons pinned to
the sheet's trailing edge: Cancel (esc) and one primary button that keeps
its place and its width through every state (hidden twins of every face).

- **Before the press:** "Pay $42.10" with the `confirmDanger` keys (⌘↩ by
  default). Nothing listens, and the press itself pays nothing. A bare ↩
  only says, in the corner, that Pay takes ⌘↩.
- **Armed:** a click or ⌘↩ turns the same button into Touch ID, its mark
  breathing (still under Reduce Motion), Cancel beside it, the line "Touch
  ID to pay $42.10 on doordash.com". Only now does `LAAuthenticationView`'s
  context evaluate. ⌘↩ again only says "Pay with Touch ID"; Esc cancels.
  Opening Pay With or Ship To disarms: Pay is pressed again for what the
  sheet then shows.
- **A finger not known:** the button shakes ±5 pt over 0.36 s and the line
  turns red, "Not recognized. Try again, or press Cancel." After three, or
  when the sensor locks, the button is Use Password, which opens the Mac's
  password dialog. A Mac without Touch ID goes from Pay straight to that
  dialog.
- **Paying, Paid, declined:** Paying with an arc and "Paying on the site";
  Paid in green with the order on the line, 1.4 s, then the sheet goes. A
  decline turns the card row and the line red and the button is Pay again.
- A yes given on another device (`paidElsewhere`) needs no press: the
  sheet goes to Paying from whatever it shows.

The bench verb `agent-pay` drives it (`press` is a click on the button,
`touch` a stood-in finger, heard only while armed); `evals/pay-sheet/check.py`
pictures every state.

## Edge cases

- **Focus and Do Not Disturb.** Until the profile carries Time Sensitive
  (Finding you), the notification is quiet; the corner and the iPhone say it.
- **Chat stopped or closed.** `leave` clears `root.permit` and its
  notification. `leave` and `stop` walk every tab of every window
  (`Agents.windowTabs`), parked ones included.
- **Subagent.** Its question goes up to the root chat (`root(of:)`).
- **Bypass.** `mailRead` and `mailSite` are asked in every mode; `mailChange`
  is skipped in Bypass.
- **Other devices.** Mail read, change and site questions travel through sealed Sync as `chat:<root id>`,
  without borrowing a tab. Their lines name the chat and say “once for this chat”,
  without a mail subject or search text. An answer on any device settles the
  root chat and clears its Mac notification. Opening the question on the Mac
  marks it `seen`: the iPhone notification goes, while its card stays answerable.

## Testing

- `Tests/FastTests/ChatAskPlaceTests.swift`: X in front, a chat's
  `mail_search` leaves X with no permit, guest, handoff, unread or answer;
  the notification's category and ids; a button answers once and a stale key
  does nothing; the call after a yes goes on with another tab in front; Not
  Now is heard once; one question per chat; no permission brings the column
  out once; another app's agent falls back to a faceless card; a send asked
  on your tab doesn't make it a guest; `leave` takes the question away.
  In a test world `AgentNotices` records what it would post (`asked`,
  `cleared`) and takes macOS's answer from `testPermission`.
- `Tests/FastTests/MailConsentTests.swift`: the consent rules themselves,
  now answered on the chat.
- `bench agent-answer` takes `chat` to answer a chat's question as its
  notification's buttons do, in a `--test` run.
- Reporter-profile check, October 20 evening: reused production build
  `d307172748b04728` (`202610201826`), signed with the installed Yab's
  Developer ID, provisioning profile and entitlements. The question appeared
  in its chat column with X in front; switching to another tab kept it;
  Return removed it and resumed one successful search of real profile mail;
  Escape in a new chat delivered Not Now, with no retry. Both Gmail accounts
  report signed out, so online refresh is unverified.
- Live check on main, October 21: a Yab Dev build never granted
  notifications brought the column out with the question in its field
  (the fallback). After f65fe655 the same build's first chat question asked
  macOS for notifications, and with a yes the "Search your mail?" banner
  came, the user at the screen.
- Still owed: the banner's buttons answering from Notification Center,
  Focus behavior, and the column fallback with notifications turned down.
  Notification permissions were not changed. Detailed outcome and reused job
  IDs: `work/session-takeover-20261020/chat-asks-result.json`.
