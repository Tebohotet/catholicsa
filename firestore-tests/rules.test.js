/**
 * Security rules tests for the Developer/Super Admin hierarchy and
 * catechist applications - built specifically because reasoning through
 * these by hand caught two real bugs during development:
 *   1. isSuperAdmin() returning true for developers too (correct) meant
 *      the old broad admin-write rule would have let a PLAIN super admin
 *      grant Developer status to someone else (wrong).
 *   2. A parish priest approving a parish-level application originally
 *      tried to also write onto the applicant's users/{uid} doc, which a
 *      priest has no permission to do.
 * These tests exist so a future change to firestore.rules can't silently
 * reintroduce either bug without a test failing.
 *
 * Requires the Firestore emulator - see README.md in this folder for how
 * to run these.
 */
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, collection, addDoc } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');
const { test, describe, before, after, beforeEach } = require('node:test');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'catholicsa-rules-test',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

describe('Developer / Super Admin role hierarchy', () => {
  test('a plain signed-in user cannot grant themselves Super Admin', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice'), { email: 'alice@test.com', isSuperAdmin: false, isDeveloper: false });
    });
    await assertFails(updateDoc(doc(alice.firestore(), 'users/alice'), { isSuperAdmin: true }));
  });

  test('a plain signed-in user cannot grant themselves Developer', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice'), { email: 'alice@test.com', isSuperAdmin: false, isDeveloper: false });
    });
    await assertFails(updateDoc(doc(alice.firestore(), 'users/alice'), { isDeveloper: true }));
  });

  test('a Super Admin who is NOT a Developer cannot grant Developer status to someone else (the exact bug caught during development)', async () => {
    const bob = testEnv.authenticatedContext('bob');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/bob'), { isSuperAdmin: true, isDeveloper: false });
      await setDoc(doc(ctx.firestore(), 'users/carol'), { isSuperAdmin: false, isDeveloper: false });
    });
    await assertFails(updateDoc(doc(bob.firestore(), 'users/carol'), { isDeveloper: true }));
  });

  test('a Super Admin who is NOT a Developer CAN still update other unrelated fields on a user', async () => {
    const bob = testEnv.authenticatedContext('bob');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/bob'), { isSuperAdmin: true, isDeveloper: false });
      await setDoc(doc(ctx.firestore(), 'users/carol'), { isSuperAdmin: false, isDeveloper: false, displayName: 'Carol' });
    });
    await assertSucceeds(updateDoc(doc(bob.firestore(), 'users/carol'), { displayName: 'Carol Updated' }));
  });

  test('a Developer CAN grant Developer status to someone else', async () => {
    const dave = testEnv.authenticatedContext('dave');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/dave'), { isSuperAdmin: false, isDeveloper: true });
      await setDoc(doc(ctx.firestore(), 'users/erin'), { isSuperAdmin: false, isDeveloper: false });
    });
    await assertSucceeds(updateDoc(doc(dave.firestore(), 'users/erin'), { isDeveloper: true }));
  });

  test('a Developer CAN grant Super Admin status to someone else', async () => {
    const dave = testEnv.authenticatedContext('dave');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/dave'), { isSuperAdmin: false, isDeveloper: true });
      await setDoc(doc(ctx.firestore(), 'users/erin'), { isSuperAdmin: false, isDeveloper: false });
    });
    await assertSucceeds(updateDoc(doc(dave.firestore(), 'users/erin'), { isSuperAdmin: true }));
  });
});

