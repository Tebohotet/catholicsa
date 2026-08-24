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

- [ ] **Push the Windows Google Sign-In feature to GitHub.** The code (`google_sign_in_all_platforms` integration, `lib/config/google_desktop_oauth_config.dart`, changes to `auth_service.dart`, `account_screen.dart`, `pubspec.yaml`) exists only on the project owner's local machine as of the last check - never committed or pushed. Also needs a real Desktop OAuth client created in Google Cloud Console (see the setup comment at the top of `google_desktop_oauth_config.dart`) before sign-in will actually work.
- [ ] **Push the leaked-credential security fix to GitHub.** `lib/seed/serviceAccountKey.json` was found publicly exposed (flagged by Google's abuse scanner) and is still tracked in the public repo's git history as of the last check. The fix - amended commit removing it, updated `.gitignore`, env-based credential loading in `seed.js`, plus `seed-firestore.yml` - exists locally but hasn't been pushed.
- [ ] **Confirm the leaked service account key was actually revoked** in Google Cloud Console (IAM & Admin > Service Accounts > `firebase-adminsdk-fbsvc@catholicsa-61b87.iam.gserviceaccount.com` > key ID `aba6afdf...bc01` > Delete). This matters more than the git history cleanup - the key itself has to be killed regardless of what git shows.

## Next up (worked in order, top to bottom)

- [ ] Fill in Entrance/Communion Antiphons, Reflection, and "Verse for the Day" for readings - empty for almost every date, no automated source found so far. Needs either a real source or a defined manual-entry process.
- [ ] Add the "+ Add when empty" treatment to the Themed Box field on the Readings admin page, matching the other fields.
- [ ] Investigate the flagged psalm verse-numbering issue: chapter-level Vulgate/modern offset is handled, but some individual psalms may have a further verse-level shift (superscription counted as verse 1).
- [ ] Test the hymn OMR pipeline against one real hymn PDF end-to-end and listen to the actual output - every piece has only been tested against a single-note dummy file so far. Fix whatever the first real run reveals.
- [ ] Support multi-voice MusicXML scores in the hymn converter - only the first `<part>` is currently read.
- [ ] Upgrade Node.js 20 and the `firebase-functions` package in `functions/` to current versions.
- [ ] Replace the placeholder values in `firebase-messaging-sw.js` and the VAPID key.
- [ ] Add the missing Super Admin sections (Countries, Provinces, Audit Log) to the newer hub navigation - they don't have a home there yet.
- [ ] Remove `node_modules/` (root, `functions/`, `firestore-tests/`) from git tracking - currently committed; should be `.gitignore`d and installed via `npm ci` instead.

## Ground rules for the bot

- Always work on a branch, always open a PR. Never push to `main` directly.
- Never open, read, or print the contents of any credential or secret file (`serviceAccountKey.json`, `.env`, etc.).
- If a task needs a decision only the project owner can make - a design choice, missing content only they have, a product tradeoff - stop and describe the blocker in the PR or an issue instead of guessing.
- Keep changes scoped to the one item being worked. Don't bundle unrelated fixes into the same PR.
