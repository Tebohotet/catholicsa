# CatholicSA

A directory and companion app for Catholic parishes in South Africa — find a church and its Mass times, read the day's Mass readings, browse hymns, see parish events, and (for parish admins) manage a parish's own information, right from the app.

**Live app:** https://catholicsa.co.za

## The vision

Started as a simple question: on a Sunday, if you've missed Mass at your usual church, can you find the nearest one and actually make it in time? From there it grew into a fuller directory and toolkit for parishes - inspired partly by the Archdiocese of Cape Town's own site (https://adct.org.za/), aiming to do that, modernised, for every parish in the country, and eventually beyond.

What that means in practice, and how much of it exists today:

- **Find a church near you, and know if you'll make it in time** - built. The map shows real GPS pins and each church's upcoming Mass/confession times, with a distance-and-travel-time estimate.
- **Mass times, confession times, readings in different languages, suggested hymns, prayers** - all built, per church.
- **A shop, in case a parish wants to sell something** - built, including order history, refunds, and pickup/courier fulfillment. Real online card payments aren't wired up yet (the config exists; nothing charges a card yet).
- **Priest and clergy info per church, editable by the parish's own admin, not just a developer** - built, including the ability to reassign who the admin is.
- **Other associations/ministries in a church, with a way to support them** - built (donations via bank deposit + proof of upload; direct online payment is the same pending piece as the shop).
- **A map of active churches, with more detail on tap** - built.
- **Comments and ratings per church** - built.
- **Social media links per church** - built (stored links only; actually pulling in or cross-posting content, the way the JW meeting finder (https://hub.jw.org/meetings) does, isn't built).
- **One domain, with a subdomain per church** - not needed yet; revisit if/when it's actually useful.
- **Beyond South Africa** - the data model doesn't hard-code the country, but nothing's been tested or built specifically for another one yet. South Africa first, by design.

See **PROGRESS.md** for the honest, feature-by-feature build status, and **PROJECT_STATUS.md** for what's being worked on right now.

## What it does

- **Map** — find the nearest church or Mass venue, with real GPS pins, Mass times, and confession times.
- **Browse** — look up a parish, diocese, or province directly.
- **Readings** — the day's Mass readings, antiphons, and Prayers of the Faithful, plus a full Douay-Rheims Bible.
- **Hymns** — sheet music and, where converted, an instrumental audio preview, for over 200 Catholic hymns.
- **Events** — upcoming parish events across the country.
- **Shop** — a parish's own small shop (candles, rosaries, and similar), with order and refund handling.
- **Courses** — parish-run courses with lessons and quizzes.
- **Donations** — bank-deposit donations with proof-of-payment upload and admin review.
- **Account** — sign in, and if you administer a parish, manage that parish's churches, Mass times, notices, and more, directly from here.

## For parish admins

If you're a priest or secretary responsible for keeping a parish's information up to date, start here: **[TRAINING_MANUAL.md](TRAINING_MANUAL.md)**.

## Project status

- **[PROJECT_STATUS.md](PROJECT_STATUS.md)** — this project's living memory: what's done, what's waiting on a decision, and what's being worked on next. Read by both the project owner and an automated daily coding run.
- **[PROGRESS.md](PROGRESS.md)** — an honest, feature-by-feature testing checklist: what's built and automated-test-covered, what's built but still needs a real manual click-through, and what's a deliberately deferred gap.

## Tech stack

- **App:** Flutter (web and Windows desktop)
- **Backend:** Firebase — Firestore (database), Authentication, Storage, Cloud Functions, Hosting
- **CI/CD:** GitHub Actions (`.github/workflows/deploy.yml`) — builds, tests, and deploys to Firebase Hosting on every push to `main`

## Running it locally

```
flutter pub get
flutter run
```

Cloud Functions live in `functions/` (Node.js) — see `functions/package.json`. A working Firebase project configuration (`lib/firebase_options.dart` and friends) is required to connect to a real backend; this repo does not include any credentials, by design (see `.gitignore` and the security note in `PROJECT_STATUS.md`'s ground rules).

## Contributing

Changes land on a branch and go through a pull request into `main` — including the automated daily coding run, which never pushes to `main` directly. See the "Ground rules" section at the bottom of `PROJECT_STATUS.md` for the house rules both the project owner and the automation follow.
