import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import Stripe from "stripe";

admin.initializeApp();

const db = admin.firestore();

/**
 * Scheduled Cloud Function — runs every 24 hours.
 * Checks for users with canceled/unpaid/past_due subscriptions
 * that have been inactive for 30+ days, then deletes their Firebase account.
 *
 * Also directly queries Stripe for subscription status as the source of truth.
 */
export const deleteUnpaidUsers = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const stripeKey = functions.config().stripe?.secret_key;
    if (!stripeKey) {
      console.warn("Stripe secret key not configured — skipping unpaid user cleanup");
      return;
    }

    const stripe = new Stripe(stripeKey);
    const thirtyDaysAgo = Math.floor((Date.now() - 30 * 24 * 60 * 60 * 1000) / 1000);

    // List all Firebase Auth users (paginated)
    let nextPageToken: string | undefined;
    let deletedCount = 0;

    do {
      const listResult = await admin.auth().listUsers(1000, nextPageToken);
      nextPageToken = listResult.pageToken;

      for (const userRecord of listResult.users) {
        // Skip users with active stripeRole claim
        if (userRecord.customClaims?.stripeRole === "premium") {
          continue;
        }

        // Skip users created less than 7 days ago (grace period for new signups)
        const createdAt = new Date(userRecord.metadata.creationTime).getTime();
        if (Date.now() - createdAt < 7 * 24 * 60 * 60 * 1000) {
          continue;
        }

        // Check Stripe for this user's subscription status
        const email = userRecord.email;
        if (!email) continue;

        try {
          const customers = await stripe.customers.list({ email, limit: 1 });
          if (customers.data.length === 0) {
            // No Stripe customer — user never paid. Delete if older than 30 days.
            const ageSeconds = (Date.now() - createdAt) / 1000;
            if (ageSeconds > 30 * 24 * 60 * 60) {
              await deleteUser(userRecord.uid, email);
              deletedCount++;
            }
            continue;
          }

          // Check for any active or trialing subscription
          const activeSubs = await stripe.subscriptions.list({
            customer: customers.data[0].id,
            status: "active",
            limit: 1,
          });
          if (activeSubs.data.length > 0) continue;

          const trialSubs = await stripe.subscriptions.list({
            customer: customers.data[0].id,
            status: "trialing",
            limit: 1,
          });
          if (trialSubs.data.length > 0) continue;

          // Check canceled/unpaid/past_due — if last period ended 30+ days ago, delete
          const allSubs = await stripe.subscriptions.list({
            customer: customers.data[0].id,
            limit: 5,
          });

          const recentEnd = allSubs.data.reduce((latest, sub) => {
            return Math.max(latest, sub.current_period_end || 0);
          }, 0);

          if (recentEnd > 0 && recentEnd < thirtyDaysAgo) {
            await deleteUser(userRecord.uid, email);
            deletedCount++;
          }
        } catch (err) {
          console.error(`Error checking subscription for ${email}:`, err);
        }
      }
    } while (nextPageToken);

    console.log(`Unpaid user cleanup complete — deleted ${deletedCount} users`);
  });

/**
 * Delete a Firebase user and clean up Firestore data
 */
async function deleteUser(uid: string, email: string): Promise<void> {
  try {
    // Delete Firebase Auth account
    await admin.auth().deleteUser(uid);

    // Clean up Firestore user document if it exists
    const userDoc = db.collection("users").doc(uid);
    const snap = await userDoc.get();
    if (snap.exists) {
      // Delete subcollections (subscriptions, checkout_sessions, etc.)
      const subcollections = await userDoc.listCollections();
      for (const subcol of subcollections) {
        const docs = await subcol.listDocuments();
        for (const doc of docs) {
          await doc.delete();
        }
      }
      await userDoc.delete();
    }

    console.log(`Deleted unpaid user: ${uid} (${email})`);
  } catch (err) {
    console.error(`Failed to delete user ${uid} (${email}):`, err);
  }
}

/**
 * Webhook-triggered cleanup: immediately revoke access when subscription is deleted.
 * This is called by the Stripe webhook handler in the backend, but can also be
 * deployed as a standalone Cloud Function if you prefer.
 */
export const onSubscriptionDeleted = functions.firestore
  .document("users/{userId}/subscriptions/{subscriptionId}")
  .onUpdate(async (change, context) => {
    const after = change.after.data();
    const status = after?.status;

    if (status === "canceled" || status === "unpaid") {
      const userId = context.params.userId;
      try {
        // Revoke premium claim
        await admin.auth().setCustomUserClaims(userId, { stripeRole: null });
        console.log(`Revoked stripeRole for user ${userId} (subscription ${status})`);
      } catch (err) {
        console.error(`Failed to revoke claims for ${userId}:`, err);
      }
    }
  });
