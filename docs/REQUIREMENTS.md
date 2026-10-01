# Balustrading Concepts CRM — Requirements

**Status:** Draft v0.1 for discussion · **Last updated:** 1 October 2026

One system that takes a job from website enquiry → site survey → per-metre quote → online acceptance and
deposit → Unex order → install → final invoice, with Xero as the accounting system and a customer portal
for accepting quotes and paying deposits.

Requirement IDs (e.g. `QTE-3`) are for referencing in issues and PRs. Items marked **(v2)** are agreed
as wanted but out of the first release.

---

## 1. Business context

| Topic | Decision |
|---|---|
| Location / service area | Auckland, Auckland-wide. No travel zones in v1; out-of-the-ordinary trips (e.g. Waiheke) are a manual extra line. |
| Users | Up to 10 staff. Installers are in-house. |
| Customers | Mix of homeowners and trade (builders, architects, developers, commercial). |
| Supplier | Unex. Unex's engineer provides engineering (PS1) where a job needs it. |
| Pricing | Fixed $/m rate per system, plus priced extras. Calculated from survey measurements. |
| Accounts | Xero (NZ org). The CRM pushes contacts and invoices; Xero stays the ledger. |
| Retail terms | 50% deposit on acceptance, balance on completion. |
| Trade terms | On account, due the 20th of the month following invoice. |

## 2. Locale conventions

- Currency NZD. **GST 15%.** All prices stored **excluding GST**; GST calculated per document.
- Dates `DD/MM/YYYY`, time zone `Pacific/Auckland`.
- Metric: lengths in metres (2 dp), heights in millimetres.
- NZ addresses (street, suburb, city, postcode) with autocomplete via Addressfinder.
- Phone numbers stored in E.164 (`+64…`), displayed in NZ format.

## 3. Users and roles

A staff member can hold more than one role (e.g. a surveyor who also installs).

