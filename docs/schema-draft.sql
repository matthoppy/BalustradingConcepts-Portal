-- Balustrading Concepts CRM — draft database schema (Postgres / Supabase)
--
-- Status: DRAFT for review alongside docs/REQUIREMENTS.md. Not yet a migration.
-- Conventions:
--   * Money is NZD, numeric(12,2), stored EXCLUDING GST unless the column says *_incl_gst.
--   * Lengths in metres (numeric), heights in millimetres (int).
--   * Relies on Supabase's auth schema (auth.users, auth.uid()).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type staff_role            as enum ('admin', 'office', 'surveyor', 'installer');
create type company_type          as enum ('builder', 'architect', 'developer', 'property_manager', 'commercial', 'other');
create type pricing_tier          as enum ('retail', 'trade');
create type payment_terms         as enum ('deposit_then_balance', 'on_account_20th');
create type contact_method        as enum ('any', 'phone', 'sms', 'email');
create type job_stage             as enum (
  'enquiry', 'survey_booked', 'surveyed', 'quoted', 'accepted', 'deposit_paid',
  'ordered', 'materials_received', 'install_scheduled', 'installed', 'complete', 'closed',
  'lost', 'cancelled'
);
create type substrate_type        as enum ('timber', 'concrete', 'steel', 'tile_over_concrete', 'membrane_deck', 'other');
create type termination_type      as enum ('wall', 'end_post', 'corner', 'open');
create type extra_unit            as enum ('each', 'per_m', 'per_post', 'per_job');
create type extra_auto_rule       as enum ('manual', 'per_corner', 'per_wall_end', 'per_open_end', 'per_post');
create type quote_status          as enum ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired', 'superseded');
create type invoice_type          as enum ('deposit', 'final', 'full', 'progress');
create type invoice_status        as enum ('draft', 'submitted', 'authorised', 'paid', 'voided');
create type payment_method        as enum ('stripe', 'bank_transfer', 'other');
create type supplier_order_status as enum ('draft', 'ordered', 'confirmed', 'delivered', 'cancelled');
create type install_status        as enum ('scheduled', 'in_progress', 'done', 'postponed', 'cancelled');
create type document_kind         as enum (
  'survey_photo', 'progress_photo', 'completion_photo', 'drawing', 'quote_pdf', 'invoice_pdf',
  'ps1', 'ps3', 'ps4', 'building_consent', 'record_of_work', 'warranty', 'signature', 'other'
);
create type compliance_kind       as enum ('building_consent', 'ps1', 'ps3', 'ps4', 'record_of_work');
create type compliance_status     as enum ('not_required', 'required', 'requested', 'received', 'issued');
create type activity_type         as enum ('note', 'call', 'email', 'sms', 'meeting', 'stage_change', 'system');

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------

