# CatholicSA — Project Status

This file is the working memory for the Claude GitHub Actions bot (see
`.github/workflows/claude-daily-coding.yml`), and for anyone picking up
this project cold. The bot reads this file at the start of every run,
works the next unchecked item under "Next up", and updates this file as
part of its own pull request - so this file, not any chat history, is
the actual source of truth on where things stand.

## Done

- [x] Vigil readings display bug fixed (`LiturgicalDay.fromFirestore` now reads the top-level `vigilReadings` field)
- [x] Tap-to-edit + bulk "Add/Edit as List" table editor for readings, built directly into the Readings admin page
- [x] Easter Vigil 2026 fully populated (all 7 OT readings + psalms)
- [x] USCCB citation sync investigated and abandoned - confirmed infrastructure-level 403 blocking, not fixable via headers. cpbjr remains the working citation source.
- [x] Hymn OMR pipeline built: PDF -> Audiveris -> MusicXML -> MIDI -> FluidSynth -> WAV, gated to native Windows builds only
- [x] Windows build fixed (CMake policy version, install-step failure, missing plugin DLL, debug-connection issue - all via `flutter clean` + one CMake line)
- [x] Windows email/password sign-in added, correctly wired through `AuthService` (including `_ensureUserDoc`) with a working "Forgot password?" flow

## In progress / blocked on the project owner

These need a human action before the bot can safely build on top of them - it should not start on "Next up" items that assume these are done until they're checked off.

- [x] **Push the Windows Google Sign-In feature to GitHub.** Confirmed landed on `main` (verified via fresh clone). Still needs a real Desktop OAuth client created in Google Cloud Console and its `clientId`/`clientSecret` pasted into `lib/config/google_desktop_oauth_config.dart` (still placeholders) before sign-in will actually work end-to-end - that one step is still on the project owner.
- [x] **Push the leaked-credential security fix to GitHub.** Confirmed `serviceAccountKey.json` is gone from every ref in the repo's history (verified via `git log --all`, `git rev-list --all --count`, `git for-each-ref` on a fresh clone). `.gitignore` hardened, `seed.js` now loads credentials from environment variables only.
- [x] **Confirm the leaked service account key was actually revoked.** Project owner confirmed it was deleted in Google Cloud Console.
- [ ] **Re-run the Douay-Rheims Bible sync** (Super Admin > Bible Management > "Sync Full Bible") once the psalm-numbering PR is merged and functions are deployed. Needed for Psalm 9 / lectionary Psalm 10 to show correctly - the stored data still has Psalm 10's text over 9:1-18 until then. Left to the project owner since it overwrites live content.

## Next up (worked in order, top to bottom)

- [ ] **Content entry, not code - no bot/automated action here.** Fill in Entrance/Communion Antiphons, Reflection, and "Verse for the Day" for readings. The editing UI for this already exists and fully works: open the Readings admin page, turn on edit mode, pick a date, and each field (Entrance Antiphon, Communion Antiphon, Verse for the Day, Reflection, and now Themed Box too) shows a tappable "+ Add [Label]" box when empty, or an edit-pencil icon when filled - tap it, type the text, Save. There's deliberately no automated/scraped source for this (liturgical text is copyrighted - the abandoned USCCB sync was the same lesson), so this has to be typed in by the project owner, one date and field at a time, directly in the app. Leave this item unchecked (it's never really "done") and skip to the next one below instead of attempting it.
- [x] Add the "+ Add when empty" treatment to the Themed Box field on the Readings admin page, matching the other fields. `themedBoxBody` is now wrapped in the same `_EditableField` component as the other fields (Entrance/Communion Antiphon, Reflection, Verse for the Day) - tap-to-add when empty, tap-to-edit, hide-from-readers toggle. `themedBoxTitle` stays display-only underneath it, same as `reflectionTitle` already does for the Reflection field - there was no existing pattern in this codebase for editing two fields from one tap target, so this matches the established precedent rather than inventing a new one.
- [x] Investigate the flagged psalm verse-numbering issue. Verified against the real Gutenberg #8300 text and real cpbjr citations (which use Hebrew/NABRE numbering, e.g. Holy Thursday "Psalm 116:12-13..."). Findings: (1) the general "superscription counted as verse 1" worry does **not** apply - NABRE also counts superscriptions as verses, so for ordinary psalms only the chapter differs (spot-checked ~20 common responsorial psalms, e.g. 51:3 = DR 50:3 "Have mercy on me"). (2) Real verse-level shifts exist only at the psalms split/merged differently - Hebrew 10 (= DR 9:22+), 115 (= DR 113:9+), 116 (DR 114 for v1-9, 115 for v10-19), 147 (DR 146 for v1-11, 147 for v12-20) - and the old chapter-only mapping got 10, 115, 116:1-9 and 147:12-20 wrong (wrong text or nothing shown; e.g. Corpus Christi's Ps 147:12-20 showed nothing). Fixed with a per-verse mapping in `lib/utils/psalm_numbering.dart` (unit-tested) used by the inline scripture on the Readings page. (3) The sync was also overwriting Psalm 9:1-18 with Hebrew Psalm 10's text, because this edition restarts the second half at "9:1."; `syncFullBible` now stores it at 9:22-39 (its real Douay-Rheims numbering) and no longer lets a duplicated psalm verse number (source typo "5:5." for 6:6) overwrite a real verse. **Psalm 9/10 only show correctly after the Douay-Rheims re-sync listed under "blocked on the project owner".
- [ ] Test the hymn OMR pipeline against one real hymn PDF end-to-end and listen to the actual output - every piece has only been tested against a single-note dummy file so far. Fix whatever the first real run reveals.
- [ ] Support multi-voice MusicXML scores in the hymn converter - only the first `<part>` is currently read.
- [ ] Upgrade Node.js 20 and the `firebase-functions` package in `functions/` to current versions.
- [ ] Replace the placeholder values in `firebase-messaging-sw.js` and the VAPID key.
- [ ] Add the missing Super Admin sections (Countries, Provinces, Audit Log) to the newer hub navigation - they don't have a home there yet.
- [ ] Remove `node_modules/` (root, `functions/`, `firestore-tests/`) from git tracking - currently committed; should be `.gitignore`d and installed via `npm ci` instead.
- [ ] Fix Douay-Rheims Psalms source typos the sync parser can't read (found during the psalm investigation, not yet fixed): verse markers missing the trailing period (`3:2`, `3:3`, `80:10`, `108:16`, `138:8`, `142:4`, `145:1`), `118: 41.`, `142.11.`, and Psalm 6:6 printed as `5:5.`. Each of these verses is currently merged into the verse before it (or dropped). Needs a targeted fix rather than loosening the verse regex for the whole Bible.
- [ ] The tap-through `BibleScreen` (opened from a reading citation) doesn't convert psalm numbers at all - "Psalm 51" opens Douay-Rheims Psalm 51, the wrong psalm. The inline scripture on the Readings page is correct; reuse `PsalmNumbering` there (note `BibleScreen` supports multiple translations, so the conversion should only apply to Vulgate-numbered ones).

## Ground rules for the bot

- Always work on a branch, always open a PR. Never push to `main` directly.
- Never open, read, or print the contents of any credential or secret file (`serviceAccountKey.json`, `.env`, etc.).
- If a task needs a decision only the project owner can make - a design choice, missing content only they have, a product tradeoff - stop and describe the blocker in the PR or an issue instead of guessing.
- Keep changes scoped to the one item being worked. Don't bundle unrelated fixes into the same PR.
