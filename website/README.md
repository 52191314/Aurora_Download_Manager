# Aurora Download Manager — website

Static landing and donation site, deployed on **Cloudflare Pages** (free tier).

- `index.html` — main landing page showcasing Aurora Download Manager features and downloads.
- `donation.html` — dedicated voluntary support and donation page with glitch-free responsive mobile layout.
- `_redirects` — routes `/donation` and `/donation/` to `donation.html`.
- `FUNDING.yml` (repo root) — F-Droid donation-link verification signal; points at the site.

## Deploy (Cloudflare dashboard)

1. **Create the Pages project**
   - cloudflare.com -> Workers & Pages -> Create -> Pages -> *Connect to Git*
     (repo `52191314/Aurora_Download_Manager`, branch `master`, build command: none,
     output directory: `website`) — every push to `master` auto-deploys.
   - Or *Direct Upload*: upload the `website/` directory contents.
2. **Attach the custom domain**
   - Pages project -> Custom domains -> Add `ahjie521.store` and `www.ahjie521.store`.
3. **Verify**
   - `curl -I https://ahjie521.store/` -> 200 (Main landing page)
   - `curl -I https://ahjie521.store/donation` -> 200 (Donation page)

## F-Droid note

- F-Droid Inclusion Policy (Security & Legal Compliance): *"All donation links need verification by upstream developers... The application's main website can also host donation links."* Hosting the Donate link on this site is explicitly sanctioned.
- Add `Donate: https://ahjie521.store/donation` to the app's F-Droid metadata once the site is live.

## Content rules

- The donation page must remain voluntary-only with no digital feature unlocks (per Google Play Store policy guidelines).
- No analytics/tracking scripts on the site (privacy-first, matching the app).
