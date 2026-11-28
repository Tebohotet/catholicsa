# CatholicSA — Progress & Testing Checklist

This is the honest source of truth for "is this chapter actually done."
Every item below reflects real code that's been bracket-checked and,
where automated tests exist, verified against them - but **manual testing
in the real app is still the only way to know something genuinely works
end to end**, and that hasn't happened yet for most of this. Nothing here
should be read as "confirmed working" until you've personally checked it.

Status key: ✅ Built + has an automated test · 🟡 Built, needs manual testing · ⚠️ Known gap, deliberately deferred

---

## Test This First — foundational, everything else depends on these

Do these in order. If any of these are broken, nothing built on top of
them can be trusted, no matter what its own checklist item says.

1. **Deploy rules and functions**
   ```
   firebase deploy --only firestore:rules,storage,functions
   ```
2. **Run the automated rules tests** - this is real, working proof of the
   security model, not just something I reasoned through by hand:
   ```
   cd firestore-tests && npm install && npm test
   ```
   All tests should pass. If any fail, stop here - fix that before testing
   anything downstream of it.
3. **Run the Flutter test suite**:
   ```
   flutter test
   ```
4. **Bootstrap your own account** (one-time, manual, can't be automated):
   sign in once with the account you'll use for testing, then in Firestore
   Console set `isDeveloper: true` on your own `users/{uid}` doc. Confirm
   the Developer tools appear in Super Admin Panel.
5. **Confirm basic navigation works**: open the app, land on Home, tap
   through Browse → a province → a diocese → a parish → a church, back out
   cleanly each time.

If all five of these pass, the foundation is sound and the checklist
below is meaningful. If any of them don't, everything below is untested
by definition, regardless of what its own status says.

---

## Church Directory

- ✅ Province → Diocese → Parish → Church hierarchy, each level rolling up
  Notices/Prayers/Courses/Gallery/Marketplace from everything beneath it
- 🟡 Church detail page - all 10 sections (Horarium, Confessions, Mass
  Intentions, Devotions, Clergy, Associations, Photos, Finances, Comments,
  Parochial Notice). **Code-level audit complete, zero bugs found**: every
  import resolves, every section's constructor call matches its actual
  declaration, and every write/read path pair was traced end to end
  (confession booking submit → admin list, Mass Intention submit → admin
  list, Associations merge scope, Finance toggle field write → display
  read, Comment reply write → display read, Notices+Events merge). What
  this can't confirm: actual rendering, tap targets, or real-device
  behaviour - that's still a genuine manual click-through, not a
  formality.
- ✅ Offline liturgical calendar (season/week/Sunday cycle/weekday cycle) -
  has real unit tests against known Easter/Advent dates and a full-year
  sweep
- ✅ Daily readings + Bible passage tie-in - genuinely tiny real coverage
  (4 citations, 1 day). **Code-level audit was clean, but real device
  testing found a genuine bug the code review missed**: `AsyncSnapshot.
  hasData` is false whenever a Future resolves to `null` - not just while
  still loading - which is exactly what `getLiturgicalDay` does for any
  unseeded date. That made "still loading" and "loaded, found nothing"
  indistinguishable, so Readings looked permanently stuck for every date
  except the one with real content. Found via a purpose-built diagnostic
  page (`our_item_page.dart`, isolating each async call independently)
  after several turns of me suspecting the wrong things - network, rules,
  an external API, the calendar algorithm. Fixed by checking
  `connectionState` instead of `hasData`. The same exact bug pattern was
  then found and fixed in two more places by deliberately sweeping every
  `hasData` usage in the app rather than assuming this was isolated:
  `bible_screen.dart` and `server_driven_page_screen.dart`. **The honest
  lesson this confirms**: a "zero bugs found" code-level audit is real
  signal, not nothing, but it is not a substitute for actually running
  the app - this is the case where that caveat, attached to every audit
  in this document, turned out to matter in practice, not just as a
  hedge.
- ⚠️ Search only does substring matching after a full collectionGroup
  fetch - fine at current scale, not built to scale further
- 🟡 **Province-level hide/show, added 2026-11-28** - same hide switch
  already used for Church/Parish, now extended one level up. A new eye
  icon on each province row in Super Admin -> Directory -> Provinces
  hides it from Browse for ordinary viewers (admins still see
  everything, same rule as Parish). Not yet tried live.
- 🟡 **Real pre-existing bug fixed, same night: hiding a church or
  parish did not actually hide its notices/prayers/courses/photos/
  marketplace listings from the Diocese/Province/National rollups
  above it** - confirmed by reading every rollup method, none filtered
  by the hide switch at all. Fixed everywhere at once rather than one
  rollup at a time. Not yet tried live.
- 🟡 **Tap-through added to Notices and Prayers**, added 2026-11-28 -
  these were the only two summary types anywhere in the app with no
  tap target; tapping one now opens the church it belongs to, same as
  Courses/Marketplace already did. Not yet tried live.

## Courses

- ✅ Course + Lesson creation, review workflow (draft → pending → published).
  **Code-level audit complete - found and fixed a real security gap**: the
  UI restricted "Approve & Publish" and "Send Back" to priests, but the
  security rule didn't enforce this at all - any parish admin, including a
  secretary, could have published a course directly via Firestore, bypassing
  the entire review workflow the feature exists for. Fixed the rule so only
  a priest can move a course away from `pendingReview`, while a secretary
  can still freely create, edit, and submit courses for review. Added 6
  tests covering it. Also confirmed: student-facing screens (course list,
  all 4 hierarchy rollups) consistently filter to published-only - traced
  every call site, no gaps found there.
- ✅ Lesson-level verification checkbox
- ✅ Course reviews - enrollment is enforced at the **rules level**, not
  just app code (caught and fixed a real bypass here) - has a test
- ✅ Sort by Latest / Top Rated on the course list screen. **Code-level
  audit complete**: manually traced the Top Rated comparator through
  several null/non-null combinations to confirm it's a valid, transitive
  ordering (Dart's sort requires this to behave correctly, not just "not
  crash"). Found a minor inconsistency in the Latest comparator - it
  returned "equal" for a missing `createdAt` instead of deterministically
  sorting it to one end, unlike the Top Rated branch's correct handling of
  missing ratings. Traced both course-creation paths (the real admin flow
  and the demo seed) and confirmed `createdAt` is always actually written
  today, so this wasn't an active bug - fixed anyway for consistency,
  since the correct pattern was already sitting right next to it. Also
  confirmed sorting re-computes client-side on tap rather than
  re-fetching from Firestore each time.
- ✅ Quiz/assessment feature - multiple choice, drag-and-drop, randomized
  question pools, and real branching (correct/wrong answer leads to a
  specific next question). Gates lesson completion: grading is
  server-authoritative (a Cloud Function, `gradeQuizAttempt`), and the
  answer key lives in a document students can never read through any
  path - both enforced at the rules level with real tests, not just the
  app code. Branching works without exposing the answer key in bulk via
  a second, narrow callable (`checkQuizAnswer`) that returns only
  correct/incorrect for one question at a time.
  **Two real bugs caught mid-build**: drag-and-drop items were
  displaying in their already-correct order, making the question
  trivially pre-solved - fixed by shuffling the display order. And a
  rules test used `getDoc` without it being imported - would have passed
  `node -c` syntax checking but thrown `ReferenceError` the moment the
  test suite actually ran; caught by tracing every identifier against
  the import list before calling it done.
  Honest, stated limitation: branching's live per-question check happens
  client-initiated, so a determined student could in theory pick a
  favourable question subset before final submission - proportionate for
  a parish course quiz, not exam-grade tamper-proof, and said so in the
  code itself rather than glossed over.
- 🟡 **Hide/manage a single course, added 2026-11-28** - the project
  owner's own ask: "Be able to hide, the Course for this page, like
  manage this course if you are an admin." A new "Visible to the
  public" switch on the course detail page, for anyone who can manage
  that course's parish - a separate switch from the existing draft/
  pending-review/published workflow above, so hiding a published
  course doesn't send it back for review. Needed no `firestore.rules`
  change (confirmed: the existing rule already lets any parish admin
  change a course's non-status fields). Not yet tried live.

## Marketplace

- ✅ Listing creation with photo upload, Buy flow, coupons (parish-wide
  and seller-scoped), refund requests. **Code-level audit complete -
  found and fixed a real, currently-active bug**: the security rule
  permitted a buyer to change exactly 3 fields when requesting a refund
  (`refundStatus`, `refundReason`, `refundRequestedAt`), but the Dart
  code also writes a 4th field, `refundAmount`, in the same update. That
  field was never in the rule's allowlist - meaning **every real refund
  request would have been rejected with permission-denied**, silently,
  the first time a real user ever tried to use this feature. Fixed by
  adding `refundAmount` to the allowed fields *and* verifying server-side
  that the submitted amount actually matches the order's own immutable
  `finalAmount`/`refundPercent` - a buyer can't request more than their
  policy entitles them to, not just "some amount was allowed through."
  Also traced and confirmed clean: listing creation's two-step
  create-then-upload-image flow, both coupon scopes writing and being
  checked consistently, the proof-of-payment field match, and the
  seller's fulfillment-update field match. Three tests added for the
  refund fix specifically.
- ✅ Pickup vs Courier fulfillment, self-courier delivery tracking log
  with photo proof at each step. **Code-level audit complete - found and
  fixed two real gaps**, both in the app layer rather than security
  rules (the rules were already correctly permissive for both cases):
  (1) `fulfillmentStatus` was written by admin ("Mark Ready for Pickup",
  "Mark Dispatched") but **never displayed anywhere the buyer could see
  it** - traced every field `my_orders_screen.dart` actually reads and
  confirmed `fulfillmentStatus`, `fulfillmentMethod`, and
  `deliveryAddress` were all absent. The admin's status button had no
  visible effect on the buyer's own order screen. Fixed by adding the
  display, using the exact same status wording already established in
  the admin panel. (2) A self-couriering seller could only post free-text
  log notes - there was no button for them to set the actual
  authoritative status themselves, even though they're the one doing the
  delivery; only the parish admin (uninvolved in a self-courier delivery)
  could. Fixed by adding Mark Dispatched/Mark Delivered to My Sales,
  reusing the existing `updateOrderFulfillmentStatus` method as-is - the
  rule already permitted this, it just had no UI entry point.
- ✅ Product/course/church search
- ⚠️ No real online checkout (PayFast/PayStack/PayPal config exists,
  nothing actually charges a card yet) - deliberate, pending sandbox access
- ⚠️ No escrow - deliberate, pending a real legal answer

## Donations

- ✅ Bank deposit flow, proof of payment upload (image or PDF).
  **Code-level audit complete, zero bugs found**: traced the create rule
  (permissive, only checks `donorId`), the narrow donor-update rule field
  match (`uploadDonationProof` writes exactly the 3 fields the rule
  permits, no more), the storage path against `storage.rules` (exact
  match), and the dialog's ID-threading between `createDonation` and
  `uploadDonationProof` (correctly captured and passed). This is the same
  class of field-mismatch check that caught the real bug in marketplace
  refunds - here it came back genuinely clean.
- ✅ Admin's three-way outcome: Approve / Wrong Bank / Reject.
  **Code-level audit complete - found and fixed two real gaps**: (1) the
  exact status strings the admin buttons write (`approved`, `wrong_bank`,
  `rejected`) were cross-checked against what the notification Cloud
  Function matches on - genuinely clean, exact match, no silent
  notification failures. (2) There was no donor-facing screen at all -
  same shape as the marketplace fulfillment-status gap found earlier: a
  donor got one push notification and then had nowhere in the app to
  ever see their donation history again. Built `MyDonationsScreen`
  (reusing the exact `getMyOrders` pattern) and wired it into Account.
  Also found the "Reject" button fired with no reason captured at all,
  despite the service method's own doc comment promising the donor sees
  why - "Wrong Bank" already prompted for a note, "Reject" didn't. Added
  a matching dialog so both paths actually deliver what the code already
  claimed to.
- ✅ Direct-to-donor push notification on status change

## Hymns & Built-In PDF Reader

- ✅ Hymn library with PDF source scans, server-side OMR conversion
  (PDF → Audiveris → MusicXML → MIDI → FluidSynth) producing real sung
  audio, repeat/D.C./D.S./Fine/To Coda playback logic, admin "View PDF"
  comparison, and per-church Song Book lookup by hymn number. Built
  across earlier sessions, not touched this pass except where noted
  below.
- 🟡 **Built-in PDF viewer** (`lib/screens/pdf_viewer_screen.dart`,
  `syncfusion_flutter_pdfviewer`), added 2026-11-28 - replaces every
  `url_launcher` PDF hand-off (hymn source PDFs, the Hymns admin "View
  original PDF" button, marketplace/donation "View Proof (PDF)"
  buttons) with a real in-app viewer, with an "open externally"
  fallback if Syncfusion's own renderer can't load a given file.
  **Known, real, not-yet-fixed bug**: opening any PDF currently fails
  with "Couldn't display this PDF here." The first CORS fix narrowed
  this down but didn't close it - checked directly against the live
  site, 2026-11-28: plain and ranged file fetches both now succeed
  (CORS itself is no longer blocking), but the response is still
  missing two specific headers (`Content-Range`, `Accept-Ranges`) the
  PDF viewer needs to figure out how big the document is before it can
  stream it. The `gsutil cors set` command already asks for both of
  those correctly; what's unconfirmed is whether that command actually
  finished last time (its own output got cut off mid-run) - see
  PROJECT_STATUS.md for the exact command to re-run, and what to paste
  back. Everything else about the viewer itself (header, fallback
  button, profile menu) is real and already deployed; this one external
  config step is the only thing standing between it and actually
  displaying a PDF.
- 🟡 **Persistent mini hymn-player bar**, added 2026-11-28 - a hymn now
  keeps playing, and stays controllable (play/pause, stop), on every
  screen in the app, not just the popup it was started from, including
  while the new PDF viewer is open on top of it. Shared, app-wide
  player (`lib/services/hymn_player_service.dart`) replacing what used
  to be a private player living inside the hymn-audio popup alone.
  **Behavior change worth testing specifically**: closing that popup's
  "Close" button no longer stops the song - it keeps playing in the
  mini-player bar below, the same way minimizing a music app's "now
  playing" screen doesn't quit it. Not yet tried live.

## Notifications (FCM)

- ✅ Notice broadcasts and Mass/Event reminders - **rebuilt as a unified
  broadcast system**, replacing what were two separate mechanisms that
  could drift apart. Every broadcast (notice, reminder, or welcome
  message) resolves its audience live at send time from a scope
  (church/parish/province/lesson/person) rather than a stored list -
  this is what makes "don't remind someone who's lost access" automatic
  rather than a check someone has to remember to add. `reminderSent`
  now lives on the broadcast itself, with a `sourceRef` back to the
  Mass time/event it came from - built so a future "edit this Mass
  time" feature can reset a stale reminder by updating one field on one
  document, not hunting through scattered state. Caught and fixed a
  real bug before it shipped: the old `notifyOnNewNotice`/
  `sendUpcomingReminders` functions were still present alongside the
  new ones when I checked the exports list - deploying as-is would have
  sent every notice and reminder twice. Removed the old functions
  entirely (172 lines) rather than leaving them running in parallel.
  Honest scope: email channel and lesson/parish/province-scoped
  broadcasts are built into the mechanism but nothing triggers them
  yet; admin UI for choosing channels/lead-time per notice still uses
  sensible defaults, not yet an admin choice.
- ✅ Donation status → donor (has a real trigger, needs a live device to
  confirm the push actually arrives)
- ✅ Marketplace order status + refund status → buyer (same - trigger is
  real, needs a live device to confirm delivery)
- ✅ Catechist/Trusted Seller application status → applicant

## Roles & Verification

- ✅ Developer > Super Admin > Priest/Secretary hierarchy - has tests
  covering the exact permission bug caught mid-build (a plain Super Admin
  couldn't have been blocked from granting Developer status without this)
- ✅ Catechist applications, parish-level (priest approves) and
  national-level (Super Admin approves) - has tests
- ✅ Trusted Seller applications (same system, different `type`).
  **Code-level audit complete - found and fixed a real cross-contamination
  bug**: `isCatechistVerified` filtered only by `applicantId` and
  `status`, never by `type` - meaning someone with an approved
  *trusted-seller* application but no catechist application at all would
  have incorrectly shown a "verified catechist" tick on a Course page.
  Root cause: `submitCatechistApplication` never wrote a `type` field at
  all (only `submitTrustedSellerApplication` did), so there was nothing
  to filter on. Fixed both sides - the write now sets `type: 'catechist'`
  explicitly, and the read filters on it. Honest note on why this wasn't
  caught by the existing rules test suite: that suite verifies
  *permission boundaries* (who can write what), not *application query
  correctness* (whether a filter selects the right documents) - a
  genuinely different class of bug that needs a different kind of test
  (Dart-side, against a real or mocked Firestore) that doesn't exist yet
  for this app. Also: existing catechist applications submitted before
  this fix have no `type` field and won't match the new filter - a real,
  low-stakes migration gap given there's no production data yet, worth
  knowing before this ships with real users.
- ✅ Verified tick (`VerifiedName`) on Course catechist names and
  Marketplace seller names

## Admin Tooling

- ✅ Admin Panel - Mass Times, Finances, Devotions, Associations,
  Notices, Events, Song Book, Prayers, Courses, Confession Bookings,
  Mass Intention Requests, Reported Issues, Media approval, Comments,
  Marketplace Listings/Orders, Donations, Catechist Applications.
  **Full audit complete across all 17 sections** - several had already
  been through their own dedicated, deeper audits earlier (Courses
  found the priest-only-publish rules gap; Marketplace found the
  refund-amount field mismatch; Donations found the missing
  donor-facing screen and the Reject-with-no-reason gap; Catechist
  Applications found the type-filtering cross-contamination bug - all
  already fixed). This pass covered what was still genuinely unchecked:
  Devotions/Song Book/Prayers (simple CRUD, confirmed symmetric
  read/write paths), Mass Times/Notices/Events (confirmed consistent,
  correctly open to any parish admin, no UI claiming a restriction the
  rules don't back), Confession Bookings/Mass Intention Requests/
  Reported Issues (confirmed correctly open to any admin, matching what
  these routine triage actions actually need), and Media approval
  specifically checked against the exact bug class that broke Courses -
  **and this one is genuinely correct**: the UI's priest-only gate
  (`canApprove: _role == 'priest'`) is properly backed by the rule
  (`isPriestForParish` required to change status; a secretary can edit
  other fields but not approve/reject) - real confirmation the correct
  pattern exists elsewhere in this codebase, not just a lucky absence
  of the bug.
- ✅ Super Admin Panel - Role assignment, Saints database (generic CRUD
  framework), Marketplace fee, Custom Pages/blocks, Design Tokens,
  Branding, National Catechist review. **Full audit complete - found
  and fixed one real, actively misleading bug**: the "Navigation bar
  position" dropdown offered a "Top" option that saved successfully and
  then did absolutely nothing - `HomeScreen`'s navigation is hardcoded
  to the bottom regardless of this setting, so selecting "Top" gave an
  admin false confidence a change had taken effect. This is worse than
  the feature simply not existing, since it actively implies a
  capability that isn't there. Removed the non-functional option rather
  than leave it silently broken, added an honest note that it's planned
  but not yet built, and hardcoded the loaded value to guard against a
  stored 'top' from before this fix crashing the dropdown. Everything
  else checked out genuinely clean: role assignment only offers the
  exact 'priest'/'secretary' strings the rules check for; Saints/
  Marketplace Fee/Custom Pages all use broad Super-Admin-only rules with
  no field-mismatch risk; Custom Pages' block-type dropdown matches
  `BlockRegistry`'s four known types exactly; Design Tokens and
  Branding's written field names (`accentColor`, `cornerRadius`,
  `appName`) match what `app.dart` actually reads, field for field.
  National Catechist review was already covered by the Catechist
  Applications audit earlier (the type-filtering bug, since fixed).
- ✅ Generic CRUD framework (`GenericAdminCrudSection`) - proven on
  Saints, parish-wide coupons, and seller coupons; explicitly **not**
  force-fit onto Courses/Mass Times/user-submitted-content workflows,
  reasoning documented at the time
- 🟡 **Logs page** (Super Admin -> Logs), added 2026-11-28 - the
  project owner's own ask: "I normally use Console.WriteLine in C#...
  Lets have that in our coding so that we just go to the logs and see
  if all went well." Every crash/error - caught automatically via three
  global handlers wired up in `main.dart`, or logged by hand anywhere
  worth tracking via `LogService.log(...)` - writes to a new `appLogs`
  Firestore collection, readable only by Super Admin, but writable by
  anyone signed in or not (most of this app's real traffic is
  signed-out visitors, and a sign-in requirement would miss exactly the
  errors this exists to catch - a deliberate tradeoff, not an
  oversight). Not yet tried live - worth breaking something on purpose
  and confirming it shows up in Super Admin -> Logs.

## Navigation & Header Consistency

- 🟡 **Every page now has the same Hymns/Bible/profile icon row Readings
  already had, added 2026-11-28** - the project owner's own ask: "I need
  the app to be uniform... make it uniform." Covers Browse's own root
  page, Province, Diocese, Parish, Church, and Course pages. Not yet
  tried live.
- 🟡 **Real navigation dead end fixed: tapping "View Hymns" from
  Readings used to push a second copy of the Hymns screen with no back
  button at all** - found from the project owner's own question ("No
  back button on Hymns to reading, or should we remove this?"). Now a
  real tab switch instead, same as tapping the bottom nav directly - no
  back button needed. Hymns' own header got a matching "View Readings"
  icon. Not yet tried live.
- 🟡 **Account/Messages no longer stick around after switching tabs and
  back, added 2026-11-28** - the project owner's own bug report. Normal
  in-page browsing depth (e.g. how far into Browse you'd drilled) is
  untouched; only Account/Messages specifically get closed when you
  switch away from that tab. Not yet tried live.
- 🟡 **Map screen's three buttons now respond to real location
  permission, added 2026-11-28** - granted hides "Use my location"
  (nothing left to ask); denied hides "Hide map"/"Can I make it?" (both
  need a real position to do anything) and leaves only "Use my
  location" so you can still grant it later. **Updated the same
  day**: denying location now also hides the map area itself at the
  bottom of the screen (it used to still show, just with its own
  toggle button hidden) - the project owner's own words: "there is no
  need to show the map at the bottom." Not yet tried live.
- 🟡 **A first-run "look here" tip overlay, added 2026-11-28** - the
  project owner's own ask for something like a short tooltip/onboarding
  tour. Shows once per device, only on the Map screen so far, pointing
  out its own three buttons. **Updated the same day, two fixes from the
  project owner's own screenshot**: (1) a timing bug where the tour
  could show a message for "Use my location" while the highlight box
  had already drifted onto a different, now-visible button - fixed by
  waiting for the location-permission check to actually finish before
  ever starting the tour, so it only ever points at something genuinely
  on screen; (2) the message card itself made smaller ("does it have to
  be that big?") - tighter text/padding/buttons, capped to a narrow
  bubble near the button instead of a full-width banner. Not yet tried
  live - and deliberately not extended to every other screen's new
  icons yet (Account/Browse/Readings/Hymns), a straightforward follow-up
  with the same reusable piece, now sized smaller by default, if
  wanted.

## Platform Infrastructure

- ✅ Server-driven UI / Custom Pages (block registry: text, spacer, share
  button, notes list). **The existing widget test's claims were
  independently verified against the real implementation, not just
  trusted at face value** - every assertion genuinely matches:
  `BlockRegistry.build`'s fallback text
  (`'Unknown block type: "$type"'`) matches the test's
  `find.textContaining`, `availableTypes` genuinely returns all four
  real block keys, and a missing `type` key correctly falls through to
  the same graceful-degradation path as an unrecognised one. Also
  checked `NotesListBlock` specifically since it's flagged as "real
  functionality, not a stub" - `getMyNotes`/`addNote`/`deleteNote` all
  exist with matching signatures, and the rule
  (`users/{uid}/notes/{noteId}`) correctly restricts access to the
  note's own owner. `ServerDrivenPageScreen` correctly maps every block
  in a page through the registry. No gaps found.
- ✅ Design tokens (nav position, corner radius, accent colour) applied
  to the real theme, not just stored. Verified beyond field-name
  matching this time - actually traced how each token affects real
  rendering: `accentColor` feeds `ColorScheme.fromSeed`'s secondary
  color and Material3's derived roles (not a full recolor - `primary`
  is explicitly pinned to the app's stone color regardless of accent,
  which is correct, intentional scope). `cornerRadius` applies to
  `CardTheme` and `FilledButtonThemeData` specifically - genuinely
  applied, but honestly doesn't reach the many hand-styled `Container`s
  with their own hardcoded radii throughout the app, which was already
  a disclosed, intentional scope boundary, not new news. Nav position
  audited and fixed last turn (the non-functional "Top" option).
- ✅ Branding (app name) applied to the real app title. Searched for any
  hardcoded "CatholicSA" that should read from branding instead and
  found none - the only two matches are legitimate fallback defaults
  (the edit form's placeholder, and the Firestore default when no
  branding doc exists yet), not bypasses.
- ✅ Dev flags (off/preview/live) with a real Super Admin UI. Verified
  end to end: the admin dropdown's exact three values match what
  `isFeatureVisible` checks, and `FeatureGate` (the actual gating
  widget) correctly wraps it. Honest finding, not a bug: this is a
  generic, freeform staging tool (admin types any key, e.g.
  "shopOnlineCheckout") built ahead of its first real use - nothing in
  the app currently wraps a screen in `FeatureGate` yet, which is
  expected for infrastructure built in advance of the feature it'll
  eventually gate, not a gap to close now.
- ✅ Onboarding (4 slides, shown once per device via `shared_preferences`).
  Single call site for `setBool('onboarding_seen', true)`, correctly
  placed inside `_finish()` alongside a `pushReplacement` so the back
  button can't return to onboarding after completion. Read side
  (`app.dart`) correctly defaults to `false` or unset - boolean logic
  checked precisely rather than assumed correct.
- ✅ Privacy Policy screen - genuine draft content, explicitly **not**
  legally reviewed, says so in the app itself. Confirmed the actual
  disclaimer text is present and honest ("DRAFT... has not been
  reviewed by an attorney"), and confirmed it's genuinely reachable
  from Settings, not just written and orphaned.

## Structural / Code Quality

- ✅ `church_detail_screen.dart` split from ~2,000 lines into 14 files
- ✅ Riverpod - two real uses (auth state, design tokens/branding),
  deliberately not a blanket rewrite
- ✅ Test infrastructure exists for both layers: `flutter test` (Dart) and
  `firestore-tests/` (security rules, via emulator) - **all 32 rules
  tests passing**. The failures along the way were a real bug in
  `@firebase/rules-unit-testing@3.0.4` + `firebase@10.14.1`'s
  interaction with the Firestore SDK ("Firestore has already been
  started" on roughly half the tests, completely unmoved by three
  different structural fixes to the test code and config) - resolved by
  upgrading both packages to `latest` (landed on `firebase@12.17.0`).
  Worth remembering if this recurs after a future `npm install`: it's a
  known class of SDK-version bug, not a rules problem - the emulator's
  own logs showed the rules correctly rejecting every disallowed
  operation throughout, even while the JS test client couldn't complete
  the assertion.

---

## Honest gaps, not forgotten, just not yet built

- Privacy Policy needs actual legal review before being relied on
- POPIA Information Officer still needs to be designated (a real
  organisational step, not a code change)
- Video files open externally, not played in-app (`video_player` package
  not added yet)
- No search-as-you-type or fuzzy matching - exact substring only
- No CI/CD - tests have to be run manually, nothing runs them on push
- **Firebase Storage bucket's CORS configuration is still incomplete**,
  found 2026-11-28, re-checked live the same day after the project
  owner ran the first fix - basic file reads now work, but the specific
  `Content-Range`/`Accept-Ranges` response headers the PDF viewer needs
  still aren't coming through, and a separate background audio fetch is
  also still blocked. Same one `gsutil cors set` command as before
  (already asks for the right headers) - needs the project owner's own
  Google Cloud login to re-run it and let it fully finish this time (see
  PROJECT_STATUS.md for the exact command and what to paste back) -
  nothing left here for the bot to do until that's confirmed done.
- 🟡 **No URL-synced routing - Phase 1 fixed, same night, not yet tried
  live.** Was: a browser refresh always reloaded the landing/About Us
  page instead of wherever you actually were. Flagged by the project
  owner directly ("I need refresh to keep in hymns... no start over
  from about us"), who then said "Yes, start it now" when asked about
  the go_router migration this needs. Now: refreshing on any of the 4
  bottom-nav tabs, or on the Hymns tab's PDF viewer, reloads exactly
  that - not About Us. Church share-links/QR codes keep working
  unchanged. **Not done yet**: anything pushed *on top of* a tab
  (Browse -> a parish/church, Admin Panel, Account, Messages, and
  dozens more) still resets to that tab's own root on refresh, not the
  exact screen - a smaller, remaining version of the same limitation,
  left for a future pass. **Caught 2 real compile errors from this
  pass via a pasted `flutter analyze` output** (a missing `go_router`
  import, and an old test still using the renamed `onContinue`
  parameter) - both fixed; everything else in that output was the
  usual harmless deprecation noise. Still needs a real `flutter pub
  get && flutter analyze` + a live test pass before fully trusting
  this - a clean analyze only rules out compile errors, not whether
  navigation actually behaves right on a real device.
- 🟡 **"Every page needs a profile/messages/login-logout icon" - only
  partly swept, added 2026-11-28.** Fixed the two screens the project
  owner's own screenshots showed missing it (Course detail, Parish
  detail) - not a full audit of every remaining screen in the app.
  Earlier sweeps already covered 14+ screens sharing one exact header
  shape (see PROJECT_STATUS.md); if it's still missing somewhere else,
  that's a real, separate gap worth a full pass, not assumed fixed
  everywhere just because it's fixed in a lot of places now.
