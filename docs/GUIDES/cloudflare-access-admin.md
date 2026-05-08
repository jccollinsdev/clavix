# Cloudflare Access Setup for /admin

The admin dashboard is currently publicly reachable at `https://clavis.andoverdigital.com/admin/`.
While it requires a password to use, adding Cloudflare Access provides defense-in-depth: IP-level
blocking before traffic even reaches the backend.

## Recommended: Cloudflare Access Application

This is the preferred approach. It adds zero-trust authentication at the Cloudflare edge before
traffic reaches the VPS.

### Steps

1. **Go to Cloudflare Zero Trust Dashboard**
   - Log in at https://one.dash.cloudflare.com/
   - Navigate to: Access → Applications

2. **Create an Access Application**
   - Click "Add an application" → "Self-hosted"
   - **Application name:** `Clavis Admin`
   - **Session Duration:** 12 hours
   - **Application domain:** `clavis.andoverdigital.com`
   - **Path:** `/admin/*`
   - This creates a policy that only applies to `/admin/` and `/admin/api/` paths

3. **Create an Access Policy**
   - **Policy name:** `Admin operators`
   - **Action:** Allow
   - **Include rule:** Email ending in `@andoverdigital.com`
     (or specific email addresses for tighter control)
   - OR: IP list rule if you have static IPs (`Add require` → `IP Source`)

4. **Configure bypass for login endpoint**
   - The `/admin/login` POST needs to be reachable for the first authentication
   - Create a second policy that **allows** the path `/admin/login` without
     Cloudflare Access, or make the app cover `/admin/*` except `/admin/login`
   - Alternatively: create the app for `/admin/api/*` only (the login and
     HTML shell are low-risk since they don't expose data)

5. **Verify**
   - Visit `https://clavis.andoverdigital.com/admin/` from an incognito window
   - You should be prompted for Cloudflare Access authentication
   - After authenticating, the admin login form should appear
   - API endpoints should also require Cloudflare Access headers

## Alternative: IP Allowlist via Cloudflare WAF

If Cloudflare Access is too complex, a WAF rule can block `/admin/*` from non-whitelisted IPs.

1. Go to your Cloudflare dashboard → Security → WAF → Custom Rules
2. Create a rule:
   - **Expression:** `(http.request.uri.path starts with "/admin") and (not ip.src in {YOUR_IP})`
   - **Action:** Block
3. This is simpler but less secure (IP spoofing is possible at the CDN level, though Cloudflare mitigates this)

## Current Status

- `/admin/` is publicly accessible (HTML shell only, no data)
- `/admin/api/*` requires session cookie (HMAC-signed, 12-hour expiry)
- Login has per-IP rate limiting (5 attempts → 15-min lockout)
- POST actions require CSRF double-submit cookie
- Emails are masked in all responses
- No Cloudflare Access or WAF rule is currently in place

## What Cloudflare Access Adds

- Zero-trust authentication before traffic reaches the VPS
- Prevents any unauthenticated user from even seeing the login form
- Audit trail in Cloudflare (who accessed, when, from where)
- Can be combined with hardware key (WebAuthn) or OTP requirement