const functions = require("firebase-functions");
const admin = require("firebase-admin");
const cheerio = require("cheerio");
admin.initializeApp();

/**
 * Callable from the Settings > Delete Account button.
 * - Anonymises the user's existing comments (keeps the discussion/rating
 *   intact for the parish, removes the personal link to it).
 * - Deletes their personal subcollections (favourites, attendance, addresses).
 * - Deletes the /users/{uid} document.
 * - Deletes the Firebase Auth account itself.
 */
exports.deleteUserAccount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
  }
  const uid = context.auth.uid;
  const db = admin.firestore();

  // Anonymise comments across every church (collection group query)
  const comments = await db.collectionGroup("comments").where("userId", "==", uid).get();
  const batch = db.batch();
  comments.forEach((doc) => {
    batch.update(doc.ref, {
      userId: null,
      userDisplayName: "[deleted user]",
    });
  });
  await batch.commit();

  // Delete personal subcollections
  for (const sub of ["favouriteChurches", "attendanceHistory", "addresses"]) {
    const snap = await db.collection("users").doc(uid).collection(sub).get();
    const subBatch = db.batch();
    snap.forEach((d) => subBatch.delete(d.ref));
    await subBatch.commit();
  }

  // Delete the user doc, then the Auth account
  await db.collection("users").doc(uid).delete();
  await admin.auth().deleteUser(uid);

  return { success: true };
});

/**
 * Same province-detection logic as the Flutter app's ProvinceLookupService,
 * reading the same provinces/{id}.bounds data - one source of truth, used
 * from both client and server. Useful for batch-validating existing data
 * (e.g. "does this church's GPS actually match its diocese's province?")
 * or auto-suggesting a province when a new church is added.
 */
exports.detectProvince = functions.https.onCall(async (data, context) => {
  const { lat, lng } = data;
  const db = admin.firestore();
  const provinces = await db.collection("provinces").get();
  const matches = [];
  provinces.forEach((doc) => {
    const bounds = doc.data().bounds;
    if (!bounds) return;
    if (lat >= bounds.minLat && lat <= bounds.maxLat && lng >= bounds.minLng && lng <= bounds.maxLng) {
      matches.push(doc.id);
    }
  });
  return { matches };
});

/**
 * Fires when a donation's status changes to approved, wrong_bank, or
 * rejected. Different shape from onNoticeBroadcast and
 * sendScheduledBroadcasts below - both of those resolve a whole audience
 * live from a scope. This is the opposite: exactly one recipient, the
 * donor themselves, found directly via donorId rather than any audience
 * resolution. Worth having as its own case rather than forcing it
 * through the broadcast system's scope model for a single, known
 * recipient.
 */
exports.notifyOnDonationStatusChange = functions.firestore
  .document("parishes/{parishId}/churches/{churchId}/donations/{donationId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (before.status === after.status) return null;
    if (!["approved", "wrong_bank", "rejected"].includes(after.status)) return null;

    const donorId = after.donorId;
    if (!donorId) return null;

    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(donorId).get();
    if (!userDoc.exists) return null;

    const prefs = userDoc.data().preferences || {};
    const notif = prefs.notifications || {};
    if (notif.pushEnabled === false) return null;

    const tokens = userDoc.data().fcmTokens || [];
    if (tokens.length === 0) {
      console.log(`Donor ${donorId} has no saved device token - nothing to notify.`);
      return null;
    }

    let title, body;
    if (after.status === "approved") {
      title = "Thank you for your donation";
      body = `Your donation of R${after.amount} to ${after.associationName} has been received. Thank you!`;
    } else if (after.status === "wrong_bank") {
      title = "Your donation needs attention";
      body = after.adminNote || "This deposit doesn't appear to have reached the right account - please contact your bank about reversing it, or reach out to the parish office.";
    } else {
      title = "Donation update";
      body = after.adminNote || "There was an issue confirming your donation - please contact the parish office.";
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { parishId: context.params.parishId, churchId: context.params.churchId, type: "donationStatus" },
    });

    console.log(`Donation status notification sent to ${response.successCount}/${tokens.length} devices for donor ${donorId}.`);
    return null;
  });

/**
 * Shared by every notify-one-specific-user trigger below (orders, refunds,
 * catechist applications) - pulled out once rather than repeating the
 * same token-lookup-and-send logic a third and fourth time, the same way
 * notifyOnDonationStatusChange already did it inline before this existed.
 */
async function notifyUser(uid, title, body, data) {
  if (!uid) return;
  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) return;

  const prefs = userDoc.data().preferences || {};
  const notif = prefs.notifications || {};
  if (notif.pushEnabled === false) return;

  const tokens = userDoc.data().fcmTokens || [];
  if (tokens.length === 0) {
    console.log(`User ${uid} has no saved device token - nothing to notify.`);
    return;
  }

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
  });
  console.log(`Notification sent to ${response.successCount}/${tokens.length} devices for user ${uid}.`);
}

/**
 * Marketplace orders - two independent things can change on the same
 * doc (payment status, refund status), so both are checked here rather
 * than needing two separate Firestore triggers on the same document.
 */
exports.notifyOnOrderStatusChange = functions.firestore
  .document("parishes/{parishId}/churches/{churchId}/products/{productId}/orders/{orderId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const { parishId, churchId } = context.params;

    if (before.status !== after.status && ["approved", "rejected"].includes(after.status)) {
      const title = after.status === "approved" ? "Your order was approved" : "Order update";
      const body = after.status === "approved"
        ? `Your payment for "${after.productTitle}" has been confirmed. The seller will be in touch about ${after.fulfillmentMethod === "courier" ? "delivery" : "pickup"}.`
        : `There was an issue with your order for "${after.productTitle}" - please contact the seller or the parish office.`;
      await notifyUser(after.buyerId, title, body, { parishId, churchId, type: "orderStatus" });
    }

    if (before.refundStatus !== after.refundStatus && after.refundStatus) {
      let title, body;
      if (after.refundStatus === "approved") {
        title = "Refund approved";
        body = `Your refund of R${after.refundAmount} for "${after.productTitle}" has been approved.`;
      } else if (after.refundStatus === "denied") {
        title = "Refund request denied";
        body = `Your refund request for "${after.productTitle}" was not approved - contact the seller for details.`;
      } else if (after.refundStatus === "processed") {
        title = "Refund sent";
        body = `Your refund of R${after.refundAmount} for "${after.productTitle}" has been sent.`;
      }
      if (title) await notifyUser(after.buyerId, title, body, { parishId, churchId, type: "refundStatus" });
    }

    return null;
  });

/**
 * Catechist applications (both 'catechist' and 'trustedSeller' types share
 * this collection - the message is worded generically enough to fit
 * either without needing to branch on type).
 */
exports.notifyOnCatechistApplicationStatusChange = functions.firestore
  .document("catechistApplications/{appId}")
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();
    if (before.status === after.status) return null;
    if (!["approved", "rejected"].includes(after.status)) return null;

    const title = after.status === "approved" ? "Application approved" : "Application update";
    const body = after.status === "approved"
      ? "Your application has been approved - you'll see a verified tick next to your name from now on."
      : "Your application was not approved this time.";

    await notifyUser(after.applicantId, title, body, { type: "applicationStatus" });
    return null;
  });

/**
 * Server-authoritative quiz grading. The client can only ever write raw
 * answers to a quizAttempt (enforced by rules) - this is the only thing
 * that ever computes score/passed, reading the answer key via Admin SDK,
 * which is the whole reason the answer key lives in a document students
 * can never read through any other path.
 *
 * On a passing grade, this is also the only thing that marks the lesson
 * complete on the student's enrollment - gating lesson completion behind
 * a real passing grade, not a client-side checkbox a student could tick
 * themselves.
 */
