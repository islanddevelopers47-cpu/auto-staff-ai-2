import { Router, raw } from "express";
import Stripe from "stripe";
import admin from "firebase-admin";
import { getEnv } from "../../config/env.js";
import { isFirebaseEnabled } from "../../auth/firebase.js";
import { createLogger } from "../../utils/logger.js";

const log = createLogger("stripe");

export function createStripeRouter(): Router {
  const router = Router();
  const env = getEnv();

  // Check if Stripe is configured
  function getStripe(): Stripe | null {
    if (!env.STRIPE_SECRET_KEY) return null;
    return new Stripe(env.STRIPE_SECRET_KEY);
  }

  // --- Public: check if Stripe billing is enabled ---
  router.get("/stripe/status", (_req, res) => {
    res.json({
      enabled: !!env.STRIPE_SECRET_KEY,
      hasPriceId: !!env.STRIPE_PRICE_ID,
    });
  });

  // --- Create Stripe Checkout Session ---
  // Called after Firebase signup — redirects user to Stripe to pay
  router.post("/stripe/create-checkout-session", async (req, res) => {
    try {
      const stripe = getStripe();
      if (!stripe) {
        res.status(503).json({ error: "Stripe is not configured" });
        return;
      }
      if (!env.STRIPE_PRICE_ID) {
        res.status(503).json({ error: "STRIPE_PRICE_ID is not set" });
        return;
      }

      const { firebaseUid, email, successUrl, cancelUrl } = req.body as {
        firebaseUid?: string;
        email?: string;
        successUrl?: string;
        cancelUrl?: string;
      };

      if (!firebaseUid || !email) {
        res.status(400).json({ error: "firebaseUid and email are required" });
        return;
      }

      // Create or retrieve Stripe customer for this Firebase user
      const customers = await stripe.customers.list({ email, limit: 1 });
      let customer: Stripe.Customer;
      if (customers.data.length > 0) {
        customer = customers.data[0];
      } else {
        customer = await stripe.customers.create({
          email,
          metadata: { firebaseUid },
        });
      }

      // Create checkout session for monthly subscription
      const baseUrl = env.PUBLIC_URL || `http://127.0.0.1:${env.PORT}`;
      const session = await stripe.checkout.sessions.create({
        customer: customer.id,
        payment_method_types: ["card"],
        mode: "subscription",
        line_items: [
          {
            price: env.STRIPE_PRICE_ID,
            quantity: 1,
          },
        ],
        metadata: { firebaseUid },
        success_url: successUrl || `${baseUrl}/?payment=success`,
        cancel_url: cancelUrl || `${baseUrl}/?payment=cancelled`,
      });

      res.json({ url: session.url, sessionId: session.id });
    } catch (err: any) {
      log.error(`Checkout session error: ${err.message}`);
      res.status(500).json({ error: err.message || "Failed to create checkout session" });
    }
  });

  // --- Check subscription status for a Firebase user ---
  router.post("/stripe/check-subscription", async (req, res) => {
    try {
      const stripe = getStripe();
      if (!stripe) {
        // If Stripe not configured, allow access (no billing enforced)
        res.json({ active: true, reason: "billing_not_configured" });
        return;
      }

      const { firebaseUid, email } = req.body as {
        firebaseUid?: string;
        email?: string;
      };

      if (!email) {
        res.status(400).json({ error: "email is required" });
        return;
      }

      // Find customer
      const customers = await stripe.customers.list({ email, limit: 1 });
      if (customers.data.length === 0) {
        res.json({ active: false, reason: "no_customer" });
        return;
      }

      // Check active subscriptions
      const subscriptions = await stripe.subscriptions.list({
        customer: customers.data[0].id,
        status: "active",
        limit: 1,
      });

      if (subscriptions.data.length > 0) {
        // Also set the custom claim on Firebase if not already set
        if (firebaseUid && isFirebaseEnabled()) {
          try {
            const userRecord = await admin.auth().getUser(firebaseUid);
            if (!userRecord.customClaims?.stripeRole) {
              await admin.auth().setCustomUserClaims(firebaseUid, {
                ...userRecord.customClaims,
                stripeRole: "premium",
              });
            }
          } catch {}
        }
        res.json({
          active: true,
          subscriptionId: subscriptions.data[0].id,
          currentPeriodEnd: (subscriptions.data[0] as any).current_period_end,
        });
        return;
      }

      // Check for trialing or past_due (still give access for past_due temporarily)
      const trialSubs = await stripe.subscriptions.list({
        customer: customers.data[0].id,
        status: "trialing",
        limit: 1,
      });
      if (trialSubs.data.length > 0) {
        res.json({ active: true, reason: "trialing" });
        return;
      }

      res.json({ active: false, reason: "no_active_subscription" });
    } catch (err: any) {
      log.error(`Check subscription error: ${err.message}`);
      res.status(500).json({ error: err.message });
    }
  });

  // --- Stripe Webhook ---
  // Handles subscription events to set/revoke Firebase custom claims
  router.post(
    "/stripe/webhook",
    raw({ type: "application/json" }),
    async (req, res) => {
      const stripe = getStripe();
      if (!stripe) {
        res.status(503).send("Stripe not configured");
        return;
      }

      const sig = req.headers["stripe-signature"] as string;
      let event: Stripe.Event;

      try {
        if (env.STRIPE_WEBHOOK_SECRET) {
          event = stripe.webhooks.constructEvent(req.body, sig, env.STRIPE_WEBHOOK_SECRET);
        } else {
          // No webhook secret — parse directly (development only)
          event = JSON.parse(req.body.toString()) as Stripe.Event;
          log.warn("No STRIPE_WEBHOOK_SECRET set — webhook signature not verified!");
        }
      } catch (err: any) {
        log.error(`Webhook signature verification failed: ${err.message}`);
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
      }

      log.info(`Stripe webhook: ${event.type}`);

      try {
        switch (event.type) {
          // Payment succeeded — activate user
          case "checkout.session.completed":
          case "invoice.payment_succeeded": {
            const obj = event.data.object as any;
            const customerId = obj.customer as string;
            await setStripeRoleForCustomer(stripe, customerId, "premium");
            break;
          }

          // Subscription becomes active
          case "customer.subscription.created":
          case "customer.subscription.updated": {
            const sub = event.data.object as Stripe.Subscription;
            if (sub.status === "active" || sub.status === "trialing") {
              await setStripeRoleForCustomer(stripe, sub.customer as string, "premium");
            } else if (
              sub.status === "canceled" ||
              sub.status === "unpaid" ||
              sub.status === "past_due"
            ) {
              await setStripeRoleForCustomer(stripe, sub.customer as string, null);
            }
            break;
          }

          // Subscription deleted — revoke access
          case "customer.subscription.deleted": {
            const sub = event.data.object as Stripe.Subscription;
            await setStripeRoleForCustomer(stripe, sub.customer as string, null);
            break;
          }

          // Invoice payment failed — revoke access
          case "invoice.payment_failed": {
            const invoice = event.data.object as any;
            await setStripeRoleForCustomer(stripe, invoice.customer as string, null);
            break;
          }
        }
      } catch (err: any) {
        log.error(`Webhook handler error: ${err.message}`);
      }

      res.json({ received: true });
    }
  );

  // --- Create Customer Portal session (manage billing) ---
  router.post("/stripe/create-portal-session", async (req, res) => {
    try {
      const stripe = getStripe();
      if (!stripe) {
        res.status(503).json({ error: "Stripe is not configured" });
        return;
      }

      const { email, returnUrl } = req.body as { email?: string; returnUrl?: string };
      if (!email) {
        res.status(400).json({ error: "email is required" });
        return;
      }

      const customers = await stripe.customers.list({ email, limit: 1 });
      if (customers.data.length === 0) {
        res.status(404).json({ error: "No Stripe customer found for this email" });
        return;
      }

      const baseUrl = env.PUBLIC_URL || `http://127.0.0.1:${env.PORT}`;
      const session = await stripe.billingPortal.sessions.create({
        customer: customers.data[0].id,
        return_url: returnUrl || baseUrl,
      });

      res.json({ url: session.url });
    } catch (err: any) {
      log.error(`Portal session error: ${err.message}`);
      res.status(500).json({ error: err.message });
    }
  });

  return router;
}

// --- Helper: Set stripeRole custom claim on the Firebase user linked to a Stripe customer ---
async function setStripeRoleForCustomer(
  stripe: Stripe,
  customerId: string,
  role: string | null
): Promise<void> {
  if (!isFirebaseEnabled()) return;

  try {
    const customer = await stripe.customers.retrieve(customerId);
    if (customer.deleted) return;

    const firebaseUid = (customer as Stripe.Customer).metadata?.firebaseUid;
    if (!firebaseUid) {
      log.warn(`No firebaseUid in Stripe customer ${customerId} metadata`);
      return;
    }

    const claims = role ? { stripeRole: role } : { stripeRole: null };
    await admin.auth().setCustomUserClaims(firebaseUid, claims);
    log.info(
      `Set stripeRole=${role ?? "null"} for Firebase user ${firebaseUid} (Stripe customer ${customerId})`
    );
  } catch (err: any) {
    log.error(`Failed to set custom claims for customer ${customerId}: ${err.message}`);
  }
}