-- Staff profile for each Supabase auth user who works at Balustrading Concepts.
create table staff (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null,
  email       text not null unique,
  phone       text,
  roles       staff_role[] not null default '{office}',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table addresses (
  id               uuid primary key default gen_random_uuid(),
  line1            text not null,
  line2            text,
  suburb           text,
  city             text not null default 'Auckland',
  postcode         text,
  country          text not null default 'NZ',
  latitude         numeric(9,6),
  longitude        numeric(9,6),
  addressfinder_id text,
  created_at       timestamptz not null default now()
);

create table companies (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  type               company_type not null default 'other',
  pricing_tier       pricing_tier not null default 'trade',
  payment_terms      payment_terms not null default 'on_account_20th',
  deposit_percent    numeric(5,2) check (deposit_percent between 0 and 100), -- null = default for terms
  phone              text,
  email              text,
  billing_address_id uuid references addresses (id),
  xero_contact_id    uuid unique,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table contacts (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid references companies (id) on delete set null,
  first_name         text not null,
  last_name          text,
  job_title          text,
  email              text,
  mobile             text,                       -- E.164, e.g. +6421…
  phone              text,
  preferred_contact  contact_method not null default 'any',
  billing_address_id uuid references addresses (id),
  -- Used when this person is billed directly (homeowners). Trade jobs use the company's.
  pricing_tier       pricing_tier not null default 'retail',
  payment_terms      payment_terms not null default 'deposit_then_balance',
  deposit_percent    numeric(5,2) check (deposit_percent between 0 and 100),
  marketing_consent  boolean not null default false,
  xero_contact_id    uuid unique,
  portal_user_id     uuid unique references auth.users (id) on delete set null,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index contacts_email_idx   on contacts (lower(email));
create index contacts_mobile_idx  on contacts (mobile);
create index contacts_company_idx on contacts (company_id);

-- ---------------------------------------------------------------------------
-- Settings and price book
-- ---------------------------------------------------------------------------

-- Single-row settings table.
create table settings (
  id                      boolean primary key default true check (id),
  gst_rate                numeric(5,4) not null default 0.15,
  default_deposit_percent numeric(5,2) not null default 50,
  minimum_job_charge      numeric(10,2) not null default 0,
  quote_valid_days        int not null default 30,
  length_rounding_m       numeric(4,2) not null default 0.10,
  quote_terms             text,
  xero_invoices_as_draft  boolean not null default true,
  updated_at              timestamptz not null default now()
);
insert into settings default values;

create table lead_sources (
  id      serial primary key,
  name    text not null unique,
  active  boolean not null default true
);
insert into lead_sources (name) values
  ('Website'), ('Phone'), ('Email'), ('Referral'), ('Repeat customer'), ('Builder / trade'),
  ('Builderscrack'), ('Google'), ('Facebook / Instagram'), ('Signage / vehicle'), ('Other');

-- Balustrade systems priced per metre (mostly Unex products).
create table systems (
  id                               uuid primary key default gen_random_uuid(),
  name                             text not null,           -- e.g. 'Frameless glass – spigot'
  category                         text not null,           -- glass / aluminium / stainless / juliet / pool fence
  supplier                         text not null default 'Unex',
  supplier_ref                     text,                    -- Unex product / system code
  retail_rate_per_m                numeric(10,2) not null,
  trade_rate_per_m                 numeric(10,2) not null,
  standard_height_mm               int not null default 1000,
  height_surcharge_per_m_per_100mm numeric(10,2) not null default 0,
  max_panel_width_mm               int,                     -- materials estimate
  max_post_spacing_mm              int,                     -- materials estimate; null for postless systems
  cost_rate_per_m                  numeric(10,2),           -- v2: margin reporting
  xero_item_code                   text,
  xero_account_code                text,
  active                           boolean not null default true,
  sort_order                       int not null default 0,
  created_at                       timestamptz not null default now(),
  updated_at                       timestamptz not null default now()
);

-- Priced extras: gates, corners, wall fixings, core drilling, scaffold, removal, travel, etc.
create table extras (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  unit              extra_unit not null default 'each',
  retail_price      numeric(10,2) not null,
  trade_price       numeric(10,2) not null,
  auto_rule         extra_auto_rule not null default 'manual',
  substrate         substrate_type,                       -- auto-apply only on this substrate (null = any)
  system_id         uuid references systems (id),         -- auto-apply only for this system (null = any)
  xero_item_code    text,
  xero_account_code text,
  active            boolean not null default true,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Jobs, surveys and measurements
-- ---------------------------------------------------------------------------

create sequence job_number_seq;

create table jobs (
  id                      uuid primary key default gen_random_uuid(),
  job_number              text not null unique
                            default ('BC-' || lpad(nextval('job_number_seq')::text, 5, '0')),
  title                   text not null,
  stage                   job_stage not null default 'enquiry',
  contact_id              uuid not null references contacts (id),
  billing_company_id      uuid references companies (id),   -- null = bill the contact
  site_address_id         uuid references addresses (id),
  site_access_notes       text,                              -- parking, gate codes, dogs, floor level
  lead_source_id          int references lead_sources (id),
  lead_source_detail      text,                              -- referrer, UTM campaign, etc.
  enquiry_message         text,
  assigned_to             uuid references staff (id),
  is_commercial           boolean not null default false,
  is_external             boolean not null default true,
  estimated_value         numeric(12,2),
  follow_up_on            date,
  lost_reason             text,
  deposit_override_by     uuid references staff (id),        -- admin allowed ordering before deposit paid
  deposit_override_reason text,
  completed_at            timestamptz,
  signed_off_by_name      text,
  warranty_starts_on      date,
  deleted_at              timestamptz,                       -- soft delete
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check (stage <> 'lost' or lost_reason is not null),
  check ((deposit_override_by is null) = (deposit_override_reason is null))
);
create index jobs_stage_idx   on jobs (stage) where deleted_at is null;
create index jobs_contact_idx on jobs (contact_id);
create index jobs_company_idx on jobs (billing_company_id);
create index jobs_follow_idx  on jobs (follow_up_on) where deleted_at is null;

create table surveys (
  id              uuid primary key default gen_random_uuid(),
  job_id          uuid not null references jobs (id) on delete cascade,
  surveyor_id     uuid references staff (id),
  scheduled_start timestamptz,
  scheduled_end   timestamptz,
  completed_at    timestamptz,
  notes           text,
  google_event_id text,
  created_at      timestamptz not null default now()
);
create index surveys_job_idx on surveys (job_id);

-- A measured length of balustrade. Mark the meeting ends of two runs as 'corner';
-- the calculator counts each corner joint once (corner ends ÷ 2).
create table runs (
  id                uuid primary key default gen_random_uuid(),
  job_id            uuid not null references jobs (id) on delete cascade,
  survey_id         uuid references surveys (id) on delete set null,
  label             text not null,                         -- e.g. 'Front deck'
  system_id         uuid references systems (id),
  length_m          numeric(7,2) not null check (length_m > 0),
  height_mm         int not null default 1000 check (height_mm > 0),
  substrate         substrate_type not null,
  start_termination termination_type not null default 'wall',
  end_termination   termination_type not null default 'open',
  notes             text,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index runs_job_idx on runs (job_id);

-- ---------------------------------------------------------------------------
-- Quotes
-- ---------------------------------------------------------------------------

create sequence quote_number_seq;

-- New versions of a quote reuse its quote_number with version + 1 (set by the app).
create table quotes (
  id                      uuid primary key default gen_random_uuid(),
  job_id                  uuid not null references jobs (id) on delete cascade,
  quote_number            text not null
                            default ('Q-' || lpad(nextval('quote_number_seq')::text, 5, '0')),
  version                 int not null default 1,
  status                  quote_status not null default 'draft',
  pricing_tier            pricing_tier not null,
  subtotal                numeric(12,2) not null default 0,
  gst                     numeric(12,2) not null default 0,
  total_incl_gst          numeric(12,2) not null default 0,
  deposit_percent         numeric(5,2) not null default 0,
  deposit_amount_incl_gst numeric(12,2) not null default 0,
  valid_until             date,
  terms_snapshot          text,
  pdf_path                text,
  sent_at                 timestamptz,
  viewed_at               timestamptz,
  accepted_at             timestamptz,
  accepted_by_name        text,
  accepted_ip             inet,
  declined_reason         text,
  created_by              uuid references staff (id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (quote_number, version)
);
create index quotes_job_idx on quotes (job_id);

create table quote_lines (
  id                uuid primary key default gen_random_uuid(),
  quote_id          uuid not null references quotes (id) on delete cascade,
  run_id            uuid references runs (id) on delete set null,
  system_id         uuid references systems (id),
  extra_id          uuid references extras (id),
  description       text not null,
  quantity          numeric(10,2) not null,
  unit              text not null,                -- 'm', 'each', 'job'
  unit_price        numeric(10,2) not null,       -- negative for discounts
  line_total        numeric(12,2) not null,
  is_auto           boolean not null default true, -- false = added or overridden by staff
  xero_item_code    text,
  xero_account_code text,
  sort_order        int not null default 0
);
create index quote_lines_quote_idx on quote_lines (quote_id);

-- ---------------------------------------------------------------------------
-- Invoices and payments (Xero is the ledger; these mirror what was pushed)
-- ---------------------------------------------------------------------------

create table invoices (
  id                  uuid primary key default gen_random_uuid(),
  job_id              uuid not null references jobs (id) on delete restrict,
  quote_id            uuid references quotes (id),
  type                invoice_type not null,
  status              invoice_status not null default 'draft',
  xero_invoice_id     uuid unique,
  xero_invoice_number text,
  lines               jsonb not null default '[]',   -- snapshot of the lines sent to Xero
  subtotal            numeric(12,2) not null,
  gst                 numeric(12,2) not null,
  total_incl_gst      numeric(12,2) not null,
  amount_paid         numeric(12,2) not null default 0,
  issued_on           date not null default current_date,
  due_on              date not null,
  paid_at             timestamptz,
  sync_error          text,
  last_synced_at      timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index invoices_job_idx on invoices (job_id);

create table payments (
  id                         uuid primary key default gen_random_uuid(),
  invoice_id                 uuid not null references invoices (id) on delete restrict,
  method                     payment_method not null,
  amount                     numeric(12,2) not null check (amount > 0),
  received_at                timestamptz not null default now(),
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id   text unique,
  xero_payment_id            uuid unique,
  created_at                 timestamptz not null default now()
);
create index payments_invoice_idx on payments (invoice_id);

-- Extra work or changes after acceptance; billed on the final invoice.
create table variations (
  id                      uuid primary key default gen_random_uuid(),
  job_id                  uuid not null references jobs (id) on delete cascade,
  description             text not null,
  amount                  numeric(12,2) not null,   -- excl. GST, may be negative
  approved_by_customer_at timestamptz,
  invoice_id              uuid references invoices (id),
  created_by              uuid references staff (id),
  created_at              timestamptz not null default now()
);
create index variations_job_idx on variations (job_id);

-- ---------------------------------------------------------------------------
-- Supplier orders (Unex) and installs
-- ---------------------------------------------------------------------------

create table supplier_orders (
  id                   uuid primary key default gen_random_uuid(),
  job_id               uuid not null references jobs (id) on delete cascade,
  supplier             text not null default 'Unex',
  supplier_order_ref   text,
  status               supplier_order_status not null default 'draft',
  ordered_on           date,
  expected_delivery_on date,
  delivered_on         date,
  deliver_to           text not null default 'site' check (deliver_to in ('site', 'yard')),
  materials            jsonb not null default '[]',   -- estimated materials list, editable
  notes                text,
  created_by           uuid references staff (id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index supplier_orders_job_idx on supplier_orders (job_id);

create table installs (
  id                   uuid primary key default gen_random_uuid(),
  job_id               uuid not null references jobs (id) on delete cascade,
  starts_on            date not null,
  duration_days        numeric(3,1) not null default 1 check (duration_days > 0),  -- half-days allowed
  status               install_status not null default 'scheduled',
  notes                text,
  google_event_id      text,
  customer_notified_at timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index installs_job_idx   on installs (job_id);
create index installs_start_idx on installs (starts_on);

create table install_crew (
  install_id uuid not null references installs (id) on delete cascade,
  staff_id   uuid not null references staff (id),
  primary key (install_id, staff_id)
);

create table snags (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null references jobs (id) on delete cascade,
  description text not null,
  raised_by   uuid references staff (id),
  raised_at   timestamptz not null default now(),
  resolved_by uuid references staff (id),
  resolved_at timestamptz
);
create index snags_job_idx on snags (job_id);

-- ---------------------------------------------------------------------------
-- Documents and compliance
-- ---------------------------------------------------------------------------

create table documents (
  id                  uuid primary key default gen_random_uuid(),
  job_id              uuid references jobs (id) on delete cascade,
  contact_id          uuid references contacts (id) on delete cascade,
  kind                document_kind not null,
  storage_path        text not null,          -- private storage bucket; served via signed URLs
  file_name           text not null,
  mime_type           text,
  caption             text,
  visible_to_customer boolean not null default false,
  ok_for_website      boolean not null default false,
  uploaded_by_staff   uuid references staff (id),
  uploaded_by_contact uuid references contacts (id),
  created_at          timestamptz not null default now(),
  check (job_id is not null or contact_id is not null)
);
create index documents_job_idx on documents (job_id);

-- Building consent, PS1 (Unex engineer), PS3 (us), PS4, LBP record of work.
create table compliance_items (
  id                uuid primary key default gen_random_uuid(),
  job_id            uuid not null references jobs (id) on delete cascade,
  kind              compliance_kind not null,
  status            compliance_status not null default 'required',
  reference         text,                  -- e.g. consent number
  responsible_party text,                  -- e.g. 'Unex engineer', 'Builder', 'Balustrading Concepts'
  requested_on      date,
  received_on       date,
  document_id       uuid references documents (id) on delete set null,
  notes             text,
  unique (job_id, kind)
);

-- ---------------------------------------------------------------------------
-- Activity, tasks, audit, integrations
-- ---------------------------------------------------------------------------

create table activities (
  id         uuid primary key default gen_random_uuid(),
  job_id     uuid references jobs (id) on delete cascade,
  contact_id uuid references contacts (id) on delete cascade,
  company_id uuid references companies (id) on delete cascade,
  type       activity_type not null,
  body       text,
  metadata   jsonb not null default '{}',
  created_by uuid references staff (id),      -- null = system
  created_at timestamptz not null default now(),
  check (job_id is not null or contact_id is not null or company_id is not null)
);
create index activities_job_idx     on activities (job_id, created_at desc);
create index activities_contact_idx on activities (contact_id, created_at desc);

create table tasks (
  id           uuid primary key default gen_random_uuid(),
  job_id       uuid references jobs (id) on delete cascade,
  contact_id   uuid references contacts (id) on delete cascade,
  assigned_to  uuid references staff (id),
  title        text not null,
  due_on       date,
  completed_at timestamptz,
  created_by   uuid references staff (id),
  created_at   timestamptz not null default now()
);
create index tasks_open_idx on tasks (assigned_to, due_on) where completed_at is null;

create table audit_log (
  id         bigint generated always as identity primary key,
  table_name text not null,
  row_id     uuid,
  action     text not null check (action in ('insert', 'update', 'delete')),
  changed_by uuid,
  old_data   jsonb,
  new_data   jsonb,
  changed_at timestamptz not null default now()
);

-- OAuth tokens for Xero etc. RLS enabled with no policies: server (service role) only.
create table integration_tokens (
  provider      text primary key,          -- 'xero'
  tenant_id     text,
  access_token  text not null,
  refresh_token text not null,
  expires_at    timestamptz not null,
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create function set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'companies', 'contacts', 'settings', 'systems', 'extras', 'jobs', 'runs', 'quotes',
    'invoices', 'supplier_orders', 'installs', 'integration_tokens'
  ] loop
    execute format(
      'create trigger %I before update on %I for each row execute function set_updated_at()',
      t || '_set_updated_at', t);
  end loop;
end $$;

-- TODO (first migration): generic audit trigger writing to audit_log for
-- jobs, quotes, quote_lines, invoices, payments, variations.

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
-- Every table has RLS on. With no policy, a table is unreachable from the browser and only the
-- server (service role) can use it — the safe default. Policies are added table by table in the
-- first migration; the helpers below are what they'll be written with.

create function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and active);
$$;

create function has_role(r staff_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and active and r = any (roles));
$$;

-- The contact record for the signed-in portal customer (null for staff).
create function portal_contact_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from contacts where portal_user_id = auth.uid();
$$;

-- The company of the signed-in portal customer, if any (trade contacts see their company's jobs).
create function portal_company_id() returns uuid
language sql stable security definer set search_path = public as $$
  select company_id from contacts where portal_user_id = auth.uid();
$$;

-- Whether the signed-in staff member is crewed on any install for the job.
create function is_on_crew(p_job_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from installs i join install_crew c on c.install_id = i.id
    where i.job_id = p_job_id and c.staff_id = auth.uid()
  );
$$;

do $$
declare t text;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- Example policies for jobs (pattern for the rest):
create policy jobs_office on jobs for all to authenticated
  using (has_role('admin') or has_role('office') or has_role('surveyor'))
  with check (has_role('admin') or has_role('office') or has_role('surveyor'));

create policy jobs_installer_read on jobs for select to authenticated
  using (has_role('installer') and is_on_crew(id));

create policy jobs_customer_read on jobs for select to authenticated
  using (
    deleted_at is null and (
      contact_id = portal_contact_id()
      or billing_company_id = portal_company_id()
    )
  );
