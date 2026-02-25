import { Router } from "express";
import type { Request, Response } from "express";
import type Database from "better-sqlite3";
import Stripe from "stripe";
import admin from "firebase-admin";
import { getEnv } from "../../config/env.js";
import { createLogger } from "../../utils/logger.js";
import { authMiddleware } from "../../auth/middleware.js";
import { findUserById, findUserByFirebaseUid, updateStripeStatus } from "../../database/users.js";
import { isFirebaseEnabled } from "../../auth/firebase.js";

const log = createLogger("billing");

function getStripe(): Stripe | null {
  const key = getEnv().STRIPE_SECRET_KEY;
  if (!key) return null;
  return new Stripe(key, { apiVersion: "2026-01-28.clover" });
}

export function isBillingEnabled(): boolean {
  const env = getEnv();
  return !!(env.STRIPE_SECRET_KEY && env.STRIPE_BILLING_ENABLED === "true");
}

export function createBillingRouter(db: Database.Database): Router {
  const router = Router();

  // -------------------------------------------------------------------
  // GET /api/billing/status — check if billing is enabled (public)
  // -------------------------------------------------------------------
  router.get("/billing/status", (_req, res) => {
    const env = getEnv();
    res.json({
      enabled: isBillingEnabled(),
      priceId: env.STRIPE_PRICE_ID ?? null,
    });
  });

  // -------------------------------------------------------------------
  // POST /api/billing/checkout — create Stripe Checkout session
  // User must provide email. They pay BEFORE getting a Firebase account.
  // -------------------------------------------------------------------
  router.post("/billing/checkout", async (req: Request, res: Response) => {
    try {
      const stripe = getStripe();
      if (!stripe || !isBillingEnabled()) {
        res.status(503).json({ error: "Billing is not configured" });
        return;
      }

      const { email, successUrl, cancelUrl } = req.body as {
        email?: string;
        successUrl?: string;
        cancelUrl?: string;
      };

      if (!email) {
        res.status(400).json({ error: "email is required" });
        return;
      }

      const env = getEnv();
      const priceId = env.STRIPE_PRICE_ID;
      if (!priceId) {
        res.status(503).json({ error: "STRIPE_PRICE_ID not configured" });
        return;
      }

      const baseUrl = env.PUBLIC_URL || "http://localhost:3000";

      const session = await stripe.checkout.sessions.create({
        payment_method_types: ["card"],
        mode: "subscription",
        customer_email: email,
        line_items: [{ price: priceId, quantity: 1 }],
        subscription_data: {
          metadata: { email },
        },
        metadata: { email },
        success_url: successUrl || `${baseUrl}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: cancelUrl || `${baseUrl}/billing/cancel`,
      });

      log.info(`Created Stripe checkout session for ${email}`);
      res.json({ url: session.url, sessionId: session.id });
    } catch (err: any) {
      log.error(`Checkout error: ${err.message}`);
      res.status(500).json({ error: err.message });
    }
  });

  // -------------------------------------------------------------------
  // POST /api/billing/portal — customer billing portal (manage sub/card)
  // Requires auth
  // -------------------------------------------------------------------
  router.post("/billing/portal", authMiddleware, async (req: Request, res: Response) => {
    try {
      const stripe = getStripe();
      if (!stripe || !isBillingEnabled()) {
        res.status(503).json({ error: "Billing is not configured" });
        return;
      }

      const user = findUserById(db, req.user!.userId);
      if (!user?.stripe_customer_id) {
        res.status(404).json({ error: "No Stripe customer found for this account" });
        return;
      }

      const env = getEnv();
      const baseUrl = env.PUBLIC_URL || "http://localhost:3000";

      const session = await stripe.billingPortal.sessions.create({
        customer: user.stripe_customer_id,
        return_url: `${baseUrl}/`,
      });

      res.json({ url: session.url });
    } catch (err: any) {
      log.error(`Portal error: ${err.message}`);
      res.status(500).json({ error: err.message });
    }
  });

  // -------------------------------------------------------------------
  // GET /api/billing/subscription — get current subscription status
  // Requires auth
  // -------------------------------------------------------------------
  router.get("/billing/subscription", authMiddleware, async (req: Request, res: Response) => {
    try {
      const stripe = getStripe();
      if (!stripe || !isBillingEnabled()) {
        res.json({ status: "billing_disabled", active: true });
        return;
      }

      const user = findUserById(db, req.user!.userId);
      if (!user) {
        res.status(404).json({ error: "User not found" });
        return;
      }

      // Admin always has access
      if (user.role === "admin") {
        res.json({ status: "admin", active: true });
        return;
      }

      if (!user.stripe_customer_id) {
        res.json({ status: "no_subscription", active: false });
        return;
      }

      // Fetch live subscription status from Stripe
      const subscriptions = await stripe.subscriptions.list({
        customer: user.stripe_customer_id,
        status: "all",
        limit: 1,
      });

      const sub = subscriptions.data[0];
      if (!sub) {
        res.json({ status: "no_subscription", active: false });
        return;
      }

      const active = sub.status === "active" || sub.status === "trialing";
      updateStripeStatus(db, user.id, sub.status, user.stripe_customer_id);

      res.json({
        status: sub.status,
        active,
        currentPeriodEnd: (sub as any).current_period_end,
        cancelAtPeriodEnd: sub.cancel_at_period_end,
      });
    } catch (err: any) {
      log.error(`Subscription check error: ${err.message}`);
      res.status(500).json({ error: err.message });
    }
  });

  // -------------------------------------------------------------------
  // POST /api/billing/webhook — Stripe webhook handler
  // Must be registered BEFORE express.json() middleware (raw body needed)
  // -------------------------------------------------------------------
  router.post(
    "/billing/webhook",
    async (req: Request, res: Response) => {
      const stripe = getStripe();
      if (!stripe) {
        res.status(503).send("Billing not configured");
        return;
      }

      const webhookSecret = getEnv().STRIPE_WEBHOOK_SECRET;
      if (!webhookSecret) {
        res.status(503).send("Webhook secret not configured");
        return;
      }

      let event: Stripe.Event;
      try {
        const sig = req.headers["stripe-signature"] as string;
        event = stripe.webhooks.constructEvent(req.body as Buffer, sig, webhookSecret);
      } catch (err: any) {
        log.warn(`Webhook signature verification failed: ${err.message}`);
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
      }

      log.info(`Stripe webhook: ${event.type}`);

      try {
        switch (event.type) {
          // ---- Payment succeeded → provision Firebase account ----
          case "checkout.session.completed": {
            const session = event.data.object as Stripe.Checkout.Session;
            if (session.mode === "subscription" && session.payment_status === "paid") {
              await handleCheckoutComplete(db, stripe, session);
            }
            break;
          }

          // ---- Subscription active (renewed monthly) ----
          case "invoice.payment_succeeded": {
            const invoice = event.data.object as Stripe.Invoice;
            await handleInvoicePaid(db, stripe, invoice);
            break;
          }

          // ---- Payment failed → mark past_due ----
          case "invoice.payment_failed": {
            const invoice = event.data.object as Stripe.Invoice;
            await handleInvoiceFailed(db, stripe, invoice);
            break;
          }

          // ---- Subscription canceled/deleted → revoke access ----
          case "customer.subscription.deleted":
          case "customer.subscription.updated": {
            const sub = event.data.object as Stripe.Subscription;
            await handleSubscriptionChange(db, sub);
            break;
          }

          default:
            break;
        }
      } catch (err: any) {
        log.error(`Webhook handler error for ${event.type}: ${err.message}`);
      }

      res.json({ received: true });
    }
  );

  return router;
}

// ---------------------------------------------------------------------------
// Webhook handler helpers
// ---------------------------------------------------------------------------

async function handleCheckoutComplete(
  db: Database.Database,
  stripe: Stripe,
  session: Stripe.Checkout.Session
): Promise<void> {
  const email = session.metadata?.email || session.customer_email;
  const customerId = session.customer as string;

  if (!email) {
    log.warn("checkout.session.completed missing email");
    return;
  }

  log.info(`Checkout complete for ${email}, customer: ${customerId}`);

  // Set stripeRole custom claim on Firebase user (create if needed)
  if (isFirebaseEnabled()) {
    try {
      let fbUser: admin.auth.UserRecord;
      try {
        fbUser = await admin.auth().getUserByEmail(email);
      } catch {
        // User doesn't exist yet — create Firebase account
        fbUser = await admin.auth().createUser({
          email,
          emailVerified: true,
          displayName: email.split("@")[0],
        });
        log.info(`Created Firebase user for ${email}: ${fbUser.uid}`);

        // Send password reset email so they can set their own password
        try {
          const link = await admin.auth().generatePasswordResetLink(email);
          log.info(`Password reset link for ${email}: ${link}`);
          // In production you'd send this via email (SendGrid/Resend etc.)
        } catch (e) {
          log.warn(`Could not generate password reset link for ${email}`);
        }
      }

      // Set premium custom claim
      await admin.auth().setCustomUserClaims(fbUser.uid, {
        stripeRole: "premium",
        stripeCustomerId: customerId,
      });
      log.info(`Set stripeRole=premium for ${fbUser.uid}`);

      // Upsert into local DB with stripe customer ID
      const existing = findUserByFirebaseUid(db, fbUser.uid);
      if (!existing) {
        const id = generateLocalId();
        let username = email.split("@")[0];
        const dup = db.prepare("SELECT id FROM users WHERE username = ?").get(username);
        if (dup) username = `${username}_${id.slice(0, 6)}`;

        db.prepare(
          `INSERT INTO users (id, username, password_hash, role, display_name, firebase_uid, email, photo_url, auth_provider, stripe_customer_id, stripe_subscription_status)
           VALUES (?, ?, NULL, 'user', ?, ?, ?, NULL, 'firebase', ?, 'active')`
        ).run(id, username, fbUser.displayName ?? null, fbUser.uid, email, customerId);
      } else {
        updateStripeStatus(db, existing.id, "active", customerId);
      }
    } catch (err: any) {
      log.error(`Firebase provisioning error: ${err.message}`);
    }
  } else {
    log.warn("Firebase not enabled — cannot provision account after checkout");
  }
}

async function handleInvoicePaid(
  db: Database.Database,
  stripe: Stripe,
  invoice: Stripe.Invoice
): Promise<void> {
  const customerId = invoice.customer as string;
  if (!customerId) return;

  // Re-activate the user in local DB
  const user = db
    .prepare("SELECT * FROM users WHERE stripe_customer_id = ?")
    .get(customerId) as any;

  if (user) {
    updateStripeStatus(db, user.id, "active", customerId);
    log.info(`Invoice paid — restored active status for user ${user.id}`);

    // Restore Firebase custom claim
    if (isFirebaseEnabled() && user.firebase_uid) {
      try {
        await admin.auth().setCustomUserClaims(user.firebase_uid, {
          stripeRole: "premium",
          stripeCustomerId: customerId,
        });
      } catch (e: any) {
        log.warn(`Could not restore Firebase claim for ${user.firebase_uid}: ${e.message}`);
      }
    }
  }
}

async function handleInvoiceFailed(
  db: Database.Database,
  stripe: Stripe,
  invoice: Stripe.Invoice
): Promise<void> {
  const customerId = invoice.customer as string;
  if (!customerId) return;

  const user = db
    .prepare("SELECT * FROM users WHERE stripe_customer_id = ?")
    .get(customerId) as any;

  if (user) {
    updateStripeStatus(db, user.id, "past_due", customerId);
    log.info(`Invoice failed — marked past_due for user ${user.id}`);

    // Revoke Firebase custom claim
    if (isFirebaseEnabled() && user.firebase_uid) {
      try {
        await admin.auth().setCustomUserClaims(user.firebase_uid, {
          stripeRole: null,
          stripeCustomerId: customerId,
        });
      } catch (e: any) {
        log.warn(`Could not revoke Firebase claim for ${user.firebase_uid}: ${e.message}`);
      }
    }
  }
}

async function handleSubscriptionChange(
  db: Database.Database,
  sub: Stripe.Subscription
): Promise<void> {
  const customerId = sub.customer as string;
  const status = sub.status;

  const user = db
    .prepare("SELECT * FROM users WHERE stripe_customer_id = ?")
    .get(customerId) as any;

  if (!user) return;

  updateStripeStatus(db, user.id, status, customerId);
  log.info(`Subscription ${status} for user ${user.id}`);

  const active = status === "active" || status === "trialing";

  if (isFirebaseEnabled() && user.firebase_uid) {
    try {
      await admin.auth().setCustomUserClaims(user.firebase_uid, {
        stripeRole: active ? "premium" : null,
        stripeCustomerId: customerId,
      });

      // Delete Firebase account if subscription is fully canceled/unpaid
      if (status === "canceled" || status === "unpaid") {
        await admin.auth().deleteUser(user.firebase_uid);
        db.prepare("DELETE FROM users WHERE id = ?").run(user.id);
        log.info(`Deleted Firebase + local account for user ${user.id} (${status})`);
      }
    } catch (e: any) {
      log.warn(`Could not update Firebase claim for ${user.firebase_uid}: ${e.message}`);
    }
  }
}

function generateLocalId(): string {
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}
