# Aurora Download Manager — website

Static donation / project site, deployed on **Cloudflare Pages** (free tier).

- `index.html` — single self-contained page (no build step, no frameworks, no trackers).
- `_redirects` — makes `/donation` (and `/donation/`) serve the same page as `/`.
- `FUNDING.yml` (repo root) — F-Droid donation-link verification signal; points at the site.

## Deploy (Cloudflare dashboard, ~5 min)

1. **Create the Pages project**
   - cloudflare.com → Workers & Pages → Create → Pages → *Connect to Git*
     (repo `52191314/Aurora_Download_Manager`, branch `master`, build command: none,
     output directory: `website`) — every push to `master` auto-deploys.
   - Or *Direct Upload*: drag the `website/` folder contents in.
2. **Attach the custom domain**
   - Pages project → Custom domains → Add `ahjie521.store` and `www.ahjie521.store`.
   - Cloudflare auto-creates the CNAME records. Note: the zone currently has
     **zero DNS records** (the domain does not resolve yet), so this step is
     what actually brings the site online.
3. **Verify**
   - `curl -I https://ahjie521.store/donation` → 200, and
   - `curl -I https://ahjie521.store/` → 200.

## F-Droid note

- F-Droid Inclusion Policy (Security & Legal Compliance): *"All donation links need
  verification by upstream developers… The application's main website can also host
  donation links."* Hosting the Donate link on this site is explicitly sanctioned.
- Add `Donate: https://ahjie521.store/donation` to the app's F-Droid metadata
  (in the fdroiddata fork) once the site is live.

## Content rules (why the page sells nothing)

- The page must stay **donation-only**. The Play build must never link to a page
  that sells/unlocks digital features (`docs/play_store_compliance.md`); a pure
  thank-you/donate page is fine, a storefront is not. The OSS edition is fully
  unlocked anyway, so there is nothing to sell.
- No analytics/tracking scripts on this page (privacy-first, matches the app).

## TODO before going live

- [ ] Replace PayPal / Ko-fi / Buy Me a Coffee placeholder links in `index.html`
- [ ] Optional: replace the placeholder TRON (USDT) address, or drop the crypto line
- [ ] Uncomment `github:` in `FUNDING.yml` if the GitHub account has Sponsors enabled