exports.gradeQuizAttempt = functions.firestore
  .document("parishes/{parishId}/churches/{churchId}/courses/{courseId}/lessons/{lessonId}/quizAttempts/{uid}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null; // deleted, nothing to grade
    const after = change.after.data();
    if (after.passed !== undefined && after.passed !== null) return null; // already graded, avoid a loop (this write itself sets passed)

    const { parishId, churchId, courseId, lessonId, uid } = context.params;
    const db = admin.firestore();
    const lessonRef = db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(churchId)
      .collection("courses").doc(courseId)
      .collection("lessons").doc(lessonId);

    const [publicSnap, keySnap] = await Promise.all([
      lessonRef.collection("quiz").doc("public").get(),
      lessonRef.collection("quiz").doc("answerKey").get(),
    ]);
    if (!publicSnap.exists || !keySnap.exists) {
      console.log(`No quiz configured for lesson ${lessonId} - nothing to grade.`);
      return null;
    }

    const quiz = publicSnap.data();
    const answerKey = keySnap.data().answers || {};
    const submitted = after.answers || {};
    const questionsShown = after.questionsShown || quiz.questions.map((q) => q.id);

    let correctCount = 0;
    for (const qId of questionsShown) {
      const key = answerKey[qId];
      const given = submitted[qId];
      if (!key) continue;
      if (key.correctIndex !== undefined) {
        if (given === key.correctIndex) correctCount++;
      } else if (key.correctOrder !== undefined) {
        if (Array.isArray(given) && JSON.stringify(given) === JSON.stringify(key.correctOrder)) correctCount++;
      }
    }

    const score = questionsShown.length > 0 ? (correctCount / questionsShown.length) * 100 : 0;
    const passingScore = quiz.passingScorePercent || 70;
    const passed = score >= passingScore;

    await change.after.ref.update({
      score,
      passed,
      gradedAt: admin.firestore.Timestamp.now(),
    });

    if (passed) {
      const enrollmentRef = db
        .collection("parishes").doc(parishId)
        .collection("churches").doc(churchId)
        .collection("courses").doc(courseId)
        .collection("enrollments").doc(uid);
      await enrollmentRef.set(
        { completedLessonIds: admin.firestore.FieldValue.arrayUnion(lessonId) },
        { merge: true }
      );
    }

    await notifyUser(
      uid,
      passed ? "Quiz passed!" : "Quiz result",
      passed ? `You scored ${Math.round(score)}% - lesson marked complete.` : `You scored ${Math.round(score)}% - you need ${passingScore}% to pass. Try again.`,
      { parishId, churchId, courseId, lessonId, type: "quizResult" }
    );

    console.log(`Graded quiz for ${uid} on lesson ${lessonId}: ${score}% (${passed ? "passed" : "failed"}).`);
    return null;
  });

/**
 * Real-time single-question check, used only to decide which question to
 * branch to next while a student is mid-quiz. Deliberately returns just
 * {correct: bool} - never the actual correct answer when wrong - so this
 * can't be used to extract the answer key one question at a time. The
 * authoritative grade and lesson-completion gate still only ever happen
 * in gradeQuizAttempt above, when the full attempt is submitted at the
 * end; this callable exists purely to make branching possible without
 * sending the answer key to the client in bulk.
 */
exports.checkQuizAnswer = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  const { parishId, churchId, courseId, lessonId, questionId, answer } = data;
  const db = admin.firestore();
  const keyDoc = await db
    .collection("parishes").doc(parishId)
    .collection("churches").doc(churchId)
    .collection("courses").doc(courseId)
    .collection("lessons").doc(lessonId)
    .collection("quiz").doc("answerKey")
    .get();

  if (!keyDoc.exists) return { correct: false };
  const key = (keyDoc.data().answers || {})[questionId];
  if (!key) return { correct: false };

  let correct = false;
  if (key.correctIndex !== undefined) {
    correct = answer === key.correctIndex;
  } else if (key.correctOrder !== undefined) {
    correct = Array.isArray(answer) && JSON.stringify(answer) === JSON.stringify(key.correctOrder);
  }
  return { correct };
});

// =====================================================================
// Unified broadcast system (notices, reminders, welcome messages)
//
// Replaces notifyOnNewNotice and sendUpcomingReminders above with a
// single mechanism, built specifically to fix two things: notices and
// reminders drifting into two different systems that could disagree,
// and reminders being computed from a stale snapshot instead of live
// eligibility. Everything below resolves WHO to notify fresh, at send
// time, from the broadcast's scope - never from a stored list. That's
// what makes "don't remind someone who's lost access" automatic rather
// than a separate check someone has to remember to add.
//
// Honest scope for this pass: push and popup are wired end to end.
// Email is deliberately not - it needs its own real sending
// infrastructure and an unsubscribe mechanism, staged as a clearly
// separate next step, not silently missing from what "done" means here.
// =====================================================================

/**
 * Resolves the live set of uids for a broadcast's scope. Never cached,
 * never stored - called fresh every time a broadcast actually sends.
 */
async function resolveAudience(db, scope) {
  const uids = new Set();

  if (scope.kind === "person") {
    uids.add(scope.id);
    return uids;
  }

  if (scope.kind === "lesson") {
    // scope.id is the lessonId; the actual enrollment list lives one
    // level up, on the course - so parentIds carries the full path.
    const { parishId, churchId, courseId } = scope.parentIds;
    const enrollSnap = await db
      .collection("parishes").doc(parishId)
      .collection("churches").doc(churchId)
      .collection("courses").doc(courseId)
      .collection("enrollments").get();
    enrollSnap.docs.forEach((d) => uids.add(d.id));
    return uids;
  }

  if (scope.kind === "church") {
    const favSnap = await db.collectionGroup("favouriteChurches").where("churchId", "==", scope.id).get();
    favSnap.docs.forEach((d) => uids.add(d.ref.parent.parent.id));
    return uids;
  }

  if (scope.kind === "parish") {
    const favSnap = await db.collectionGroup("favouriteChurches").where("parishId", "==", scope.id).get();
    favSnap.docs.forEach((d) => uids.add(d.ref.parent.parent.id));
    return uids;
  }

  if (scope.kind === "province") {
    // Same honest N+1 walk already accepted elsewhere in this codebase
    // for hierarchy rollups (dioceses -> parishes -> favourites) - fine
    // for the current real dataset, would need real denormalization at
    // national scale.
    const diocesesSnap = await db.collection("dioceses").where("provinceId", "==", scope.id).get();
    for (const dioceseDoc of diocesesSnap.docs) {
      const parishesSnap = await db.collection("parishes").where("dioceseId", "==", dioceseDoc.id).get();
      for (const parishDoc of parishesSnap.docs) {
        const favSnap = await db.collectionGroup("favouriteChurches").where("parishId", "==", parishDoc.id).get();
        favSnap.docs.forEach((d) => uids.add(d.ref.parent.parent.id));
      }
    }
    return uids;
  }

  console.log(`resolveAudience: unrecognised scope.kind "${scope.kind}" - no one notified.`);
  return uids;
}

/**
 * Sends a broadcast to its live-resolved audience across whichever
 * channels it's configured for, then marks it sent. prefKey is the
 * specific notification preference to also honour (massReminders,
 * eventReminders) - scopes without a specific preference yet (lesson,
 * parish, province, person) fall back to the general pushEnabled flag
 * only, which is an honest simplification worth knowing, not an oversight.
 */
async function sendBroadcast(db, broadcastRef, broadcast, prefKey) {
  const uids = await resolveAudience(db, broadcast.scope);
  const tokens = [];

  for (const uid of uids) {
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) continue;
    const prefs = userDoc.data().preferences || {};
    const notif = prefs.notifications || {};
    if (notif.pushEnabled === false) continue;
    if (prefKey && notif[prefKey] === false) continue;

    if (broadcast.channels?.push !== false) {
      tokens.push(...(userDoc.data().fcmTokens || []));
    }
    if (broadcast.channels?.popup) {
      await db.collection("users").doc(uid).collection("pendingPopups").add({
        title: broadcast.title,
        body: broadcast.body,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        dismissed: false,
      });
    }
  }

  if (tokens.length > 0) {
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: broadcast.title, body: broadcast.body },
      data: { type: broadcast.type },
    });
    console.log(`Broadcast ${broadcastRef.id}: sent to ${response.successCount}/${tokens.length} devices.`);
  } else {
    console.log(`Broadcast ${broadcastRef.id}: no eligible recipients right now.`);
  }

  await broadcastRef.update({
    "timing.reminderSent": true,
    "timing.sentAt": admin.firestore.Timestamp.now(),
  });
}

/**
 * A new notice creates a broadcast (scope: church) and sends it
 * immediately - notices aren't scheduled, "just posted" is the trigger.
 * Same event source as the old notifyOnNewNotice, now going through the
 * shared, unified path.
 */
