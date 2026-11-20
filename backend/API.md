# API overview

All `/api` routes require a Bearer token except register/login. Create a clinician account through the local CLI, never public registration.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | /health | Server readiness and OCR configuration |
| POST | /api/auth/register | Patient account creation |
| POST | /api/auth/login | Patient/clinician sign-in |
| POST | /api/auth/logout | Revoke current session |
| GET | /api/state | Patient snapshot and revision |
| POST | /api/sync | Idempotent, revision-checked patient snapshot update |
| POST | /api/documents | Multipart validated image upload, encryption and optional OCR |
| GET | /api/documents | Signed-in patient's document metadata |
| GET | /api/documents/{id} | Owner/consented care-team image access |
| POST | /api/cases | Submit a consented record snapshot and selected documents |
| GET | /api/cases | Own patient cases or care-team queue |
| PATCH | /api/cases/{id} | Clinician review note/status with revision check |
| POST | /api/cases/{id}/withdraw | Patient withdrawal of future sharing access |
| GET | /api/operations | Clinician-only current queue statistics |
| GET | /api/audit | Clinician-only audit history |
| POST | /api/knowledge/drafts | Clinician creates immutable reference draft |
| GET | /api/knowledge/manage | Clinician source history, rights and review notes |
| POST | /api/knowledge/{id}/review | Revision-checked approval, rejection or withdrawal |
| POST | /api/knowledge/search | Exact approved source passages; query in JSON body |
| GET | /api/knowledge/pack | Current approved passages for 24-hour offline reading |
| GET | /api/knowledge/{id} | Current approved source text and citation |
| GET | /care-team | Care-team dashboard |
| GET | /openapi.json | Machine-readable API schema |

Money is stored in integer minor units (100 paisa per BDT). Medical entries remain patient-provided until reviewed; clinician notes do not overwrite them.

The sync endpoint rejects stale versions instead of silently taking last-write-wins. The client coalesces local edits into a pending snapshot and retains its event ID for retries. Conflicts require explicit user resolution. This release is intended for a single care team; it does not implement hospital/organisation tenancy.

Reference search accepts `query`, `language` (`all`, `en`, `bn`) and `limit` (1–10). Queries are limited to 300 characters and 20 unique word tokens; all tokens must match. There is no answer generation. Draft, expired, rejected, withdrawn and superseded sources are excluded. Search text is not stored in the audit log. Reference author and approver must be different clinician accounts. See REFERENCE_LIBRARY.md.

## Medicine workflow (API version 1.2.0)

| Method | Path | Purpose |
| --- | --- | --- |
| GET | /api/extraction/capabilities | Reports whether the structured local OCR adapter is configured |
| POST | /api/documents/{id}/extract | Owner-only structured model call; no automatic medicine insertion |
| POST | /api/market/search | Public supplier-search candidates when server-rendered; returns native supplier-search URL otherwise |
| POST | /api/market/quote | Fetch an exact public Arogga product listing and save an account-scoped encrypted quote |
| POST | /api/shopping/plan | Revision-checked whole-quantity/whole-pack budget estimate using server-owned quote data |
| POST | /api/pharmacies/nearby | Authenticated bounded OSM pharmacy lookup; no location history persisted |

Quote request: `{"product_url":"https://www.arogga.com/product/ID/SLUG"}`. Only exact HTTPS supplier product URLs are accepted. Redirects are not followed. The displayed primary pack and structured BDT price must agree. A quote carries `quote_id`, source URL, product/variant IDs, strength, form, base unit, units per pack, exact pack price in paisa, unit estimate, availability and check/expiry timestamps. Source HTML can be cached for two minutes; quote expiry is measured from the original source check.

The medicine snapshot now supports `purchased`, `price_confirmed`, `quantity_unit`, `quote_id`, `product_match_confirmed` and bounded `price_quote` display metadata. Backend shopping calculations ignore client-supplied quote metadata and resolve the actual quote by ID within the authenticated account. Old patient snapshots remain readable; the new fields have defaults. Changing medicine identity in the UI invalidates its product match and avoids silently carrying its old price to a different medicine.

Plan request: `{"base_version":N,"budget_minor":null,"delivery_minor":0,"selected_ids":null}`. A null budget means no user-imposed limit; zero is a valid zero budget. Null selected IDs automatically consider items in medicine-list order; an explicit list considers only those selections. Already purchased items are excluded. Unreviewed/unpriced/unmatched/out-of-stock items cannot silently enter an assisted cart. Prescribed quantities never change. Whole packs may supply surplus units. Manual-price estimates cannot claim supplier-cart eligibility. Duplicate supplier product matches disable automated preparation until reviewed.

The response distinguishes a complete `full_total_minor` from `known_full_total_minor` when some prices are missing, and includes rows/reasons, selected totals, delivery reserve, shortfall, individual affordability and incomplete/cart-ready flags. Prices can change after quoting. No route places supplier orders, uploads a prescription to a retailer, captures payment details or processes payment.

Pharmacy requests carry latitude/longitude/radius in a POST body. Radius is 500–10,000m. Results are actual mapped locations sorted by approximate straight-line distance, without stock/open-now guarantees. Searches use fixed-provider endpoints and a 15-minute in-memory cache; query coordinates are not recorded in the application audit log.
