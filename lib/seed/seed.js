// One-time seed script. Run with: node seed.js
// Requires credentials (see loadCredential() below) and national_seed.json
// in the same folder.
//
// npm install firebase-admin  (run this first, once)

const admin = require("firebase-admin");
const seed = require("./national_seed.json");

// ---------------------------------------------------------------------
// Credentials - loaded from the environment, never from a committed file.
// A real Admin SDK key for this project was accidentally committed and
// publicly exposed once already (Google's automated abuse scanner caught
// it) - this rewrite exists specifically so that can't happen again.
// serviceAccountKey.json is .gitignore'd, but the safest fix is to never
// have credentials on a path git is watching in the first place.
//
// Pick ONE of these ways to supply credentials:
//
//   A) GOOGLE_APPLICATION_CREDENTIALS - the standard Google convention.
//      Point it at a local JSON key file, anywhere on disk:
//        export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/key.json
//        node seed.js
//
//   B) FIREBASE_SERVICE_ACCOUNT - the raw JSON key contents, as a single
//      environment variable. Handy for CI, or anywhere dropping a file
//      onto disk isn't convenient:
//        export FIREBASE_SERVICE_ACCOUNT="$(cat key.json)"
//        node seed.js
//
// Generate a key at: Firebase Console > Project Settings > Service
// Accounts > Generate new private key.
// ---------------------------------------------------------------------
function loadCredential() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    let parsed;
    try {
      parsed = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    } catch (e) {
      throw new Error(
        "FIREBASE_SERVICE_ACCOUNT is set but isn't valid JSON: " + e.message
      );
    }
    return admin.credential.cert(parsed);
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    // applicationDefault() reads this env var itself - no need to
    // require() the file path directly.
    return admin.credential.applicationDefault();
  }
  throw new Error(
    "No Firebase credentials found. Set GOOGLE_APPLICATION_CREDENTIALS to " +
    "the path of a service account key file, or FIREBASE_SERVICE_ACCOUNT " +
    "to its JSON contents - see the comment above loadCredential() in " +
    "this file for both options. Never commit a key file to git."
  );
}

admin.initializeApp({ credential: loadCredential() });
const db = admin.firestore();