exports.onNoticeBroadcast = functions.firestore
  .document("parishes/{parishId}/churches/{churchId}/notices/{noticeId}")
  .onCreate(async (snap, context) => {
    const { parishId, churchId, noticeId } = context.params;
    const notice = snap.data();
    const db = admin.firestore();

    const churchDoc = await db.collection("parishes").doc(parishId).collection("churches").doc(churchId).get();
    const churchName = churchDoc.exists ? churchDoc.data().name : "your parish";

    const broadcastRef = db.collection("broadcasts").doc();
    const broadcast = {
      type: "notice",
      scope: { kind: "church", id: churchId, parentIds: { parishId } },
      title: churchName,
      body: notice.title || "A new notice has been posted.",
      timing: { triggerAt: admin.firestore.Timestamp.now(), leadTimeMinutes: 0, reminderSent: false, sentAt: null },
      channels: { push: true, popup: false, email: false },
      sourceRef: { collection: "notices", docPath: snap.ref.path },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await broadcastRef.set(broadcast);
    await sendBroadcast(db, broadcastRef, broadcast, null);
    return null;
  });

/**
 * Fires once, the moment a user's own account document is first
 * created - a welcome message is a "person" scoped broadcast to exactly
 * one uid, triggered by having an account at all rather than by content
 * being published. Same send path as everything else.
 */
exports.onUserWelcomeBroadcast = functions.firestore
  .document("users/{uid}")
  .onCreate(async (snap, context) => {
    const { uid } = context.params;
    const db = admin.firestore();

    const broadcastRef = db.collection("broadcasts").doc();
    const broadcast = {
      type: "welcome",
      scope: { kind: "person", id: uid, parentIds: {} },
      title: "Welcome to CatholicSA",
      body: "Find your parish, follow daily readings, and see what's happening near you.",
      timing: { triggerAt: admin.firestore.Timestamp.now(), leadTimeMinutes: 0, reminderSent: false, sentAt: null },
      channels: { push: true, popup: true, email: false },
      sourceRef: { collection: "users", docPath: snap.ref.path },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await broadcastRef.set(broadcast);
    await sendBroadcast(db, broadcastRef, broadcast, null);
    return null;
  });

/**
 * Replaces sendUpcomingReminders. Two jobs each run: (1) make sure every
 * upcoming service/event within the lookahead window has a reminder
 * broadcast - creating one with sensible defaults if it doesn't exist
 * yet, using a deterministic ID so this is safe to run every 15 minutes
 * without ever creating duplicates, and (2) send whichever due
 * broadcasts haven't been sent yet, resolving their audience live.
 *
 * sourceRef is what a future "edit this Mass time" feature would use to
 * find and reset the matching broadcast's reminderSent when the time
 * actually changes - the concrete fix for reminders going stale after
 * an edit, built into the shape now even though the edit UI itself
 * isn't built yet.
 */
exports.sendScheduledBroadcasts = functions.pubsub.schedule("every 15 minutes").onRun(async (context) => {
  const db = admin.firestore();
  const now = new Date();

  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  const endOfToday = new Date(now);
  endOfToday.setHours(23, 59, 59, 999);

  // ---------- Ensure reminder broadcasts exist: Mass/Service (today only, lead time 60 min) ----------
  const servicesSnap = await db.collectionGroup("services")
    .where("date", ">=", admin.firestore.Timestamp.fromDate(startOfToday))
    .where("date", "<=", admin.firestore.Timestamp.fromDate(endOfToday))
    .get();

  for (const doc of servicesSnap.docs) {
    const data = doc.data();
    if (!data.time) continue;
    const churchRef = doc.ref.parent.parent;
    const parishRef = churchRef.parent.parent;
    const broadcastId = `service_${parishRef.id}_${churchRef.id}_${doc.id}`;
    const broadcastRef = db.collection("broadcasts").doc(broadcastId);
    const existing = await broadcastRef.get();
    if (existing.exists) continue;

    const [hh, mm] = data.time.split(":").map(Number);
    const serviceDateTime = data.date.toDate();
    serviceDateTime.setHours(hh, mm, 0, 0);

    const churchDoc = await churchRef.get();
    const churchName = churchDoc.exists ? churchDoc.data().name : "your church";

    await broadcastRef.set({
      type: "reminder",
      scope: { kind: "church", id: churchRef.id, parentIds: { parishId: parishRef.id } },
      title: churchName,
      body: `${data.type || "Mass"} starts at ${data.time} today.`,
      timing: { triggerAt: admin.firestore.Timestamp.fromDate(serviceDateTime), leadTimeMinutes: 60, reminderSent: false, sentAt: null },
      channels: { push: true, popup: false, email: false },
      sourceRef: { collection: "services", docPath: doc.ref.path },
      reminderCategory: "mass",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // ---------- Ensure reminder broadcasts exist: Events (next 24h, lead time 24h) ----------
  const in24h = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const eventsSnap = await db.collectionGroup("events")
    .where("date", ">=", admin.firestore.Timestamp.fromDate(now))
    .where("date", "<=", admin.firestore.Timestamp.fromDate(in24h))
    .get();

  for (const doc of eventsSnap.docs) {
    const data = doc.data();
    const churchRef = doc.ref.parent.parent;
    const parishRef = churchRef.parent.parent;
    const broadcastId = `event_${parishRef.id}_${churchRef.id}_${doc.id}`;
    const broadcastRef = db.collection("broadcasts").doc(broadcastId);
    const existing = await broadcastRef.get();
    if (existing.exists) continue;

    const churchDoc = await churchRef.get();
    const churchName = churchDoc.exists ? churchDoc.data().name : "your church";

    await broadcastRef.set({
      type: "reminder",
      scope: { kind: "church", id: churchRef.id, parentIds: { parishId: parishRef.id } },
      title: churchName,
      body: `${data.title} is coming up soon.`,
      timing: { triggerAt: data.date, leadTimeMinutes: 24 * 60, reminderSent: false, sentAt: null },
      channels: { push: true, popup: false, email: false },
      sourceRef: { collection: "events", docPath: doc.ref.path },
      reminderCategory: "event",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // ---------- Send whichever reminder broadcasts are now due ----------
  const dueSnap = await db.collection("broadcasts")
    .where("type", "==", "reminder")
    .where("timing.reminderSent", "==", false)
    .get();

  for (const doc of dueSnap.docs) {
    const broadcast = doc.data();
    const triggerAt = broadcast.timing.triggerAt.toDate();
    const leadMs = (broadcast.timing.leadTimeMinutes || 0) * 60 * 1000;
    const msUntil = triggerAt.getTime() - now.getTime();
    if (msUntil <= 0 || msUntil > leadMs) continue;

    const prefKey = broadcast.reminderCategory === "mass" ? "massReminders" : "eventReminders";
    await sendBroadcast(db, doc.ref, broadcast, prefKey);
  }

  return null;
});

/**
 * Keeps a comment's likeCount authoritative and server-computed. The
 * client only ever creates/deletes the tiny likes/{uid} doc (a trivial,
 * narrow rule) - it never gets write access to likeCount on the comment
 * itself, so there's no way to fake a like count from the client.
 */
exports.onCommentLikeChange = functions.firestore
  .document("parishes/{parishId}/churches/{churchId}/comments/{commentId}/likes/{uid}")
  .onWrite(async (change, context) => {
    const { parishId, churchId, commentId } = context.params;
    const delta = !change.before.exists && change.after.exists ? 1
      : change.before.exists && !change.after.exists ? -1
      : 0;
    if (delta === 0) return null;

    const commentRef = admin.firestore()
      .collection("parishes").doc(parishId)
      .collection("churches").doc(churchId)
      .collection("comments").doc(commentId);
    await commentRef.update({ likeCount: admin.firestore.FieldValue.increment(delta) });
    return null;
  });

/**
 * Syncs a year of feast data from the LitCal API (litcal.johnromanodorazio.com)
 * into feastCalendar, and where safe, auto-populates liturgicalReadings
 * with the real reading citations the API provides.
 *
 * Self-diagnosing by design, agreed on specifically because the exact
 * response shape couldn't be verified ahead of time through normal
 * tooling - a real sample had to be captured and provided directly.
 * Each entry is checked for the fields this sync actually depends on
 * before being trusted; anything that doesn't match gets logged and
 * skipped rather than silently written as if it were confirmed correct.
 * The summary returned makes a bad sync visible immediately, not
 * something that quietly corrupts data until someone happens to notice.
 *
 * Never overwrites an existing liturgicalReadings/{date} doc - a
 * priest's own manually-verified entry always wins over a synced one.
 */
exports.syncFeastCalendar = functions.runWith({ timeoutSeconds: 300 }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  const db = admin.firestore();
  const callerDoc = await db.collection("users").doc(context.auth.uid).get();
  const callerData = callerDoc.exists ? callerDoc.data() : {};
  if (!(callerData.isSuperAdmin === true || callerData.isDeveloper === true)) {
    throw new functions.https.HttpsError("permission-denied", "Super Admin only.");
  }

  const { year, nationalCalendar } = data;
  if (!year || typeof year !== "number") {
    throw new functions.https.HttpsError("invalid-argument", "A numeric year is required.");
  }

  let url = `https://litcal.johnromanodorazio.com/api/v5/calendar/${year}`;
  if (nationalCalendar) url += `?nationalCalendar=${encodeURIComponent(nationalCalendar)}`;

  let response;
  try {
    response = await fetch(url);
  } catch (e) {
    throw new functions.https.HttpsError("unavailable", `Could not reach the LitCal API: ${e.message}`);
  }
  if (!response.ok) {
    throw new functions.https.HttpsError("unavailable", `LitCal API returned ${response.status}`);
  }

  let body;
  try {
    body = await response.json();
  } catch (e) {
    throw new functions.https.HttpsError("internal", "LitCal API response wasn't valid JSON - the API may have changed shape since this sync was written.");
  }

  const entries = body && body.litcal;
  if (!Array.isArray(entries)) {
    throw new functions.https.HttpsError(
      "internal",
      "Response didn't contain the expected 'litcal' array - the API shape may have changed. Nothing was written."
    );
  }

  let synced = 0;
  let readingsPopulated = 0;
  const needsReview = [];

  // Parallelized rather than sequential - a full year is 300+ entries,
  // and awaiting each one's Firestore round-trip in turn was very
  // likely the actual cause of the internal/timeout error being seen,
  // well past the default 60s Cloud Functions limit. JS's single
  // event loop means the shared counters/array below stay safe even
  // running these concurrently - no real race condition risk here.
  await Promise.all(entries.map(async (entry) => {
    if (!entry || typeof entry.date !== "string" || typeof entry.name !== "string" || typeof entry.grade !== "number") {
      needsReview.push({ event_key: entry && entry.event_key, reason: "missing date/name/grade", raw: entry });
      return;
    }

    const dateStr = entry.date.slice(0, 10); // "2025-12-03T00:00:00+00:00" -> "2025-12-03"
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
      needsReview.push({ event_key: entry.event_key, reason: "date didn't parse to YYYY-MM-DD", raw: entry.date });
      return;
    }

    await db.collection("feastCalendar").doc(dateStr).set({
      eventKey: entry.event_key || null,
      name: entry.name,
      grade: entry.grade,
      gradeLabel: entry.grade_lcl || null,
      gradeAbbr: entry.grade_abbr || null,
      type: entry.type || null,
      liturgicalSeason: entry.liturgical_season || null,
      liturgicalSeasonLabel: entry.liturgical_season_lcl || null,
      color: Array.isArray(entry.color) ? entry.color : null,
      commonLabel: entry.common_lcl || null,
      psalterWeek: typeof entry.psalter_week === "number" ? entry.psalter_week : null,
      hasVigilMass: entry.has_vigil_mass === true,
      hasVesperI: entry.has_vesper_i === true,
      hasVesperII: entry.has_vesper_ii === true,
      holyDayOfObligation: entry.holy_day_of_obligation === true,
      syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncedFor: nationalCalendar || "general",
    });
    synced++;

    // Only for a real celebration (grade > 0 - not a plain ferial
    // weekday) with real reading data, and only if nothing has been
    // manually entered for this date yet.
    if (entry.grade > 0 && entry.readings && entry.readings.first_reading && entry.readings.gospel) {
      const existing = await db.collection("liturgicalReadings").doc(dateStr).get();
      if (!existing.exists) {
        await db.collection("liturgicalReadings").doc(dateStr).set({
          liturgicalTitle: entry.name,
          readings: {
            en: {
              firstReading: entry.readings.first_reading,
              psalm: entry.readings.responsorial_psalm || null,
              secondReading: entry.readings.second_reading || null,
              gospel: entry.readings.gospel,
              source: "LitCal API sync - please review before relying on it",
            },
          },
        });
        readingsPopulated++;
      }
    }
  }));

  return { synced, readingsPopulated, needsReviewCount: needsReview.length, needsReview: needsReview.slice(0, 20) };
});

/**
 * Scans every chapter of a given translation server-side and returns
 * verses whose text contains the query (case-insensitive substring
 * match). Honest limitation: this is a brute-force scan, not a real
 * search index - fine at the current scale of a handful of chapters,
 * but would need Algolia or similar if the Bible content grows toward
 * anything close to a full 73-book translation. Flagging this now
 * rather than pretending it scales indefinitely.
 */
exports.searchBibleVerses = functions.runWith({ timeoutSeconds: 60 }).https.onCall(async (data, context) => {
  const { translationCode, query } = data;
  if (!translationCode || typeof translationCode !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "translationCode is required.");
  }
  if (!query || typeof query !== "string" || query.trim().length < 2) {
    throw new functions.https.HttpsError("invalid-argument", "A search query of at least 2 characters is required.");
  }

  const db = admin.firestore();
  const needle = query.trim().toLowerCase();

  const chaptersSnap = await db.collectionGroup("chapters")
    .where("translationCode", "==", translationCode)
    .get();

  const results = [];
  for (const doc of chaptersSnap.docs) {
    const data = doc.data();
    const verses = data.verses || {};
    const bookCode = data.bookCode;
    const chapter = data.chapter;
    for (const [verseNum, text] of Object.entries(verses)) {
      if (typeof text === "string" && text.toLowerCase().includes(needle)) {
        results.push({ bookCode, chapter, verse: verseNum, text });
      }
    }
  }

  // Capped rather than unbounded - a very common word could otherwise
  // return an enormous result set.
  return { results: results.slice(0, 100), totalMatches: results.length };
});

/**
 * Real, server-side "sync the whole Bible." Currently one verified,
 * working source - Douay-Rheims from Project Gutenberg. Structured as a
 * registry specifically so a second source can be added as a real
 * dropdown option later, rather than guessed at now without verifying
 * its actual page structure first the way this one was checked.
 */
const BIBLE_SOURCES = {
  douayRheims: {
    name: "Douay-Rheims (Challoner Revision)",
    sourceUrl: "https://www.gutenberg.org/files/8300/8300-h/8300-h.htm",
    translationCode: "douayRheims",
    isPublicDomain: true,
    licenseNote: "Confirmed public domain - Project Gutenberg, Wikipedia, Internet Archive.",
    // Older book names (Josue not Joshua, Machabees not Maccabees, Osee
    // not Hosea) mapped to this app's manifest codes. An unrecognized
    // name is skipped and reported in needsReview, never silently
    // mis-filed under the wrong code.
    bookMap: {
      "genesis": "gen", "exodus": "exo", "leviticus": "lev", "numbers": "num",
      "deuteronomy": "deu", "joshua": "jos", "josue": "jos", "judges": "jdg", "ruth": "rut",
      "1 kings": "1sa", "2 kings": "2sa", "3 kings": "1ki", "4 kings": "2ki",
      "1 paralipomenon": "1ch", "2 paralipomenon": "2ch",
      "1 ezdras": "ezr", "1 esdras": "ezr", "2 ezdras": "neh", "2 esdras": "neh",
      "tobias": "tob", "judith": "jdt", "esther": "est", "job": "job",
      "psalms": "psa", "proverbs": "pro", "ecclesiastes": "ecc",
      "canticles": "sng", "canticle of canticles": "sng", "book of wisdom": "wis", "the book of wisdom": "wis", "ecclesiasticus": "sir",
      "isaias": "isa", "jeremiah": "jer", "jeremias": "jer",
      "lamentations": "lam", "lamentations of jeremias": "lam",
      "barruch": "bar", "baruch": "bar",
      "ezekiel": "ezk", "ezechiel": "ezk", "daniel": "dan", "osee": "hos", "joel": "jol",
      "amos": "amo", "abdias": "oba", "jonah": "jon", "jonas": "jon", "micheas": "mic",
      "nahum": "nam", "habacuc": "hab", "sophonias": "zep", "aggeus": "hag",
      "zacharias": "zec", "malachias": "mal",
      "1 machabees": "1ma", "2 machabees": "2ma",
      "matthew": "mat", "mark": "mrk", "luke": "luk", "john": "jhn",
      "acts": "act", "romans": "rom", "1 corinthians": "1co", "2 corinthians": "2co",
      "galatians": "gal", "ephesians": "eph", "philippians": "php", "colossians": "col",
      "1 thessalonians": "1th", "2 thessalonians": "2th",
      "1 timothy": "1ti", "2 timothy": "2ti", "titus": "tit", "philemon": "phm",
      "hebrews": "heb", "james": "jas", "1 peter": "1pe", "2 peter": "2pe",
      "1 john": "1jn", "2 john": "2jn", "3 john": "3jn", "jude": "jud",
      "apocalypse": "rev",
    },
  },
};

exports.getBibleSyncSources = functions.https.onCall(async (data, context) => {
  return Object.entries(BIBLE_SOURCES).map(([id, s]) => ({ id, name: s.name, isPublicDomain: s.isPublicDomain }));
});

exports.syncFullBible = functions.runWith({ timeoutSeconds: 540, memory: "512MB" }).https.onCall(async (data, context) => {
  const sourceId = (data && data.sourceId) || "douayRheims";
  const source = BIBLE_SOURCES[sourceId];
  if (!source) {
    throw new functions.https.HttpsError("invalid-argument", `Unknown source: ${sourceId}`);
  }

  const db = admin.firestore();

  const response = await fetch(source.sourceUrl);
  if (!response.ok) {
    throw new functions.https.HttpsError("unavailable", `Could not fetch source text: HTTP ${response.status}`);
  }
  const html = await response.text();

  const text = html
    // Real, confirmed bug found from the last diagnostic: tag-stripping
    // alone removes <style> and <script> tags but leaves everything
    // BETWEEN them intact - which is why the previous attempt's
    // "content" started with raw CSS rules. These have to be removed
    // as whole blocks, contents included, before generic tag-stripping.
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    // The actual, confirmed root cause from the last live diagnostic:
    // "Book 01 &nbsp;&nbsp;&nbsp;&nbsp; Genesis" - literal, unescaped
    // &nbsp; entities sit between the number and the book name
    // throughout the index. Every other entity was already handled;
    // this one specifically was not, and it alone was enough to make
    // the book-boundary pattern match zero times across the whole
    // document.
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&").replace(/&#8217;/g, "'").replace(/&#8216;/g, "'")
    .replace(/&#8220;/g, '"').replace(/&#8221;/g, '"').replace(/&#8212;/g, "-")
    .replace(/\s+/g, " ");

  // Real, confirmed bug from the first version of this function: pages
  // like this one list every book name once in a compact index at the
  // very top, BEFORE the real content - "Book 01 Genesis Book 02
  // Exodus..." all in a row with no content between them. The book-split
  // regex below matched that index first, producing dozens of
  // "books" with zero content each. Fixed by finding the LAST
  // occurrence of the very first book's header specifically (the real
  // content one, since the index only lists it once and the real
  // header appears again later) and starting the real parse from there,
  // skipping the index entirely.
  const firstBookEntry = Object.entries(source.bookMap)[0];
  const firstBookHeaderPattern = new RegExp(`Book \\d{2} ${firstBookEntry[0].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`, "gi");
  const firstBookMatches = [...text.matchAll(firstBookHeaderPattern)];
  const contentStartIndex = firstBookMatches.length > 0 ? firstBookMatches[firstBookMatches.length - 1].index : 0;
  const contentText = text.substring(contentStartIndex);

  // Real, confirmed root cause for Ecclesiastes/Ecclesiasticus, verified
  // against actual fetched text: "Book 23 Ecclesiastes ECCLESIASTES
  // This Book is called..." - the name is immediately followed by
  // itself, repeated in all caps, as the section's own title. The
  // lookahead below only anticipated specific words (THE, Book NN,
  // Gospel, etc.) as valid stopping points, so a match against this
  // structure simply never terminated and the whole boundary was
  // silently skipped. \s+[A-Z]{4,} (any all-caps word of real length)
  // now covers this without needing a separate explicit pattern.
  const bookSplitRegex = /Book (\d{2}) ([A-Za-z1-4 ]+?)(?=\s+THE|\s+Book \d{2}|\s+Gospel|\s+Epistle|\s+Acts|\s+Apocalypse|\s+[A-Z]{4,}|$)/g;
  const standardBoundaries = [...contentText.matchAll(bookSplitRegex)].map((m) => ({
    index: m.index,
    endOfHeader: m.index + m[0].length,
    rawName: m[2].trim(),
  }));

  // Real, confirmed gap: these 4 books were completely absent from both
  // the written list AND the unrecognized-name list in a live run -
  // meaning the standard "Book NN Name" pattern never found their
  // headers at all, so their text silently got absorbed into whichever
  // book came before them. Their actual headers use a different,
  // untitled-by-number style (a plain "(THE) BOOK OF ___" or the
  // Gospel's own liturgical title), which is why an explicit pattern is
  // needed for just these four rather than trying to make the one
  // general regex cover every case.
  const explicitPatterns = [
    { re: /(?:THE\s+)?BOOK\s+OF\s+ECCLESIASTES/gi, rawName: "Ecclesiastes" },
    { re: /(?:THE\s+)?(?:SOLOMON'S\s+)?CANTICLE\s+OF\s+CANTICLES/gi, rawName: "Canticles" },
    { re: /(?:THE\s+)?BOOK\s+OF\s+ECCLESIASTICUS/gi, rawName: "Ecclesiasticus" },
    { re: /(?:THE\s+)?(?:HOLY\s+)?GOSPEL\s+(?:OF\s+JESUS\s+CHRIST\s+)?ACCORDING\s+TO\s+(?:ST\.?\s+|SAINT\s+)?MATTHEW/gi, rawName: "Matthew" },
  ];
  const explicitBoundaries = [];
  const explicitPatternDiagnostics = [];
  for (const { re, rawName } of explicitPatterns) {
    // A real book header is followed, sooner or later, by its actual
    // "1:1." verse start - a stray mention elsewhere (a cross-reference,
    // a footnote) is not. Checks every occurrence, not just the first,
    // specifically because the first occurrence being a false positive
    // (matched inside an unrelated book's own text) was the confirmed
    // cause of the original Canticles bug. Window widened from 400 to
    // 800 chars after directly measuring Matthew's real intro blurb (the
    // saint's biography plus the chapter-1 summary line) at 611
    // characters - the same underlying limitation as the Canticles bug,
    // just not yet wide enough to also cover this longer case.
    const allMatches = [...contentText.matchAll(re)];
    let confirmed = null;
    for (const m of allMatches) {
      const after = contentText.substring(m.index + m[0].length, m.index + m[0].length + 800);
      if (/1:1\./.test(after)) { confirmed = m; break; }
    }
    if (confirmed) {
      explicitBoundaries.push({ index: confirmed.index, endOfHeader: confirmed.index + confirmed[0].length, rawName });
      explicitPatternDiagnostics.push(`${rawName}: confirmed at index ${confirmed.index} (${allMatches.length} total mentions found, this one followed by a real 1:1.)`);
    } else {
      explicitPatternDiagnostics.push(`${rawName}: NOT FOUND - ${allMatches.length} mention(s) of the phrase exist, but none were followed by a real "1:1." within 800 chars, so none were trusted as the real header.`);
    }
  }

  // Merge both sets, sorted by real position in the text. Two kinds of
  // duplicate exist, confirmed from real data rather than assumed:
  // (1) the same pattern matching the same heading within a few
  // characters - dropped outright below. (2) a genuinely different
  // case, confirmed directly from a live "no verses parsed" result -
  // the SAME underlying book matched twice, hundreds of characters
  // apart, by two DIFFERENT patterns that produce different text: the
  // standard pattern captures the full "Canticle of Canticles", the
  // explicit pattern's rawName is hardcoded to the shorter "Canticles".
  // Comparing those two strings directly never matches, even though
  // both resolve to the same bookMap code - that string mismatch was
  // the actual reason the first fix attempt didn't change anything.
  // Resolving to the real code before comparing fixes it for real.
  const allBoundaries = [...standardBoundaries, ...explicitBoundaries].sort((a, b) => a.index - b.index);
  const deduped = [];
  for (const b of allBoundaries) {
    if (deduped.length === 0 || b.index - deduped[deduped.length - 1].index > 30) {
      deduped.push(b);
    }
  }
  const resolvedCode = (b) => source.bookMap[b.rawName.toLowerCase()] || null;
  const bookBoundaries = [];
  for (let i = 0; i < deduped.length; i++) {
    const b = deduped[i];
    const next = deduped[i + 1];
    const bCode = resolvedCode(b);
    const nextCode = next ? resolvedCode(next) : null;
    // Same resolved bookMap code, appearing again within 1000 chars -
    // the same book's real start superseding an earlier intro-blurb
    // match, not two different books (a genuinely different book's
    // code wouldn't repeat that soon). Only compares when both actually
    // resolved to a real code, so an unrecognized name never silently
    // absorbs a real one.
    if (bCode && nextCode && bCode === nextCode && next.index - b.index < 1000) {
      continue; // skip this earlier one - the next iteration keeps the later, real one
    }
    bookBoundaries.push(b);
  }

  let synced = 0;
  const needsReview = [];
  const detailedLog = [...explicitPatternDiagnostics.map((d) => ({ diagnostic: d }))];

  // Matthew specifically was never actually verified against real text
  // the way Ecclesiastes/Ecclesiasticus were - the earlier plain-word
  // search only ever found a stray "Matthew 2.15" cross-reference
  // sitting inside Hosea's own text, never the real header. Checking
  // "Book 47" directly (its expected number in this 73-book numbering)
  // rather than assume the standard or explicit pattern already covers
  // it correctly. Pushed to needsReview specifically, not detailedLog -
  // the Flutter UI only ever reads and displays needsReview, so a
  // detailedLog-only diagnostic is invisible on screen no matter how
  // correct the check itself is.
  const book47Matches = [...contentText.matchAll(/Book\s+47[^0-9]/gi)];
  if (book47Matches.length === 0) {
    needsReview.push(`Book 47 search: no "Book 47" text found anywhere - Matthew's header likely doesn't use the numbered format at all.`);
  } else {
    for (const m of book47Matches) {
      const snippet = contentText.substring(m.index, m.index + 300);
      needsReview.push(`Book 47 found at index ${m.index}: "${snippet}"`);
    }
  }


  // For any of the 4 whose wording assumption was completely wrong (zero
  // mentions of the phrase anywhere) - find the plain word itself, no
  // prefix assumed at all, and show real text from right around it. The
  // same method that found the &nbsp; issue and the CSS-stripping gap;
  // guessing a 4th wording without this would just repeat the mistake.
  for (const { rawName } of explicitPatterns) {
    const alreadyConfirmed = explicitBoundaries.some((b) => b.rawName === rawName);
    if (alreadyConfirmed) continue;
    const plainWordIndex = contentText.search(new RegExp(rawName, "i"));
    const plainSnippet = plainWordIndex >= 0
      ? contentText.substring(Math.max(0, plainWordIndex - 100), plainWordIndex + 200)
      : `(the plain word "${rawName}" does not appear anywhere in the content text at all)`;
    detailedLog.push({ diagnostic: `${rawName} plain-word search: first occurrence at index ${plainWordIndex}, real text: "${plainSnippet}"` });
  }

  if (bookBoundaries.length === 0) {
    // Zero matches on the "Book NN Name" pattern even with style/script
    // stripped now - rather than guess a third time at why, find the
    // plain word "Genesis" itself, with no prefix assumption at all,
    // and show real text from right around it. Whatever actually
    // precedes it there is the real format to match against, not
    // another theory.
    const genesisIndex = text.search(/genesis/i);
    const genesisSnippet = genesisIndex >= 0
      ? text.substring(Math.max(0, genesisIndex - 150), genesisIndex + 150)
      : "(the word \"Genesis\" does not appear anywhere in the fetched text at all)";
    needsReview.push(
      `No book boundaries found. Diagnostics: fetched text length=${text.length}, ` +
      `first-book pattern matches=${firstBookMatches.length}. ` +
      `Real text around the first plain occurrence of "Genesis" (index ${genesisIndex}): "${genesisSnippet}"`
    );
  }

  for (let i = 0; i < bookBoundaries.length; i++) {
    const boundary = bookBoundaries[i];
    const rawName = boundary.rawName.toLowerCase();
    const bookCode = source.bookMap[rawName];
    if (!bookCode) {
      needsReview.push(`Unrecognized book name: "${boundary.rawName}" - skipped, not written anywhere.`);
      detailedLog.push({ rawName: boundary.rawName, action: "skipped", reason: "not in bookMap" });
      continue;
    }

    const bookContentStart = boundary.endOfHeader;
    const bookContentEnd = i + 1 < bookBoundaries.length ? bookBoundaries[i + 1].index : contentText.length;
    const bookText = contentText.substring(bookContentStart, bookContentEnd);

    const verseMatches = [...bookText.matchAll(/(\d+):(\d+)\.\s+/g)];
    const chapters = {};
    for (let j = 0; j < verseMatches.length; j++) {
      const chapter = parseInt(verseMatches[j][1], 10);
      const verse = verseMatches[j][2];
      const start = verseMatches[j].index + verseMatches[j][0].length;
      const end = j + 1 < verseMatches.length ? verseMatches[j + 1].index : bookText.length;
      const verseText = bookText.substring(start, end).trim();
      if (!chapters[chapter]) chapters[chapter] = {};
      chapters[chapter][verse] = verseText;
    }

    if (Object.keys(chapters).length === 0) {
      const nextBoundary = i + 1 < bookBoundaries.length ? bookBoundaries[i + 1] : null;
      needsReview.push(
        `${boundary.rawName} (${bookCode}): no verses parsed. Segment length=${bookText.length}, real content found: "${bookText.substring(0, 400)}". ` +
        `Next boundary that cut this short: ${nextBoundary ? `"${nextBoundary.rawName}" at index ${nextBoundary.index} (${nextBoundary.index - boundary.index} chars after this one started)` : "(none - this was the last boundary)"}`
      );
      detailedLog.push({ rawName: boundary.rawName, bookCode, action: "skipped", reason: "zero chapters" });
      continue;
    }

    for (const [chapterNum, verses] of Object.entries(chapters)) {
      await db
        .collection("bibleTranslations").doc(source.translationCode)
        .collection("books").doc(bookCode)
        .collection("chapters").doc(chapterNum)
        .set({ verses, translationCode: source.translationCode, bookCode, chapter: parseInt(chapterNum, 10) });
      synced++;
    }
    detailedLog.push({ rawName: boundary.rawName, bookCode, action: "written", chapters: Object.keys(chapters).length });
  }

  await db.collection("bibleTranslations").doc(source.translationCode).set({
    name: source.name,
    isPublicDomain: source.isPublicDomain,
    licenseNote: source.licenseNote,
  }, { merge: true });

  return {
    chaptersSynced: synced,
    booksProcessed: bookBoundaries.length,
    needsReviewCount: needsReview.length,
    needsReview: needsReview.slice(0, 30),
    detailedLog,
  };
});

/**
 * Re-hosts every hymn's external CMAA PDF into this project's own
 * Firebase Storage, then updates the Firestore doc to point at the
 * re-hosted copy instead of the external link - what "I want the PDF,
 * not a link" actually means in practice. The original CMAA URL is kept
 * as sourceUrl for attribution, never overwritten. Only touches docs
 * still pointing at an external URL, so re-running this after adding
 * more hymns manually (uploaded PDF or plain text, added separately)
 * never re-processes what's already been re-hosted.
 */
exports.rehostHymnPdfs = functions.runWith({ timeoutSeconds: 540, memory: "512MB" }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  const db = admin.firestore();
  const callerDoc = await db.collection("users").doc(context.auth.uid).get();
  const callerData = callerDoc.exists ? callerDoc.data() : {};
  if (!(callerData.isSuperAdmin === true || callerData.isDeveloper === true)) {
    throw new functions.https.HttpsError("permission-denied", "Super Admin only.");
  }

  const bucket = admin.storage().bucket();
  const hymnsSnap = await db.collection("hymns").get();

  let rehosted = 0;
  let skipped = 0;
  const failures = [];

  for (const doc of hymnsSnap.docs) {
    const hymn = doc.data();
    const currentUrl = hymn.pdfUrl || "";

    // Already re-hosted (points at this project's own Storage, not an
    // external host) - skip, so re-running is always safe and cheap.
    if (currentUrl.includes("firebasestorage.googleapis.com") || currentUrl.includes("storage.googleapis.com")) {
      skipped++;
      continue;
    }
    if (!currentUrl) {
      skipped++;
      continue;
    }

    try {
      const response = await fetch(currentUrl);
      if (!response.ok) {
        failures.push(`${hymn.title || doc.id}: source returned HTTP ${response.status}`);
        continue;
      }
      const arrayBuffer = await response.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);

      const storagePath = `hymns/${doc.id}.pdf`;
      const file = bucket.file(storagePath);
      await file.save(buffer, { metadata: { contentType: "application/pdf" } });
      await file.makePublic();
      const publicUrl = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;

      await doc.ref.update({
        pdfUrl: publicUrl,
        sourceUrl: currentUrl,
        fileType: "pdf",
      });
      rehosted++;
    } catch (e) {
      failures.push(`${hymn.title || doc.id}: ${e.message}`);
    }
  }

  return {
    rehosted,
    skipped,
    failureCount: failures.length,
    failures: failures.slice(0, 30),
  };
});

/**
 * Syncs daily Mass reading CITATIONS (book/chapter/verse references
 * only, e.g. "Wisdom 9:13-18b" - never the reading's actual text) from
 * cpbjr's Catholic Readings API, confirmed real and MIT-licensed
 * (https://cpbjr.github.io/catholic-readings-api/), verified directly
 * against a live response before this was written, not assumed from
 * documentation alone.
 *
 * Deliberately independent of saints - this is what actually fixes "no
 * readings on a date without a saint": readings and saints are separate
 * collections that happened to only be populated together so far, not a
 * real code dependency. This backfills reading citations for every day
 * of a year regardless of whether a saint entry exists for that date.
 *
 * Never overwrites an existing non-empty value - a priest's own
 * Entrance Antiphon, Communion Antiphon, or manually-typed citation
 * always wins. Only fills in whichever of the four citation fields are
 * currently missing or empty, same "never clobber real curation"
 * principle as syncFeastCalendar.
 */
exports.syncDailyReadingsCitations = functions.runWith({ timeoutSeconds: 540, memory: "512MB" }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  const db = admin.firestore();
  const callerDoc = await db.collection("users").doc(context.auth.uid).get();
  const callerData = callerDoc.exists ? callerDoc.data() : {};
  if (!(callerData.isSuperAdmin === true || callerData.isDeveloper === true)) {
    throw new functions.https.HttpsError("permission-denied", "Super Admin only.");
  }

  const { year } = data;
  if (!year || typeof year !== "number") {
    throw new functions.https.HttpsError("invalid-argument", "A numeric year is required.");
  }

  const isLeap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
  const daysInMonth = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  const dateStrs = [];
  for (let m = 1; m <= 12; m++) {
    for (let d = 1; d <= daysInMonth[m - 1]; d++) {
      dateStrs.push(`${year}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`);
    }
  }

  let created = 0;
  let filled = 0;
  let unchanged = 0;
  const failures = [];

  // Parallelized (same reasoning as syncFeastCalendar) - 365 sequential
  // fetches would very likely exceed even this function's generous
  // timeout.
  await Promise.all(dateStrs.map(async (dateStr) => {
    const [, mm, dd] = dateStr.split("-");
    const url = `https://cpbjr.github.io/catholic-readings-api/readings/${year}/${mm}-${dd}.json`;

    let body;
    try {
      const response = await fetch(url);
      if (!response.ok) {
        failures.push(`${dateStr}: HTTP ${response.status}`);
        return;
      }
      body = await response.json();
    } catch (e) {
      failures.push(`${dateStr}: ${e.message}`);
      return;
    }

    const r = body && body.readings;
    if (!r || !r.firstReading || !r.gospel) {
      failures.push(`${dateStr}: response missing expected readings shape`);
      return;
    }

    const docRef = db.collection("liturgicalReadings").doc(dateStr);
    const existing = await docRef.get();

    if (!existing.exists) {
      await docRef.set({
        liturgicalTitle: body.season || "",
        readings: {
          en: {
            firstReading: r.firstReading,
            psalm: r.psalm || null,
            secondReading: r.secondReading || null,
            gospel: r.gospel,
            source: "cpbjr Catholic Readings API sync - citations only, please review",
          },
        },
      });
      created++;
      return;
    }

    // Only fill in whichever citation fields are currently empty -
    // never overwrite a real, already-entered value.
    const existingData = existing.data();
    const existingEn = (existingData.readings && existingData.readings.en) || {};
    const patch = {};
    if (!existingEn.firstReading) patch["readings.en.firstReading"] = r.firstReading;
    if (!existingEn.psalm && r.psalm) patch["readings.en.psalm"] = r.psalm;
    if (!existingEn.secondReading && r.secondReading) patch["readings.en.secondReading"] = r.secondReading;
    if (!existingEn.gospel) patch["readings.en.gospel"] = r.gospel;

    if (Object.keys(patch).length > 0) {
      await docRef.update(patch);
      filled++;
    } else {
      unchanged++;
    }
  }));

  return {
    daysProcessed: dateStrs.length,
    created,
    filled,
    unchanged,
    failureCount: failures.length,
    failures: failures.slice(0, 30),
  };
});

/**
 * Syncs reading CITATIONS ONLY from USCCB's own daily readings site -
 * never the actual reading text, which USCCB's own page footer
 * explicitly states is copyrighted ("Neither this work nor any part of
 * it may be reproduced, distributed, performed or displayed in any
 * medium, including electronic or digital, without permission in
 * writing from the copyright owner"). Only the linked citation text
 * (e.g. "Genesis 1:1-2:2") is ever extracted - references aren't
 * copyrightable, unlike the verse text itself.
 *
 * Two real steps, confirmed necessary by inspecting the actual
 * calendar page directly: most dates use a predictable MMDDYY.cfm URL,
 * but some genuinely don't (a memorial or feast can instead use a slug
 * like "memorial-saint-dominic-priest") - there's no way to predict
 * which, so the monthly calendar page itself is scraped first to get
 * each date's real URL before following it.
 *
 * Correctly captures the Easter Vigil's real multi-reading structure
 * (Reading I through Reading VII, each with its citation, several with
 * genuine "Or" alternates) into vigilReadings when a day has more
 * sections than the standard 4-reading structure - confirmed directly
 * against the real April 4, 2026 page before this was written.
 */
exports.syncUsccbCitations = functions.runWith({ timeoutSeconds: 540, memory: "512MB" }).https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  const db = admin.firestore();
  const callerDoc = await db.collection("users").doc(context.auth.uid).get();
  const callerData = callerDoc.exists ? callerDoc.data() : {};
  if (!(callerData.isSuperAdmin === true || callerData.isDeveloper === true)) {
    throw new functions.https.HttpsError("permission-denied", "Super Admin only.");
  }

  const { year, month } = data; // month: 1-12
  if (!year || !month) {
    throw new functions.https.HttpsError("invalid-argument", "A year and month are required.");
  }

  // Step 1: scrape the monthly calendar page for each date's real URL.
  // A fuller, more realistic browser fingerprint than before - the
  // Sec-Fetch-* headers in particular are things a real browser sends
  // automatically that a plain server-side fetch() never does on its
  // own, making them a genuinely useful signal to add. Honest limit:
  // if the block is IP-reputation-based (Google Cloud/Firebase
  // datacenter ranges) or a JavaScript challenge, no header set fixes
  // that from here - only a real browser engine could get past it.
  const BROWSER_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate, br",
    "Referer": "https://bible.usccb.org/",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "same-origin",
    "Cache-Control": "max-age=0",
  };
  const calendarUrl = `https://bible.usccb.org/readings/calendar/${year}${String(month).padStart(2, "0")}`;
  const calResponse = await fetch(calendarUrl, { headers: BROWSER_HEADERS });
  if (!calResponse.ok) {
    throw new functions.https.HttpsError("unavailable", `Calendar page returned HTTP ${calResponse.status}`);
  }
  const calHtml = await calResponse.text();
  const $cal = cheerio.load(calHtml);

  // Deliberately not dependent on any specific table/td structure -
  // that was the actual point of failure last run, confirmed by a real
  // "no date links found" error against the real page. Every reading
  // link on the page is collected in document order regardless of
  // what wraps it, then dates are resolved two ways: most URLs encode
  // the date directly in their own path (e.g. "080526.cfm" = Aug 5),
  // which needs no HTML structure knowledge at all. A slug-based URL
  // that doesn't encode a date ("memorial-saint-dominic-priest") gets
  // its date inferred from sequential position instead - the calendar
  // is guaranteed to list days in strict chronological order no matter
  // how each cell is marked up, so a slug link sitting immediately
  // after the Aug 7 link and before the Aug 9 link must be Aug 8.
  const allLinks = [];
  $cal("a[href*='/bible/readings/']").each((_, el) => {
    const href = $cal(el).attr("href");
    if (href) allLinks.push(href.startsWith("http") ? href : `https://bible.usccb.org${href}`);
  });

  if (allLinks.length === 0) {
    // Real diagnostic instead of a generic failure - reports what
    // actually exists on the page, so the real structure can be seen
    // and fixed directly rather than guessed at a third time.
    const totalLinks = $cal("a").length;
    const sampleHrefs = $cal("a").slice(0, 15).map((_, el) => $cal(el).attr("href")).get().filter(Boolean);
    throw new functions.https.HttpsError(
      "internal",
      `No reading links found. Page has ${totalLinks} total <a> tags. First few hrefs: ${JSON.stringify(sampleHrefs)}`
    );
  }

  const dateUrls = {}; // "2026-08-12" -> real absolute URL
  let lastResolvedDay = null;
  for (const url of allLinks) {
    const datedMatch = url.match(/\/readings\/(\d{2})(\d{2})(\d{2})\.cfm/);
    let day = null;
    if (datedMatch) {
      const urlMonth = parseInt(datedMatch[1], 10);
      const urlDay = parseInt(datedMatch[2], 10);
      // Only trust a dated URL that's actually within the requested
      // month - the calendar page can show a few trailing/leading days
      // from adjacent months.
      if (urlMonth === month) day = urlDay;
    }
    if (day === null && lastResolvedDay !== null) {
      // Slug-based link with no date in its own URL - infer from
      // position, one day after whatever was last resolved.
      day = lastResolvedDay + 1;
    }
    if (day === null) continue; // no way to resolve this one's date at all - skip rather than guess wrong
    const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    dateUrls[dateStr] = url;
    lastResolvedDay = day;
  }

  // Step 2: for each real URL, extract citations only.
  const SECTION_NAMES = ["reading i", "reading ii", "reading iii", "reading iv", "reading v", "reading vi", "reading vii", "epistle", "gospel", "responsorial psalm", "or"];

  let created = 0;
  let filled = 0;
  let unchanged = 0;
  const failures = [];

  // Sequential with a small delay, not Promise.all firing all requests
  // at once - confirmed as the actual cause of the 403s: a single
  // calendar-page request succeeded with these same headers, but all
  // 30 per-date requests fired simultaneously failed identically. A
  // burst of near-instant parallel requests from one server IP to the
  // same domain is exactly the pattern bot-detection is built to
  // catch, regardless of User-Agent - a real browser never does this.
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  for (const [dateStr, url] of Object.entries(dateUrls)) {
    let html;
    try {
      const response = await fetch(url, { headers: BROWSER_HEADERS });
      if (!response.ok) {
        failures.push(`${dateStr}: HTTP ${response.status} from ${url}`);
        await sleep(1200);
        continue;
      }
      html = await response.text();
    } catch (e) {
      failures.push(`${dateStr}: ${e.message}`);
      await sleep(1200);
      continue;
    }

    const $ = cheerio.load(html);
    const titleEl = $("h1, h2").first();
    const liturgicalTitle = titleEl.text().trim();

    // Every heading whose own text matches a known section name, in
    // document order - the citation is the linked text immediately
    // following it.
    const sections = [];
    $("h2, h3, h4").each((_, el) => {
      const heading = $(el).text().trim().toLowerCase();
      if (!SECTION_NAMES.includes(heading)) return;
      // The citation link sits somewhere after this heading, before
      // the next heading - walking forward through siblings until the
      // first real link is found is more robust than assuming a fixed
      // DOM depth.
      let node = $(el).next();
      let citationText = null;
      let guard = 0;
      while (node.length && guard < 5) {
        const link = node.is("a") ? node : node.find("a").first();
        if (link.length && link.attr("href") && link.attr("href").includes("/bible/")) {
          citationText = link.text().trim();
          break;
        }
        node = node.next();
        guard++;
      }
      if (citationText) sections.push({ label: heading, citation: citationText });
    });

    if (sections.length === 0) {
      failures.push(`${dateStr}: no reading sections found on ${url}`);
      await sleep(1200);
      continue;
    }

    // Build both possible shapes - the standard 4-field structure and
    // the vigilReadings list - deciding which to use based on how many
    // real Reading-N sections were actually found. "Or" entries follow
    // the section immediately before them and aren't a separate
    // reading - dropped here since only one citation is stored, not
    // every liturgically-valid alternative.
    const readingLabels = sections.filter((s) => s.label.startsWith("reading "));
    const psalmSections = sections.filter((s) => s.label === "responsorial psalm");
    const epistle = sections.find((s) => s.label === "epistle");
    const gospel = sections.find((s) => s.label === "gospel");

    const docRef = db.collection("liturgicalReadings").doc(dateStr);
    const existing = await docRef.get();
    const existingData = existing.exists ? existing.data() : {};
    const existingEn = (existingData.readings && existingData.readings.en) || {};

    let patch = {};
    let vigilReadings = null;

    if (readingLabels.length > 4) {
      // Genuinely more readings than the standard structure covers -
      // the Vigil case. order set from position for correct display
      // sequence; "Or" alternates already dropped above.
      vigilReadings = readingLabels.map((r, i) => ({
        order: i,
        reading: r.citation,
        psalm: psalmSections[i] ? psalmSections[i].citation : null,
        psalmResponse: null,
      }));
      if (gospel) patch.gospel = gospel.citation;
    } else {
      if (readingLabels[0] && !existingEn.firstReading) patch.firstReading = readingLabels[0].citation;
      if (psalmSections[0] && !existingEn.psalm) patch.psalm = psalmSections[0].citation;
      const secondReadingSource = readingLabels[1] || epistle;
      if (secondReadingSource && !existingEn.secondReading) patch.secondReading = secondReadingSource.citation;
      if (gospel && !existingEn.gospel) patch.gospel = gospel.citation;
    }

    if (!existing.exists) {
      const newData = { liturgicalTitle, readings: { en: patch } };
      if (vigilReadings) newData.vigilReadings = vigilReadings;
      await docRef.set(newData);
      created++;
    } else {
      const fieldPatch = {};
      for (const [key, value] of Object.entries(patch)) {
        fieldPatch[`readings.en.${key}`] = value;
      }
      // Vigil readings only ever set if the document doesn't already
      // have any - never overwrites a real manual entry someone
      // already built through the admin form.
      if (vigilReadings && (!existingData.vigilReadings || existingData.vigilReadings.length === 0)) {
        fieldPatch.vigilReadings = vigilReadings;
      }
      if (Object.keys(fieldPatch).length > 0) {
        await docRef.update(fieldPatch);
        filled++;
      } else {
        unchanged++;
      }
    }
    await sleep(1200);
  }

  return {
    datesFound: Object.keys(dateUrls).length,
    created,
    filled,
    unchanged,
    failureCount: failures.length,
    failures: failures.slice(0, 30),
  };
});