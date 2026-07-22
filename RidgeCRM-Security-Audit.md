# RidgeCRM — Security & Audit Report
_Full review of `server.js`, `public/index.html`, the Supabase database, and dependencies._

## Bottom line

The CRM is **fundamentally well-built**: secrets live in environment variables (none hardcoded as API keys), the Supabase **service-role key never reaches the browser** (the client uses only the publishable/anon key), **every database table has Row-Level Security enabled** (so the anon key can't read your data directly — all access flows through the server), most HTML is escaped, and most webhooks are signature-verified.

The real risks are concentrated in a few **"fail-open" guards**, a couple of **hardcoded passwords in the client**, some **missing per-record ownership checks**, and **out-of-date email libraries**. One issue — self-escalation of the new account tier — I already fixed during this audit.

Severity legend: 🔴 Critical · 🟠 High · 🟡 Medium · ⚪ Low

---

## 🔴 Critical

**C1. Confirm `REQUIRE_LOGIN=true` in Railway.**
The whole API is wrapped in `if (REQUIRE_LOGIN) { …auth… }`. If that variable is **not** set to true, the server treats every request as an unauthenticated admin (`/api/me` returns `role:"admin"`), and all role checks fail open. You **do** have a `REQUIRE_LOGIN` variable in Railway — this is just to **verify its value is `true`**. If it is, the "fail-open" notes below are mitigated in production; the code should still be hardened to fail *closed*.

**C2. Tier self-escalation — FIXED during this audit.**
`POST /api/profile` let an agent merge arbitrary fields into their own `ops`. `level` was pinned server-side but `tier` was not — so a **non-licensed agent could set `ops.tier:'licensed'` on themselves and unlock the full CRM, bypassing the Team toggle and the $50/mo billing.** I pinned `tier`, `billingActive`, and `licensedAt` server-side (line ~3178). ✅ Done — ships on next deploy.

---

## 🟠 High

**H1. Stripe webhook fails open when the secret is unset.** `server.js:2798`
`if (STRIPE_WH && !verifyStripeSig(...))` — if `STRIPE_WEBHOOK_SECRET` is empty, signature checking is skipped entirely. Anyone could POST a forged `checkout.session.completed` to mark accounts paid (billing bypass) or `subscription.deleted` to suspend accounts (DoS). Billing turns on as soon as `STRIPE_SECRET_KEY` is set, independent of the webhook secret.
**Fix:** when billing is on, hard-require `STRIPE_WH`; reject (400) if missing/invalid.

**H2. Twilio webhook fails open when the auth token is unset.** `server.js:1457`
`twilioSignatureValid` returns `true` if `TWILIO_AUTH_TOKEN` is falsy, plus a `TWILIO_SKIP_VERIFY=true` bypass. Forged inbound SMS/voice/status callbacks could be injected into contacts.
**Fix:** fail closed when no token; remove/tighten the skip flag.

**H3. IDOR on the generic by-id routes for non-contact records.** `server.js:~6002 (GET), ~6042 (PUT), ~6003 (POST)`
Contacts have proper `makeVisible(me)` checks, but **policies, claims, deals, documents, templates** fall through to a generic handler that fetches/updates/creates **by id with no ownership check and writes the entire request body**. An authenticated agent could read or edit another producer's policy/claim by guessing the numeric id, and set arbitrary fields (e.g. `producer`, `commission`).
**Fix:** for those collections, resolve the linked contact and enforce `makeVisible`/`canOps`, and whitelist updatable fields.

**H4. Hardcoded shared password for bulk-created agents.** `public/index.html:4043, 4062` (`Ridgeway#2026`)
The bulk "add agents" flow provisions real login accounts with this known password, shipped in the page source. Anyone reading the JS knows the default credential for any freshly created agent who hasn't changed it.
**Fix:** generate a random per-account password server-side; force reset on first login.

**H5. Non-licensed tier is not enforced server-side.** (the feature we built today)
The minimal non-licensed view is **client-side only**. A non-licensed agent could still call data API routes directly. Combined with C2 (now fixed) this was doubly exploitable; even with C2 fixed, the *view* restriction isn't enforced on the API.
**Fix:** in the auth gate, block non-licensed agents from data routes (return 402/403), not just hide tabs.

**H6. Out-of-date email libraries (3 high-severity CVEs).** `nodemailer`, via `imapflow` + `mailparser`
`nodemailer <=9.0.0` has SMTP command injection, header injection, and SSRF/file-read advisories. You're on `^6.9.14`.
**Fix:** bump `nodemailer` to `^7` (and update `imapflow`/`mailparser`), then re-test send + inbox sync.

---

## 🟡 Medium

**M1. `GET /api/setting?key=…` has no role gate.** `server.js:~5454`
Any approved agent can read any setting — including `billing`, `hierarchy`, agency emails, and the new `crm_collections`. (PUT is partly gated; GET is not.)
**Fix:** gate sensitive keys behind `canOps`/admin on read.

**M2. `GET /api/team` and `/api/hierarchy` expose agency-wide financials.** `server.js:~3481, ~3487`
Any approved agent sees the full roster plus every agent's premium/commission/production and the whole org chart.
**Fix:** restrict financial fields + full roster to `canOps(me)`.

**M3. Inbound lead/email webhook secrets are optional and compared non-constant-time.** `server.js:2861, 2940, 2963`
Plain `!==` (timing side-channel), and when no secret is configured the check is skipped — an unconfigured source accepts unauthenticated lead/event injection.
**Fix:** require a secret and use `crypto.timingSafeEqual` (your Calendly handler at ~2891 is the good reference).

**M4. Operators can approve accounts.** `server.js:~3355`
`approve` is gated by admin-OR-operator, while disable/role-change require admin. Confirm this is intended.

**M5. Demo + Zoom credentials in client source.** `public/index.html:8782` (`RidgeDemo2026!`), `6128` (Zoom passcode)
Standing credentials anyone can read.
**Fix:** sandbox the demo account; don't print live meeting passcodes into shipped HTML.

---

## ⚪ Low / Hardening

- **L1. `esc()` doesn't escape single quotes** (`index.html:647`). No clean exploit found today, but any future single-quoted attribute becomes injectable. Add `'`→`&#39;`.
- **L2. AI/library link `href` not protocol-checked** (`index.html:9071, 6827`). A `javascript:` URL from the server-side library would execute on click. Validate http/https.
- **L3. Hardcoded master-admin emails in source** (`server.js:~5469`). Functional but brittle; move to env (`MASTER_ADMINS`).
- **L4. `POST /api/billing/settings` references `me` before it's declared** (~2817) — throws and returns 500 (fails closed, so not exploitable, but the route is broken).
- **L5. `POST /api/contacts` accepts client-set `assignedTo`** — a user can create a contact assigned to another producer. Validate against allowed owner keys.

---

## Verified NOT vulnerable (checked, clean)
- Service-role key is **not** exposed to the browser; client uses the publishable key only.
- **RLS is enabled on all 50+ tables** → the anon key returns nothing directly; data is reachable only through the authenticated server. (Advisors flag "RLS enabled, no policy" as INFO — that's deny-all, which is what you want here.)
- No hardcoded API keys; no `eval`/`Function`/`child_process`; no SQL string concatenation (parameterized Supabase client throughout).
- Calendly webhook fully verified (HMAC + timing-safe + replay window). Email click-tracker validates protocol before redirect. Wildcard CORS is limited to the public marketing chatbot with no credentials.
- `x-view-as` impersonation is gated to admin/manager and read-only.

---

## Recommended fix order (by ROI)
1. **Verify `REQUIRE_LOGIN=true`** (C1) — 30 seconds, mitigates the biggest class of risk.
2. **Deploy the tier-escalation fix** (C2, already done) + **enforce non-licensed server-side** (H5).
3. **Harden Stripe + Twilio webhooks to fail closed** (H1, H2).
4. **Add ownership checks to the generic by-id routes** (H3).
5. **Remove the hardcoded bulk/demo passwords** (H4, M5) and **bump nodemailer** (H6).
6. Gate `GET /setting` and team/hierarchy financials (M1, M2); timing-safe webhook secrets (M3).