| Role | Can do |
|---|---|
| **Admin** | Everything, incl. price book, settings, users, Xero/Stripe connections, overrides. |
| **Office / Sales** | Contacts, jobs, quotes, scheduling, invoicing, reports. No settings/users. |
| **Surveyor** | Their surveys: measurements, photos, notes; draft quotes from their runs. |
| **Installer** | Only jobs they're crewed on: site details, runs, materials, photos, snags, sign-off. |
| **Customer** (portal) | Only their own jobs (or their company's jobs, for trade contacts). |

## 4. Job lifecycle

A **job** is the central record. An enquiry is simply a job at the first stage, so nothing is
re-keyed when it converts.

```
Enquiry → Survey booked → Surveyed → Quoted → Accepted → [Deposit paid] → Ordered (Unex)
  → Materials received → Install scheduled → Installed → Complete → Closed (fully paid)
                                  ↘ Lost (reason) / Cancelled
```

- **JOB-1** Stages can be moved manually; system events also move them (quote sent → *Quoted*,
  accepted online → *Accepted*, deposit paid → *Deposit paid*, final invoice paid → *Closed*).
- **JOB-2** *Deposit paid* applies to retail jobs only. Trade jobs go *Accepted → Ordered*.
- **JOB-3** A retail job cannot move to *Ordered* until the deposit is paid. An Admin can override
  with a reason, which is logged.
- **JOB-4** Moving to *Lost* requires a reason (price, timing, went elsewhere, no response, other).
- **JOB-5** Every job has a job number (`BC-00001`), an owner (staff member), and a follow-up date.

## 5. Functional requirements

### 5.1 Contacts, companies and addresses

- **CON-1** People: name, mobile, other phone, email, preferred contact method, notes, marketing consent.
- **CON-2** Companies: name, type (builder, architect, developer, property manager, commercial, other),
  phone, email, billing address. A person can belong to a company.
- **CON-3** Pricing tier (retail / trade) and payment terms (*deposit then balance* /
  *on account – 20th of following month*) sit on whoever is billed: the company for trade jobs, the
  person for homeowners. Deposit % can be overridden per customer.
- **CON-4** Duplicate detection on email and mobile when creating contacts (including from the website).
- **CON-5** One-off import of existing contacts from Xero, linked by Xero ContactID.
- **CON-6** Contact and company pages show all jobs, quotes, invoices, documents and activity.

### 5.2 Enquiries and pipeline

- **ENQ-1** Website enquiries arrive automatically as new jobs at *Enquiry* (see 5.15).
- **ENQ-2** Manual entry for phone/email/walk-in enquiries in under a minute.
- **ENQ-3** Lead source from an editable list (Website, Phone, Referral, Repeat customer,
  Builder/trade, Builderscrack, Google, Facebook/Instagram, Signage/vehicle, Other) plus a free-text detail.
- **ENQ-4** Pipeline board (columns by stage, drag to move) and list view with filters (stage, owner,
  source, retail/trade, date).
- **ENQ-5** Overdue follow-ups highlighted; "no contact within 24 h of enquiry" flagged.

### 5.3 Site survey and measurements

- **SRV-1** Book a survey: date/time, surveyor, customer confirmation email + SMS, reminder the day before.
- **SRV-2** Works well on a phone on site.
- **SRV-3** Record one or more **runs** per job:
  label (e.g. "Front deck"), system, length (m), height (mm), substrate
  (timber, concrete, steel, tile over concrete, membrane deck, other), and how each end finishes
  (wall, end post, corner, open).
- **SRV-4** Photos and sketches attached to the job (camera upload from phone).
- **SRV-5** Site access notes: parking, gate codes, dogs, floor level, stairs, power.
- **SRV-6** Building consent needed? If so, who holds it (owner / builder) and the consent number.
- **SRV-7 (v2)** Offline capture when there's no signal; syncs when back online.

### 5.4 Price book

- **PRC-1** **Systems** (e.g. frameless glass on spigots, channel-set glass, aluminium post-and-glass,
  aluminium picket, Juliet balcony, pool fence): retail $/m, trade $/m, standard height, height surcharge
  ($/m per 100 mm over standard), Unex product reference, Xero item and account codes, active flag.
- **PRC-2** For materials estimates, each system can store max panel width and max post spacing.
- **PRC-3** **Extras** (gates, corners, wall fixings, handrail upgrades, core drilling, scaffold,
  removal/disposal, out-of-area travel, etc.): unit (each / per m / per post / per job), retail and trade
  price, and an optional auto-apply rule (per corner, per wall end, per open end, per post — optionally
  only for a given substrate or system).
- **PRC-4** Global settings: GST rate, default deposit %, minimum job charge, quote validity (default
  30 days), length rounding (default up to nearest 0.1 m), quote terms & conditions text.
- **PRC-5** Price changes don't alter quotes already sent.
- **PRC-6 (v2)** Cost prices from Unex for margin reporting.

### 5.5 Quote calculator

Runs the moment runs are entered. Rules:

1. Each run's length is rounded **up** to the rounding step (default 0.1 m).
2. **Line per run:** `length × system rate` using the customer's tier (retail or trade).
3. **Height surcharge:** if height > the system's standard height,
   `length × surcharge rate × ceil((height − standard) / 100)`.
4. **Auto extras** are counted from the runs:
   - corners: run ends marked *corner*, ÷ 2 (each joint counted once);
   - wall ends and open ends: counted directly;
   - per-post extras: estimated post count × the extra, where the substrate/system filter matches.
5. **Manual lines** can be added (any extra, or free text) and any line can be overridden. Discounts are
   a negative manual line with a reason.
6. If the subtotal is under the minimum job charge, a "Minimum charge" line tops it up.
7. **GST** = 15% of the subtotal. **Total** = subtotal + GST.
8. **Deposit** (retail) = deposit % × total incl. GST, rounded to the cent; balance = total − deposit.

**Materials estimate** (internal only, for ordering): per run, panels = `ceil(length / max panel width)`;
posts = `ceil(length / max post spacing) + 1`, less one per shared corner. Final quantities follow
Unex's design.

> **Worked example (example rates only).** Retail customer, frameless glass at $650/m, standard height
> 1000 mm. Front deck 8.3 m (wall → corner) and side deck 4.1 m (corner → open), both 1000 mm.
>
> | Line | Qty | Rate | Amount |
> |---|---|---|---|
> | Frameless glass – Front deck | 8.3 m | $650.00 | $5,395.00 |
> | Frameless glass – Side deck | 4.1 m | $650.00 | $2,665.00 |
> | Corner | 1 | $120.00 | $120.00 |
> | Wall fixing | 1 | $85.00 | $85.00 |
> | **Subtotal (excl. GST)** | | | **$8,265.00** |
> | GST 15% | | | $1,239.75 |
> | **Total (incl. GST)** | | | **$9,504.75** |
> | Deposit 50% | | | $4,752.38 |
> | Balance on completion | | | $4,752.37 |

### 5.6 Quotes

- **QTE-1** Branded PDF quote: customer and site, run-by-run breakdown, extras, GST, total, deposit and
  terms, validity date, photos/sketch optional.
- **QTE-2** Statuses: draft → sent → viewed → accepted / declined / expired; *superseded* when a new
  version is issued.
- **QTE-3** Once sent, a quote is locked. Changes create a new version (`Q-00042 v2`); earlier
  versions stay readable.
- **QTE-4** Send by email with a portal link; the system records when it's opened.
- **QTE-5** Automatic reminders: follow-up task 3 days after sending, warning 5 days before expiry.
- **QTE-6** Accepting a quote (online or marked accepted by staff) records name, time and IP, and
  snapshots the T&Cs it was accepted under.

### 5.7 Customer portal

- **PRT-1** Passwordless login (magic link to the customer's email). No account setup needed.
- **PRT-2** The customer can see their jobs and status in plain language (e.g. "Materials ordered —
  install booked for 14/11/2026").
- **PRT-3** View and **accept the quote online** (tick to accept T&Cs, type their name).
- **PRT-4** **Pay the deposit by card** straight after accepting (or later), or see bank-transfer
  details with the reference to use.
- **PRT-5** Download quote, invoices, PS1/PS3 where relevant, warranty and care guide.
- **PRT-6** Upload photos or plans (e.g. before the survey).
- **PRT-7** Trade contacts see all jobs for their company.
- **PRT-8 (v2)** Approve variations online; pay the final invoice by card.

### 5.8 Payments

- **PAY-1** Card payments via **Stripe Checkout** (NZD, cards, Apple Pay / Google Pay).
- **PAY-2** On successful payment (Stripe webhook): mark the deposit paid in the CRM, record the payment
  against the deposit invoice in Xero (into a *Stripe clearing* account), move the job to
  *Deposit paid*, and notify the office.
- **PAY-3** Bank transfers are reconciled in Xero as normal; the CRM picks up the paid status from Xero.
- **PAY-4** Partial payments are supported; balance outstanding is always visible on the job.

### 5.9 Xero integration

- **XRO-1** Connect one Xero organisation via OAuth 2.0 (Admin only); tokens kept server-side and
  refreshed automatically.
- **XRO-2** Contacts: when a job is first invoiced, find the Xero contact by stored ContactID, or by
  email/name, else create it. Trade companies get Xero payment terms *20th of the following month*.
- **XRO-3** Invoices pushed as Xero sales invoices (ACCREC), prices exclusive, GST on income 15%,
  item and account codes from the price book.
  - Retail: **deposit invoice** on acceptance (50%); **final invoice** for the balance plus approved
    variations on completion.
  - Trade: **single invoice** on completion, due the 20th of the following month.
- **XRO-4** Invoices created as **Draft** in Xero by default (so the office can check them for the
  first few weeks), switchable to **Approved** in settings.
- **XRO-5** Paid status pulled back from Xero (Xero webhooks plus a nightly sync). Jobs with all
  invoices paid move to *Closed*.
- **XRO-6** Sync errors are shown on the job and in an admin log; nothing fails silently.

### 5.10 Supplier orders (Unex)

- **ORD-1** From an accepted quote, generate a materials list (from the estimate in 5.5, editable).
- **ORD-2** Record the Unex order: order reference, date ordered, expected delivery, deliver to
  site or yard, notes.
- **ORD-3** Track status: draft → ordered → confirmed → delivered. Delivered moves the job to
  *Materials received*.
- **ORD-4** Reminder when delivery is due; flag overdue deliveries; warn if an install is booked
  before expected delivery.
- **ORD-5 (v2)** Email the order to Unex from the CRM in their preferred format.

### 5.11 Compliance and documents

- **CMP-1** Compliance checklist per job, each item *not required / required / requested / received /
  issued*, with a file and dates:
  - Building consent (held by owner/builder; consent number)
  - **PS1** — design, from Unex's engineer
  - **PS3** — construction, issued by Balustrading Concepts
  - PS4 — construction review, if council requires it
  - LBP record of work, where applicable
- **CMP-2** Track when the PS1 was requested from Unex and chase it if outstanding.
- **CMP-3** Warn before marking a job *Complete* while a required item is outstanding.
- **CMP-4** Documents: survey/progress/completion photos, drawings, quotes, invoices, PS documents,
  consents, warranty. Each can be marked *visible to customer* and *OK for website*.
- **CMP-5 (v2)** Generate the PS3 and warranty certificate from templates.

### 5.12 Install scheduling

- **INS-1** Calendar (week and month) of installs and surveys by crew member.
- **INS-2** Book an install: start date, duration (half-days allowed), crew members. Warn on clashes
  and if materials aren't due yet.
- **INS-3** Customer gets the install date by email + SMS, and a reminder the day before.
- **INS-4** Installer mobile view: today's jobs, address with map link, access notes, runs, materials
  list, photos, customer phone (tap to call).
- **INS-5** Google Calendar sync for staff calendars (if you use Google Workspace — to confirm).

### 5.13 Completion and final invoice

- **CMPL-1** Installer uploads completion photos and logs any snags.
- **CMPL-2** Customer sign-off on the installer's phone (name + signature), which starts the warranty.
- **CMPL-3** Variations (extra work or changes after acceptance) recorded on the job with an amount and
  added to the final invoice.
- **CMPL-4** Marking the job *Complete* creates the final invoice (retail) or the full invoice (trade)
  in Xero.
- **CMPL-5 (v2)** Review request email a few days after completion; warranty and maintenance reminders.

### 5.14 Activity, tasks and notifications

- **ACT-1** Timeline on every job and contact: notes, calls, emails, SMS, stage changes, quote and
  payment events — who did what and when.
- **ACT-2** Tasks with due dates and an assignee; "My tasks" list on login.
- **ACT-3** Email templates: enquiry auto-reply, survey confirmation, quote sent, quote reminder,
  deposit receipt, install date, install reminder, completion/thank-you.
- **ACT-4** Staff notifications (in-app + email): new enquiry, quote viewed, quote accepted, deposit
  paid, delivery due, overdue follow-up.
- **ACT-5 (v2)** Log Gmail threads against contacts automatically.

### 5.15 Website integration

- **WEB-1** The website's enquiry form posts to a CRM endpoint: name, email, phone, address/suburb,
  project type, message, photos, plus page and UTM source.
- **WEB-2** Spam protection (honeypot + Cloudflare Turnstile or similar); endpoint authenticated with a
  shared secret.
- **WEB-3** Creates or matches the contact (CON-4), creates the job at *Enquiry*, sends the customer an
  auto-reply and notifies the office.
- **WEB-4 (v2)** Completion photos marked *OK for website* feed the website's gallery.

### 5.16 Dashboard and reports

- **RPT-1** Dashboard: new enquiries this week, pipeline value by stage, quotes awaiting response,
  deposits outstanding, deliveries due, surveys and installs this week.
- **RPT-2** Quote conversion rate (count and value) by month, by salesperson, by retail/trade.
- **RPT-3** Enquiries and won jobs by lead source.
- **RPT-4** Revenue by month and by system type (from accepted quotes and invoices).
- **RPT-5** Lost reasons breakdown.
- **RPT-6** Export any list to CSV.
- **RPT-7 (v2)** Job margin (quoted vs Unex cost + labour).

## 6. Non-functional requirements

- **Security:** staff login with email + password or magic link, MFA available (required for Admin).
  Database row-level security on every table; customers can only ever reach their own records.
  Files in private storage with expiring links. Stripe and Xero webhooks signature-verified.
- **Privacy (Privacy Act 2020):** collect only what's needed; customers can request their data;
  breach process documented. Marketing emails only with consent.
- **Record keeping:** financial records kept at least 7 years (IRD). Soft-delete for jobs, quotes and
  invoices; full audit log of changes to jobs, quotes, invoices and payments.
- **Hosting:** data hosted in the Sydney region (closest to NZ). Daily backups with point-in-time
  recovery.
- **Mobile:** every surveyor and installer screen usable one-handed on a phone; office screens
  designed for desktop.
- **Performance:** pages load in under 2 s on 4G; quote recalculates instantly as runs are typed.
- **Accessibility:** WCAG 2.1 AA for the customer portal.

## 7. Proposed technology

Balustrading Concepts already uses **Cloudflare**, so the app is hosted there alongside the website.

| Part | Choice | Why |
|---|---|---|
| App | Next.js (TypeScript) | One codebase for staff app, portal and API routes. |
| Hosting | **Cloudflare Workers** (via the OpenNext adapter) | Same account as the website; preview URL per change. |
| Domain / DNS | **`portal.balustrading.co.nz`** on Cloudflare — customers at `/`, staff at `/staff` | One app, one domain, already managed there. |
| Scheduled jobs | Cloudflare Cron Triggers | Nightly Xero sync, quote/delivery/install reminders. |
| Spam protection | Cloudflare Turnstile | Website enquiry form and portal login. |
| Extra staff protection (optional) | Cloudflare Access on the `/staff` path | Second login layer for staff only; customer pages stay public. |
| Database / auth / files | Supabase (Postgres, Sydney region) | Row-level security for the portal, magic-link login, file storage. |
| Payments | Stripe | NZD cards + Apple/Google Pay; hosted checkout keeps card data off our servers. |
| Accounts | Xero API | Existing system. |
| Email | Resend or Postmark | Transactional email with open tracking. |
| SMS | Twilio (or NZ provider) | Survey/install confirmations and reminders. |
| Addresses | Addressfinder | NZ address autocomplete. |
| PDFs | Server-side React PDF | Branded quotes and invoices. |

**Why not all-Cloudflare (D1 + R2)?** D1 is SQLite with no row-level security and no built-in user
login, so the customer portal's "only see your own jobs" guarantee and the staff/customer logins would
all have to be hand-built. Supabase gives both out of the box and works well from Workers. Cloudflare
R2 remains an option later for photo storage if volumes grow (no egress fees).

To confirm once we've seen the website repo: its framework, and whether it's on Cloudflare Pages or
Workers — sharing components and branding with it may shift the framework choice.

Draft database schema: [`schema-draft.sql`](schema-draft.sql).

## 8. Release plan

**v1** (in build order — each milestone usable on its own):

1. **Foundation:** staff login and roles, contacts/companies, jobs and pipeline, Xero contact import,
   website enquiry endpoint.
2. **Survey and quoting:** survey booking, runs and photos on mobile, price book, quote calculator,
   PDF quotes, quote emails.
3. **Portal and payments:** customer portal, online acceptance, Stripe deposits, Xero deposit invoices,
   paid status from Xero.
4. **Delivery:** Unex orders, compliance checklist, install calendar, installer mobile view, sign-off,
   variations, final invoices.
5. **Insight:** dashboard and reports, reminders and notifications polish.

**v2:** offline survey capture, Unex cost prices and job margin, emailing orders to Unex, PS3/warranty
templates, variation approval and final payment in the portal, review requests, warranty/maintenance
reminders, Gmail logging, website gallery feed.

**Later / maybe:** Construction Contracts Act payment claims and retentions for larger commercial jobs.

## 9. Assumptions and open questions

Assumptions made in this draft — please correct any that are wrong:

1. **Trade customers pay no deposit** and are invoiced in full on completion (deposit % can be set
   per company if some do).
2. Unex's engineer issues the **PS1**; Balustrading Concepts issues the **PS3**; the owner or builder
   holds any building consent.
3. No travel pricing inside Auckland; anything unusual is a manual extra.
4. Quotes are valid for 30 days.

Open questions:

1. **Website repo** — what's it built with (it's on Cloudflare — Pages or Workers?), and can we look at
   it to wire up the enquiry form?
2. **Unex ordering** — how do you order today (their portal, email, spreadsheet)? Do you want their
   cost prices stored for margin reporting?
3. **Price book** — list of systems, $/m rates (retail and trade), standard heights, extras, and the
   minimum job charge.
4. **Card fees** — absorb them, or add a surcharge on card payments?
5. **Google Workspace** — do staff use Google Calendar (for INS-5)?
6. **Existing data** — beyond Xero contacts, is there a spreadsheet of open jobs/quotes to import?
7. **Branding** — logo, colours and your current quote T&Cs for the quote PDF and portal.
8. **Commercial jobs** — do any head contractors hold retentions or require formal payment claims?
