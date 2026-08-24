# Firestore Rules Tests

**Start at `../PROGRESS.md` first** - it has the full priority order for
testing this project, of which running this suite is step 2. Coming here
directly still works, but that file is the actual starting point.

Tests the security rules directly - the Developer/Super Admin hierarchy,
the catechist/trusted-seller application approval/escalation flow, course
review enrollment enforcement, the quiz answer-key split, and marketplace
refund amount verification. All five were reasoned through by hand at
some point and caught a real bug along the way - these tests exist so a
future rules change can't silently reintroduce any of them without a
test failing.

## One-time setup

```bash
cd firestore-tests
npm install
```

This project's `firebase.json` needs an emulator config for the Firestore
emulator. If it doesn't already have one, add this (merge into the
existing file rather than overwrite it - `firebase.json` has other real
config for hosting/functions):

```json
{
  "emulators": {
    "firestore": {
      "port": 8080
    }
  }
}
```

If Firebase CLI's emulator hasn't been used before, it needs a one-time
download:

```bash
firebase setup:emulators:firestore
```

## Running the tests

```bash
cd firestore-tests
npm test
```

This spins up a real (local, temporary) Firestore emulator, loads the
actual `firestore.rules` file, runs every test against it, then tears the
emulator down. Nothing here touches the real Firestore project - it's
fully local and safe to run as often as needed.

## What's covered

- A plain signed-in user cannot grant themselves Super Admin or Developer
- A Super Admin who is *not* a Developer cannot grant Developer status to
  anyone else (the exact bug caught while building this) - but can still
  edit other unrelated fields on a user
- A Developer can grant both Super Admin and Developer status
- A parish priest can approve a parish-level catechist application for
  *their own* parish - not for a different parish, not a national-level one
- Only a Super Admin (or Developer) can approve a national-level application
- A user can create their own application, but not one claiming to be
  someone else
- A signed-in but NOT enrolled user cannot write a course review (this
  was a real gap - the enrollment check originally only existed in the
  Dart app code, which a direct Firestore write could have bypassed)
- An enrolled user can write their own review, but not one claiming to
  be someone else
- A student can never read a quiz's answer key, only the questions -
  an admin can read both
- A student can submit raw quiz answers, but can never self-report
  score/passed on create or update - only the grading Cloud Function
  (via Admin SDK, bypassing rules entirely) ever sets those fields
- A student can't submit a quiz attempt claiming to be someone else
- A buyer can request a refund with the correctly-computed amount, but
  not more than their policy entitles them to (verified against the
  order's own immutable data) - and still can't approve their own request

## What's not covered yet

This only tests the five systems built across these sessions. The rest of
`firestore.rules` (churches, courses, marketplace, donations, etc.) has
been verified by hand throughout, but doesn't have automated tests. Worth
extending the same way if those areas keep changing.
