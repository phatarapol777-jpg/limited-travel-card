# Development plan: platform fixes, module gaps, merchant partners (module 6)

Order matters: phase 0 changes things every module relies on, so it goes first. Each phase ends with tests and a local commit.
Nothing is pushed or deployed until the owner says so.

## Decisions (from the gap analysis)
1. Merchants submit their shop **inside the app** (like quests); admins review in the Node admin dashboard.
2. The Node admin (Render) is the main admin. The PHP admin on the university host only gets a **read-only summary** of the new modules.
3. Images stay in the database but are **small** (hard caps per field and per shop); snapshots are spaced at least 60 s apart.
4. Quest claims check GPS (about 1 km around the attraction), switchable from the admin dashboard.

## Phase 0: platform
| # | Item | Notes |
|---|------|-------|
| 0.1 | Change password | min 8 chars, ends all other sessions; banner while the admin still uses the seed password. No boot logic rewrites the live password. |
| 0.2 | Login rate limit | keyed on username (the proxy IP is client-controlled), short window, never a permanent lock |
| 0.3 | Session expiry + logout | 30 days; server logout; the app handles 401 in one place (back to login); PHP logout calls the server |
| 0.4 | Settings table | `ENV_CHECK`, quest GPS on/off and radius editable in the dashboard; env vars are only defaults; survives restores |
| 0.5 | Account deletion | anonymise (foreign keys), cancel trades both ways, drop pins/sessions/notifications, close quests, suspend shops; not for admins |
| 0.6 | Retention + backup status | purge check-in face photos after 30 days; last backup time/size/error in the dashboard; `/api/health` carries a version |

## Phase 1: gaps in existing modules
- Kiosk: disable a kiosk, rotate its key (version 0 keeps the current derivation)
- Quests: creator edits and resubmits after a rejection, creator closes own quest, GPS check
- Cards: printable QR sheet (made in the browser), notify people who tapped "order physical card" (once), `VOIDED` card status handled everywhere
- Community: admin hides / restores posts

## Phase 2: merchants and card privileges (module 6)
- Tables: merchants (+ pending revision), gallery, catalog items, privileges (indexed by card template), opening hours
- API: submit / edit (as a revision) / my shops / public list / detail / card picker / partners of a card
- Admin: approve, reject with reason, suspend
- App: shop form with map pin picker, hours editor, items, privileges; my shops; map pins by category with a gift badge and filters; shop drawer; partners on the card page sorted by distance; "show to staff" screen
- Old `shops` rows migrated once (idempotent)

## Phase 3: PHP admin summary (read-only counts for quests, merchants, packs)

## Testing rules
Backend tests for every phase (`npm test`), Flutter tests for pure logic, in-browser checks for the screens.
Probes against the live server are read-only.
