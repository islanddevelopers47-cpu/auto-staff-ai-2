"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.stripeWebhook = exports.deleteUnpaidUsers = void 0;
const scheduler_1 = require("firebase-functions/v2/scheduler");
const https_1 = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const stripe_1 = require("stripe");
admin.initializeApp();
let _stripe = null;
function getStripe() {
    if (!_stripe) {
        const key = process.env.STRIPE_SECRET_KEY;
        if (!key)
            throw new Error("STRIPE_SECRET_KEY not set");
        _stripe = new stripe_1.default(key, { apiVersion: "2026-01-28.clover" });
    }
    return _stripe;
}
// ---------------------------------------------------------------------------
// Scheduled: delete Firebase accounts for canceled/unpaid subscriptions
// Runs every 24 hours. Gives users 3 days grace after subscription ends.
// ---------------------------------------------------------------------------
exports.deleteUnpaidUsers = (0, scheduler_1.onSchedule)({ schedule: "every 24 hours", secrets: ["STRIPE_SECRET_KEY"] }, async () => {
    const gracePeriodMs = 3 * 24 * 60 * 60 * 1000; // 3 days
    const cutoff = Math.floor((Date.now() - gracePeriodMs) / 1000); // Unix timestamp
    const db = admin.firestore();
    // Find users whose subscription is canceled/unpaid and grace period has passed
    const snapshot = await db
        .collection("users")
        .where("stripeSubscriptionStatus", "in", ["canceled", "unpaid", "past_due", "incomplete_expired"])
        .get();
    let deleted = 0;
    let skipped = 0;
    for (const doc of snapshot.docs) {
        const data = doc.data();
        const uid = doc.id;
        // Skip if the subscription ended recently (still within grace period)
        const periodEnd = data.stripeCurrentPeriodEnd;
        if (periodEnd && periodEnd > cutoff) {
            skipped++;
            continue;
        }
        try {
            // Delete Firebase Auth account
            await admin.auth().deleteUser(uid);
            // Delete Firestore user doc
            await doc.ref.delete();
            deleted++;
            console.log(`Deleted unpaid user: ${uid} (status: ${data.stripeSubscriptionStatus})`);
        }
        catch (e) {
            if (e.code === "auth/user-not-found") {
                // Auth user already gone — just clean up Firestore
                await doc.ref.delete().catch(() => { });
                deleted++;
            }
            else {
                console.error(`Failed to delete user ${uid}: ${e.message}`);
            }
        }
    }
    console.log(`deleteUnpaidUsers: deleted=${deleted}, skipped=${skipped}`);
});
// ---------------------------------------------------------------------------
// Stripe webhook handler via Firebase HTTPS function (alternative to backend)
// Use this if deploying the backend to a serverless environment where you
// prefer to handle webhooks via Firebase Functions instead.
// ---------------------------------------------------------------------------
exports.stripeWebhook = (0, https_1.onRequest)({ secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"] }, async (req, res) => {
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || "";
    if (!webhookSecret) {
        console.error("STRIPE_WEBHOOK_SECRET not set");
        res.status(500).send("Webhook secret not configured");
        return;
    }
    let event;
    try {
        const sig = req.headers["stripe-signature"];
        event = getStripe().webhooks.constructEvent(req.rawBody, sig, webhookSecret);
    }
    catch (err) {
        console.error(`Webhook signature failed: ${err.message}`);
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
    }
    console.log(`Stripe webhook: ${event.type}`);
    const db = admin.firestore();
    try {
        switch (event.type) {
            case "checkout.session.completed": {
                const session = event.data.object;
                if (session.mode === "subscription" && session.payment_status === "paid") {
                    const email = session.metadata?.email || session.customer_email;
                    const customerId = session.customer;
                    const subscriptionId = session.subscription;
                    if (!email)
                        break;
                    // Get subscription details
                    const sub = await getStripe().subscriptions.retrieve(subscriptionId);
                    // Find or create Firebase Auth user
                    let fbUser;
                    try {
                        fbUser = await admin.auth().getUserByEmail(email);
                    }
                    catch {
                        fbUser = await admin.auth().createUser({
                            email,
                            emailVerified: true,
                            displayName: email.split("@")[0],
                        });
                        console.log(`Created Firebase user for ${email}: ${fbUser.uid}`);
                        // Generate password setup link
                        try {
                            await admin.auth().generatePasswordResetLink(email);
                            console.log(`Password reset link generated for ${email}`);
                            // TODO: send via email provider (SendGrid, Resend, etc.)
                            // await sendWelcomeEmail(email, link);
                        }
                        catch (e) {
                            console.warn(`Could not generate password reset link: ${e}`);
                        }
                    }
                    // Set premium custom claim
                    await admin.auth().setCustomUserClaims(fbUser.uid, {
                        stripeRole: "premium",
                        stripeCustomerId: customerId,
                    });
                    // Sync to Firestore
                    await db.collection("users").doc(fbUser.uid).set({
                        email,
                        stripeCustomerId: customerId,
                        stripeSubscriptionId: subscriptionId,
                        stripeSubscriptionStatus: sub.status,
                        stripeCurrentPeriodEnd: sub.current_period_end,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                    console.log(`Provisioned account for ${email} (uid: ${fbUser.uid})`);
                }
                break;
            }
            case "invoice.payment_succeeded": {
                const invoice = event.data.object;
                const customerId = invoice.customer;
                if (!customerId)
                    break;
                const users = await db
                    .collection("users")
                    .where("stripeCustomerId", "==", customerId)
                    .limit(1)
                    .get();
                if (!users.empty) {
                    const userDoc = users.docs[0];
                    await userDoc.ref.update({
                        stripeSubscriptionStatus: "active",
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    // Restore premium claim
                    await admin.auth().setCustomUserClaims(userDoc.id, {
                        stripeRole: "premium",
                        stripeCustomerId: customerId,
                    });
                    console.log(`Invoice paid — restored active for ${userDoc.id}`);
                }
                break;
            }
            case "invoice.payment_failed": {
                const invoice = event.data.object;
                const customerId = invoice.customer;
                if (!customerId)
                    break;
                const users = await db
                    .collection("users")
                    .where("stripeCustomerId", "==", customerId)
                    .limit(1)
                    .get();
                if (!users.empty) {
                    const userDoc = users.docs[0];
                    await userDoc.ref.update({
                        stripeSubscriptionStatus: "past_due",
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    // Revoke premium claim
                    await admin.auth().setCustomUserClaims(userDoc.id, {
                        stripeRole: null,
                        stripeCustomerId: customerId,
                    });
                    console.log(`Invoice failed — marked past_due for ${userDoc.id}`);
                }
                break;
            }
            case "customer.subscription.updated":
            case "customer.subscription.deleted": {
                const sub = event.data.object;
                const customerId = sub.customer;
                const users = await db
                    .collection("users")
                    .where("stripeCustomerId", "==", customerId)
                    .limit(1)
                    .get();
                if (!users.empty) {
                    const userDoc = users.docs[0];
                    const active = sub.status === "active" || sub.status === "trialing";
                    await userDoc.ref.update({
                        stripeSubscriptionStatus: sub.status,
                        stripeCurrentPeriodEnd: sub.current_period_end,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    await admin.auth().setCustomUserClaims(userDoc.id, {
                        stripeRole: active ? "premium" : null,
                        stripeCustomerId: customerId,
                    });
                    // Immediately delete if canceled or unpaid (no grace period version)
                    if (sub.status === "canceled") {
                        console.log(`Subscription canceled for ${userDoc.id} — scheduled for deletion by deleteUnpaidUsers`);
                    }
                    console.log(`Subscription ${sub.status} for user ${userDoc.id}`);
                }
                break;
            }
            default:
                break;
        }
    }
    catch (err) {
        console.error(`Handler error for ${event.type}: ${err.message}`);
    }
    res.json({ received: true });
});
//# sourceMappingURL=index.js.map