describe('Course review workflow - only a priest can move a course away from pendingReview', () => {
  const coursePath = 'parishes/st-jude-parish/churches/vredenburg/courses/rcia';

  test('a secretary can create a draft course', async () => {
    const secretary = testEnv.authenticatedContext('secretary1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/secretary1'), { role: 'secretary', status: 'active' });
    });
    await assertSucceeds(setDoc(doc(secretary.firestore(), coursePath), {
      title: 'RCIA', description: '', catechistName: 'Jane', status: 'draft', createdBy: 'secretary1',
    }));
  });

  test('a secretary can submit their own draft course for review (draft -> pendingReview)', async () => {
    const secretary = testEnv.authenticatedContext('secretary1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/secretary1'), { role: 'secretary', status: 'active' });
      await setDoc(doc(ctx.firestore(), coursePath), { title: 'RCIA', status: 'draft' });
    });
    await assertSucceeds(updateDoc(doc(secretary.firestore(), coursePath), { status: 'pendingReview' }));
  });

  test('a secretary CANNOT self-approve a pendingReview course to published (this is the exact gap found and fixed)', async () => {
    const secretary = testEnv.authenticatedContext('secretary1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/secretary1'), { role: 'secretary', status: 'active' });
      await setDoc(doc(ctx.firestore(), coursePath), { title: 'RCIA', status: 'pendingReview' });
    });
    await assertFails(updateDoc(doc(secretary.firestore(), coursePath), { status: 'published' }));
  });

  test('a secretary CANNOT send a pendingReview course back to draft either', async () => {
    const secretary = testEnv.authenticatedContext('secretary1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/secretary1'), { role: 'secretary', status: 'active' });
      await setDoc(doc(ctx.firestore(), coursePath), { title: 'RCIA', status: 'pendingReview' });
    });
    await assertFails(updateDoc(doc(secretary.firestore(), coursePath), { status: 'draft' }));
  });

  test('a priest CAN approve a pendingReview course to published', async () => {
    const priest = testEnv.authenticatedContext('priest1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/priest1'), { role: 'priest', status: 'active' });
      await setDoc(doc(ctx.firestore(), coursePath), { title: 'RCIA', status: 'pendingReview' });
    });
    await assertSucceeds(updateDoc(doc(priest.firestore(), coursePath), { status: 'published' }));
  });

  test('a secretary can still edit an unrelated field on a pendingReview course, just not its status', async () => {
    const secretary = testEnv.authenticatedContext('secretary1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/secretary1'), { role: 'secretary', status: 'active' });
      await setDoc(doc(ctx.firestore(), coursePath), { title: 'RCIA', description: 'old', status: 'pendingReview' });
    });
    await assertSucceeds(updateDoc(doc(secretary.firestore(), coursePath), { description: 'updated description' }));
  });
});

describe('Course reviews - enrollment is enforced at the rules level, not just app code', () => {
  const coursePath = 'parishes/st-jude-parish/churches/vredenburg/courses/rcia';

  test('a signed-in but NOT enrolled user cannot write a review (this is the exact gap found and fixed)', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await assertFails(
      setDoc(doc(alice.firestore(), `${coursePath}/reviews/alice`), {
        reviewerId: 'alice', reviewerName: 'Alice', rating: 5, comment: 'Great course',
      })
    );
  });

  test('an enrolled user CAN write their own review', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${coursePath}/enrollments/alice`), { enrolledAt: new Date(), completedLessonIds: [] });
    });
    await assertSucceeds(
      setDoc(doc(alice.firestore(), `${coursePath}/reviews/alice`), {
        reviewerId: 'alice', reviewerName: 'Alice', rating: 5, comment: 'Great course',
      })
    );
  });

  test('an enrolled user cannot write a review claiming to be someone else', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${coursePath}/enrollments/alice`), { enrolledAt: new Date(), completedLessonIds: [] });
    });
    await assertFails(
      setDoc(doc(alice.firestore(), `${coursePath}/reviews/alice`), {
        reviewerId: 'mallory', reviewerName: 'Mallory', rating: 1, comment: 'Fake review',
      })
    );
  });
});