async function run() {
  console.log("Seeding provinces...");
  for (const p of seed.provinces) {
    await db.collection("provinces").doc(p.id).set({
      name: p.name,
      bounds: p.bounds,
    });
  }

  console.log("Seeding dioceses...");
  for (const d of seed.dioceses) {
    const { id, ...fields } = d;
    await db.collection("dioceses").doc(id).set(fields);
  }

  console.log("Seeding parishes...");
  for (const p of seed.parishes) {
    const { id, priests, ...fields } = p;
    await db.collection("parishes").doc(id).set(fields);

    if (priests) {
      // Clear existing first so re-running this script doesn't duplicate.
      const existingPriests = await db.collection("parishes").doc(id).collection("priests").get();
      const clearBatch = db.batch();
      existingPriests.forEach((d) => clearBatch.delete(d.ref));
      await clearBatch.commit();

      for (const priest of priests) {
        const priestId = priest.name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
        await db.collection("parishes").doc(id).collection("priests").doc(priestId).set(priest);
      }
    }
  }

  console.log("Seeding churches...");
  const churchToParish = {};
  for (const c of seed.churches) {
    const { id, parishId, lat, lng, ...fields } = c;
    churchToParish[id] = parishId;
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(id)
      .set({
        ...fields,
        parishId,
        geopoint: new admin.firestore.GeoPoint(lat, lng),
      });
  }

  console.log("Seeding services (this week's Mass/Communion schedule)...");
  const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // First, clear any old service documents so stale dates don't linger
  for (const churchId of Object.keys(churchToParish)) {
    const parishId = churchToParish[churchId];
    const existing = await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(churchId)
      .collection("services").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }

  // Expand each weekday-based template entry into real dates for the next
  // 14 days, so the app always has a believable "upcoming week" to show
  // regardless of when this script is actually run.
  for (const s of seed.services) {
    const parishId = churchToParish[s.churchId];
    const targetWeekday = WEEKDAYS.indexOf(s.dayOfWeek);
    for (let offset = 0; offset < 14; offset++) {
      const d = new Date(today);
      d.setDate(d.getDate() + offset);
      if (d.getDay() !== targetWeekday) continue;
      const dateStr = d.toISOString().slice(0, 10);
      const docId = `${dateStr}_${s.time}`;
      await db
        .collection("parishes").doc(parishId)
        .collection("churches").doc(s.churchId)
        .collection("services").doc(docId)
        .set({
          date: admin.firestore.Timestamp.fromDate(d),
          time: s.time,
          type: s.type,
          language: s.language || "EN",
          notes: s.notes || null,
        });
    }
  }

  console.log("Seeding confession times...");
  for (const churchId of Object.keys(churchToParish)) {
    const parishId = churchToParish[churchId];
    const existing = await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(churchId)
      .collection("confessionTimes").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const c of seed.confessionTimes) {
    const parishId = churchToParish[c.churchId];
    const docId = `${c.dayOfWeek}_${c.startTime}`;
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(c.churchId)
      .collection("confessionTimes").doc(docId)
      .set({
        dayOfWeek: c.dayOfWeek,
        startTime: c.startTime,
        endTime: c.endTime,
      });
  }

  console.log("Seeding devotions...");
  for (const churchId of Object.keys(churchToParish)) {
    const parishId = churchToParish[churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(churchId).collection("devotions").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const d of seed.devotions || []) {
    const parishId = churchToParish[d.churchId];
    const docId = `${d.dayOfWeek}_${d.time}`;
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(d.churchId)
      .collection("devotions").doc(docId)
      .set({ name: d.name, dayOfWeek: d.dayOfWeek, time: d.time });
  }

  console.log("Seeding parish-wide associations...");
  for (const parishId of new Set(Object.values(churchToParish))) {
    const existing = await db.collection("parishes").doc(parishId).collection("associations").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const a of seed.parishAssociations || []) {
    const docId = a.name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    await db
      .collection("parishes").doc("st-jude-parish") // TODO: generalise once more than one parish exists
      .collection("associations").doc(docId)
      .set({
        name: a.name,
        purpose: a.purpose || null,
        contactPerson: a.contactPerson || null,
        meetingDay: a.meetingDay || null,
        meetingTime: a.meetingTime || null,
      });
  }

  console.log("Seeding church-specific associations...");
  for (const churchId of Object.keys(churchToParish)) {
    const parishId = churchToParish[churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(churchId).collection("associations").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const a of seed.associations || []) {
    const parishId = churchToParish[a.churchId];
    const docId = a.name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(a.churchId)
      .collection("associations").doc(docId)
      .set({
        name: a.name,
        purpose: a.purpose || null,
        contactPerson: a.contactPerson || null,
        meetingDay: a.meetingDay || null,
        meetingTime: a.meetingTime || null,
      });
  }

  console.log("Seeding sample comments...");
  for (const c of seed.comments || []) {
    const parishId = churchToParish[c.churchId];
    const commentsRef = db.collection("parishes").doc(parishId).collection("churches").doc(c.churchId).collection("comments");
    // Only clear previously seeded comments (userId == null) so re-running
    // this script never deletes a real signed-in user's comment.
    const existing = await commentsRef.where("userId", "==", null).get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const c of seed.comments || []) {
    const parishId = churchToParish[c.churchId];
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(c.churchId)
      .collection("comments")
      .add({
        userId: null,
        userDisplayName: c.userDisplayName,
        rating: c.rating,
        text: c.text,
        reply: c.reply || null,
        createdAt: admin.firestore.Timestamp.now(),
      });
  }

  console.log("Seeding events...");
  for (const churchId of Object.keys(churchToParish)) {
    const parishId = churchToParish[churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(churchId).collection("events").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const e of seed.events || []) {
    const parishId = churchToParish[e.churchId];
    const [year, month, day] = e.date.split("-").map(Number);
    const docId = `${e.date}_${e.title.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`;
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(e.churchId)
      .collection("events").doc(docId)
      .set({
        title: e.title,
        description: e.description,
        date: admin.firestore.Timestamp.fromDate(new Date(year, month - 1, day)),
        time: e.time,
        category: e.category || null,
        showInNotices: e.showInNotices || false,
      });
  }

  console.log("Seeding notices...");
  for (const churchId of Object.keys(churchToParish)) {
    const parishId = churchToParish[churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(churchId).collection("notices").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const n of seed.notices || []) {
    const parishId = churchToParish[n.churchId];
    const docId = n.title.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(n.churchId)
      .collection("notices").doc(docId)
      .set({ title: n.title, body: n.body });
  }

  console.log("Seeding safeguarding policy...");
  if (seed.safeguardingPolicy) {
    await db
      .collection("parishes").doc("st-jude-parish")
      .collection("policies").doc("safeguarding")
      .set({ body: seed.safeguardingPolicy });
  }

  console.log("Seeding Bible passages (public domain Douay-Rheims)...");
  for (const [id, passage] of Object.entries(seed.biblePassages || {})) {
    await db.collection("biblePassages").doc(id).set(passage);
  }

  console.log("Seeding curated saint profiles...");
  for (const s of seed.saints || []) {
    await db.collection("saints").doc(s.id).set({
      name: s.name,
      matchPhrase: s.matchPhrase,
      feastMonthDay: s.feastMonthDay,
      feastDay: s.feastDay,
      bio: s.bio,
      patronage: s.patronage,
      medals: s.medals,
      imageUrl: s.imageUrl || null,
    });
  }

  console.log("Seeding prayers...");
  for (const churchId of Object.keys(churchToParish)) {
    const parishId = churchToParish[churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(churchId).collection("prayers").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
  }
  for (const p of seed.prayers || []) {
    const parishId = churchToParish[p.churchId];
    const docId = p.title.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(p.churchId)
      .collection("prayers").doc(docId)
      .set({ title: p.title, text: p.text, language: p.language });
  }

  console.log("Seeding liturgical readings...");
  for (const r of seed.liturgicalReadings || []) {
    await db.collection("liturgicalReadings").doc(r.date).set({
      liturgicalTitle: r.liturgicalTitle,
      readings: r.readings,
    });
  }

  // ---------- Demo/Training environment content ----------
  // These 5 collections don't have a generic per-church loop above (unlike
  // services/notices/prayers/etc, which any church can already use), so
  // they're written directly here, scoped only to demo-church. As new
  // features get added to the app going forward, add their demo content
  // here too - this keeps the training environment comprehensive without
  // needing a separate maintenance process.
  console.log("Seeding demo confession booking request...");
  if (seed.demoConfessionBooking) {
    const b = seed.demoConfessionBooking;
    const parishId = churchToParish[b.churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(b.churchId).collection("confessionBookingRequests").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
    await db.collection("parishes").doc(parishId).collection("churches").doc(b.churchId).collection("confessionBookingRequests").add({
      userId: null, name: b.name, contactPhone: b.contactPhone, contactEmail: b.contactEmail,
      availability: b.availability, status: b.status, createdAt: admin.firestore.Timestamp.now(),
    });
  }

  console.log("Seeding demo report...");
  if (seed.demoReport) {
    const r = seed.demoReport;
    const parishId = churchToParish[r.churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(r.churchId).collection("reports").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
    await db.collection("parishes").doc(parishId).collection("churches").doc(r.churchId).collection("reports").add({
      text: r.text, userId: null, status: r.status, createdAt: admin.firestore.Timestamp.now(),
    });
  }

  console.log("Seeding demo fundraiser...");
  if (seed.demoFundraiser) {
    const f = seed.demoFundraiser;
    const parishId = churchToParish[f.churchId];
    await db.collection("parishes").doc(parishId).collection("churches").doc(f.churchId).collection("fundraisers").doc("demo-fundraiser").set({
      title: f.title, goalAmount: f.goalAmount, raisedAmount: f.raisedAmount, currency: f.currency, active: f.active,
    });
  }

  console.log("Seeding demo pending media...");
  if (seed.demoMedia) {
    const m = seed.demoMedia;
    const parishId = churchToParish[m.churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(m.churchId).collection("media").get();
    const clearBatch = db.batch();
    existing.forEach((d) => clearBatch.delete(d.ref));
    await clearBatch.commit();
    await db.collection("parishes").doc(parishId).collection("churches").doc(m.churchId).collection("media").add({
      kind: m.kind, url: m.url, caption: m.caption, uploadedBy: null, uploadedByName: m.uploadedByName,
      uploadedAt: admin.firestore.Timestamp.now(), status: m.status,
    });
  }

  console.log("Seeding demo courses + lessons...");
  for (const churchId of ["demo-church"]) {
    const parishId = churchToParish[churchId];
    const existing = await db.collection("parishes").doc(parishId).collection("churches").doc(churchId).collection("courses").get();
    for (const courseDoc of existing.docs) {
      const lessons = await courseDoc.ref.collection("lessons").get();
      const clearBatch = db.batch();
      lessons.forEach((d) => clearBatch.delete(d.ref));
      clearBatch.delete(courseDoc.ref);
      await clearBatch.commit();
    }
  }
  for (const c of seed.demoCourses || []) {
    const parishId = churchToParish[c.churchId];
    const courseRef = await db.collection("parishes").doc(parishId).collection("churches").doc(c.churchId).collection("courses").add({
      title: c.title, description: c.description, catechistName: c.catechistName,
      meetingLink: null, status: c.status, createdBy: null, createdAt: admin.firestore.Timestamp.now(),
    });
    for (const lesson of c.lessons || []) {
      await courseRef.collection("lessons").add({ title: lesson.title, content: lesson.content, order: lesson.order });
    }
  }

  console.log("Done! All seed data written to Firestore.");
}

run().catch((err) => {
  console.error("Seed script failed:", err);
  process.exit(1);
});
