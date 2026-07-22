# Email Deliverability Fix — Stop Landing in Spam

**Diagnosed live on the DNS for each domain. The fix is mostly one record.**

---

## 1. THE #1 FIX — Add DMARC to pacificridgewayinsurance.com

This is the domain your team's company emails send from. It already has SPF ✓ and DKIM ✓,
but **no DMARC record** — that's what's sending mail to spam under Gmail/Yahoo's 2024 rules.

**Add this TXT record** at your DNS host (this domain is on Google Cloud DNS):

| Field | Value |
|-------|-------|
| Type  | `TXT` |
| Name / Host | `_dmarc` |
| Value | `v=DMARC1; p=none; rua=mailto:stevenson@pacificridgewayinsurance.com; adkim=r; aspf=r; pct=100` |
| TTL   | `3600` (or default) |

- Start with `p=none` (monitors, doesn't block — zero risk of breaking real mail).
- After ~1–2 weeks of clean delivery, tighten to `p=quarantine` (then later `p=reject`)
  by editing that one value. That's the "very secure" end state.

**That single record is the main thing standing between you and the inbox.**

---

## 2. What's ALREADY correct (no action needed)

`pacificridgewayinsurance.com`
- SPF ✓ `v=spf1 include:_spf.google.com ~all`
- DKIM ✓ (Google DKIM key published at `google._domainkey`)
- MX ✓ Google Workspace

`indexedannuitysecrets.com` — SPF ✓, DKIM ✓, DMARC ✓ (p=none)
`pacificridgeway.com` — DMARC ✓ (p=quarantine)

---

## 3. Signature — remove the spam trigger

Your current signature wraps the LinkedIn link in a `fub.direct/1/...` tracking redirect.
**Redirect/shortener links are a top spam signal.** Use plain, direct URLs instead.

### Clean signature (paste into CRM → Settings → Email signature):

```
Gregory Stevenson
CEO & Founder, Pacific Ridgeway Insurance Solutions
Licensed Financial Professional · License #4132743
Business: 619-374-8100

Web:      https://pacificridgeway.com
Personal: https://gregorystevensonfinancial.com
IAS:      https://www.IndexedAnnuitySecrets.com
LinkedIn: https://www.linkedin.com/in/gregory-stevenson-financial-services

Confidentiality Notice: This transmission is privileged and confidential and may
contain protected health information (PHI) under HIPAA. It is intended only for the
addressee. If you are not the intended recipient, any use, distribution, or copying
is prohibited. If received in error, please reply to notify the sender and delete it.
```

---

## 4. Other deliverability hygiene (helps, optional)

- **Resend fallback:** the CRM falls back to Resend for system mail. Whatever address is set
  as `EMAIL_FROM` must be a domain **verified in Resend** (its own SPF + DKIM records added),
  or those specific messages will spam. Since per-agent Gmail is now the primary path, this
  only affects automated/sequence mail.
- Avoid ALL-CAPS subject lines, single big image with no text, and link shorteners.
- Warm up new sending addresses gradually (don't blast 500 cold emails day one).