describe('Catechist applications', () => {
  test('a signed-in user can create their own application', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await assertSucceeds(addDoc(collection(alice.firestore(), 'catechistApplications'), {
      applicantId: 'alice', applicantName: 'Alice', applicantContact: '0821234567',
      level: 'parish', parishId: 'st-jude-parish', status: 'pending',
    }));
  });

  test('a user cannot create an application claiming to be someone else', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await assertFails(addDoc(collection(alice.firestore(), 'catechistApplications'), {
      applicantId: 'mallory', applicantName: 'Mallory', applicantContact: '0821234567',
      level: 'parish', parishId: 'st-jude-parish', status: 'pending',
    }));
  });

  test("that parish's own priest can approve a parish-level application for that parish", async () => {
    const priest = testEnv.authenticatedContext('priest1');
    let appId;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/priest1'), { role: 'priest', status: 'active' });
      const ref = await addDoc(collection(ctx.firestore(), 'catechistApplications'), {
        applicantId: 'alice', applicantName: 'Alice', applicantContact: '0821234567',
        level: 'parish', parishId: 'st-jude-parish', status: 'pending',
      });
      appId = ref.id;
    });
    await assertSucceeds(updateDoc(doc(priest.firestore(), `catechistApplications/${appId}`), { status: 'approved' }));
  });

  test('a priest cannot approve a parish-level application for a DIFFERENT parish (not real bypass via demo-parish)', async () => {
    const priest = testEnv.authenticatedContext('priest1');
    let appId;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/priest1'), { role: 'priest', status: 'active' });
      const ref = await addDoc(collection(ctx.firestore(), 'catechistApplications'), {
        applicantId: 'alice', applicantName: 'Alice', applicantContact: '0821234567',
        level: 'parish', parishId: 'a-different-parish', status: 'pending',
      });
      appId = ref.id;
    });
    await assertFails(updateDoc(doc(priest.firestore(), `catechistApplications/${appId}`), { status: 'approved' }));
  });

  test('a priest cannot approve a national-level application', async () => {
    const priest = testEnv.authenticatedContext('priest1');
    let appId;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/priest1'), { role: 'priest', status: 'active' });
      const ref = await addDoc(collection(ctx.firestore(), 'catechistApplications'), {
        applicantId: 'alice', applicantName: 'Alice', applicantContact: '0821234567',
        level: 'national', parishId: null, status: 'pending',
      });
      appId = ref.id;
    });
    await assertFails(updateDoc(doc(priest.firestore(), `catechistApplications/${appId}`), { status: 'approved' }));
  });

  test('a Super Admin CAN approve a national-level application (this is the whole point of the escalation)', async () => {
    const admin = testEnv.authenticatedContext('admin1');
    let appId;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/admin1'), { isSuperAdmin: true, isDeveloper: false });
      const ref = await addDoc(collection(ctx.firestore(), 'catechistApplications'), {
        applicantId: 'alice', applicantName: 'Alice', applicantContact: '0821234567',
        level: 'national', parishId: null, status: 'pending',
      });
      appId = ref.id;
    });
    await assertSucceeds(updateDoc(doc(admin.firestore(), `catechistApplications/${appId}`), { status: 'approved' }));
  });

  test('a random signed-in user with no role at all cannot approve any application', async () => {
    const random = testEnv.authenticatedContext('random-guy');
    let appId;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const ref = await addDoc(collection(ctx.firestore(), 'catechistApplications'), {
        applicantId: 'alice', applicantName: 'Alice', applicantContact: '0821234567',
        level: 'parish', parishId: 'st-jude-parish', status: 'pending',
      });
      appId = ref.id;
    });
    await assertFails(updateDoc(doc(random.firestore(), `catechistApplications/${appId}`), { status: 'approved' }));
  });
});

describe('Quiz answer key - a student can never read correct answers or self-report a passing grade', () => {
  const lessonPath = 'parishes/st-jude-parish/churches/vredenburg/courses/rcia/lessons/lesson1';

  test('a student CANNOT read the answer key directly', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${lessonPath}/quiz/answerKey`), { answers: { q1: { correctIndex: 2 } } });
    });
    await assertFails(getDoc(doc(alice.firestore(), `${lessonPath}/quiz/answerKey`)));
  });

  test('a student CAN read the public quiz (questions, no answers) once the course is published', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/churches/vredenburg/courses/rcia'), { status: 'published' });
      await setDoc(doc(ctx.firestore(), `${lessonPath}/quiz/public`), { questions: [{ id: 'q1', type: 'multipleChoice', text: 'Q1', options: ['A', 'B'] }] });
    });
    await assertSucceeds(getDoc(doc(alice.firestore(), `${lessonPath}/quiz/public`)));
  });

  test('an admin (priest/secretary) CAN read the answer key', async () => {
    const secretary = testEnv.authenticatedContext('secretary1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'parishes/st-jude-parish/admins/secretary1'), { role: 'secretary', status: 'active' });
      await setDoc(doc(ctx.firestore(), `${lessonPath}/quiz/answerKey`), { answers: { q1: { correctIndex: 2 } } });
    });
    await assertSucceeds(getDoc(doc(secretary.firestore(), `${lessonPath}/quiz/answerKey`)));
  });

  test('a student can submit an attempt with only raw answers', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await assertSucceeds(setDoc(doc(alice.firestore(), `${lessonPath}/quizAttempts/alice`), {
      studentId: 'alice', answers: { q1: 2 }, questionsShown: ['q1'],
    }));
  });

  test('a student CANNOT self-report passed=true when creating an attempt (the exact gap this whole design exists to close)', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await assertFails(setDoc(doc(alice.firestore(), `${lessonPath}/quizAttempts/alice`), {
      studentId: 'alice', answers: { q1: 2 }, questionsShown: ['q1'], passed: true, score: 100,
    }));
  });

  test('a student CANNOT later update their own attempt to add a passing score', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${lessonPath}/quizAttempts/alice`), { studentId: 'alice', answers: { q1: 2 }, questionsShown: ['q1'] });
    });
    await assertFails(updateDoc(doc(alice.firestore(), `${lessonPath}/quizAttempts/alice`), { passed: true, score: 100 }));
  });

  test('a student cannot submit an attempt claiming to be someone else', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await assertFails(setDoc(doc(alice.firestore(), `${lessonPath}/quizAttempts/alice`), {
      studentId: 'mallory', answers: { q1: 2 }, questionsShown: ['q1'],
    }));
  });
});

describe('Marketplace refund requests - amount is verified server-side, not trusted from the client', () => {
  const orderPath = 'parishes/st-jude-parish/churches/vredenburg/products/rosary/orders/order1';

  test('a buyer CAN request a refund with the correctly-computed amount (this exact request used to be rejected - refundAmount was missing from the rule allowlist entirely)', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), orderPath), {
        buyerId: 'alice', sellerId: 'bob', finalAmount: 100, refundPercent: 50, status: 'approved',
      });
    });
    await assertSucceeds(updateDoc(doc(alice.firestore(), orderPath), {
      refundStatus: 'requested', refundReason: 'Changed my mind', refundRequestedAt: new Date(),
      refundAmount: 50, // 100 * (50/100) = 50, matches the order's own immutable data
    }));
  });

  test('a buyer CANNOT request a refund for more than their policy actually entitles them to', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), orderPath), {
        buyerId: 'alice', sellerId: 'bob', finalAmount: 100, refundPercent: 50, status: 'approved',
      });
    });
    await assertFails(updateDoc(doc(alice.firestore(), orderPath), {
      refundStatus: 'requested', refundReason: 'Changed my mind', refundRequestedAt: new Date(),
      refundAmount: 100, // should be 50 - this is the buyer trying to claim a full refund on a 50% policy
    }));
  });

  test('a buyer cannot approve their own refund request (still admin-only)', async () => {
    const alice = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), orderPath), {
        buyerId: 'alice', sellerId: 'bob', finalAmount: 100, refundPercent: 50, status: 'approved', refundStatus: 'requested', refundAmount: 50,
      });
    });
    await assertFails(updateDoc(doc(alice.firestore(), orderPath), { refundStatus: 'approved' }));
  });
});
