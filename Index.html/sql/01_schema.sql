-- ══════════════════════════════════════════════════════════════════════════
-- GLYPHS COMPANY LIMITED — BMS v6 DATABASE SCHEMA
-- Colpian Systems Ltd · Accra, Ghana
-- ══════════════════════════════════════════════════════════════════════════
-- Run this file in the Supabase SQL Editor (project → SQL Editor → New query)
-- Execute all sections in order. Safe to re-run (uses IF NOT EXISTS / OR REPLACE).
-- ══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── 1. BRANCHES ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branches (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL UNIQUE,
    address     TEXT,
    phone       TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO public.branches (name) VALUES ('North Kaneshie'),('Awoshie')
ON CONFLICT (name) DO NOTHING;

-- ── 2. USER PROFILES ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name     TEXT NOT NULL,
    role          TEXT NOT NULL CHECK (role IN (
                      'super_admin','sysadmin','ceo','manager',
                      'finance_officer','cso','production')),
    branch_id     UUID REFERENCES public.branches(id),
    branch_name   TEXT,
    phone         TEXT,
    is_active     BOOLEAN NOT NULL DEFAULT true,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 3. SETTINGS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settings (
    key         TEXT PRIMARY KEY,
    value       TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  UUID REFERENCES public.user_profiles(id)
);
INSERT INTO public.settings (key, value) VALUES
    ('vat_rate','15'),('nhil_rate','2.5'),('getfund_rate','2.5'),
    ('tin_number',''),('vat_number',''),
    ('company_name','Glyphs Company Limited'),('currency','GHS'),
    ('invoice_prefix','INV'),('quote_prefix','QT'),('job_prefix','JO')
ON CONFLICT (key) DO NOTHING;

-- ── 4. SERVICE TYPES ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.service_types (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL UNIQUE,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    sort_order  INTEGER DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO public.service_types (name, sort_order) VALUES
    ('Digital Printing',1),('Offset Printing',2),('Large Format',3),
    ('Branding',4),('Signage',5),('Embroidery',6),
    ('Promotional Items',7),('Design Services',8)
ON CONFLICT (name) DO NOTHING;

-- ── 5. CUSTOMERS ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.customers (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL,
    phone       TEXT,
    whatsapp    TEXT,
    email       TEXT,
    address     TEXT,
    branch_id   UUID REFERENCES public.branches(id),
    branch_name TEXT,
    notes       TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_by  UUID REFERENCES public.user_profiles(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customers_branch ON public.customers(branch_id);
CREATE INDEX IF NOT EXISTS idx_customers_name   ON public.customers(name);

-- ── 6. QUOTATIONS ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.quotations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quote_no        TEXT NOT NULL UNIQUE,
    customer_id     UUID REFERENCES public.customers(id),
    customer_name   TEXT NOT NULL,
    customer_phone  TEXT,
    branch_id       UUID REFERENCES public.branches(id),
    branch_name     TEXT NOT NULL,
    quote_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_until     DATE,
    status          TEXT NOT NULL DEFAULT 'Draft'
                        CHECK (status IN ('Draft','Sent','Approved','Rejected','Converted','Expired')),
    notes           TEXT,
    subtotal        NUMERIC(15,2) NOT NULL DEFAULT 0,
    vat_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
    nhil_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
    getfund_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
    total           NUMERIC(15,2) NOT NULL DEFAULT 0,
    amount_paid     NUMERIC(15,2) NOT NULL DEFAULT 0,
    prepared_by_id  UUID REFERENCES public.user_profiles(id),
    prepared_by     TEXT,
    converted_to_job_id UUID,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_quotations_branch   ON public.quotations(branch_id);
CREATE INDEX IF NOT EXISTS idx_quotations_customer ON public.quotations(customer_id);
CREATE INDEX IF NOT EXISTS idx_quotations_status   ON public.quotations(status);

-- ── 7. QUOTATION LINE ITEMS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.quotation_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quotation_id    UUID NOT NULL REFERENCES public.quotations(id) ON DELETE CASCADE,
    line_number     INTEGER NOT NULL DEFAULT 1,
    description     TEXT NOT NULL,
    service_type    TEXT,
    qty             NUMERIC(10,2) NOT NULL DEFAULT 1,
    unit_price      NUMERIC(15,2) NOT NULL DEFAULT 0,
    subtotal        NUMERIC(15,2) GENERATED ALWAYS AS (qty * unit_price) STORED,
    media           TEXT,
    finishing       TEXT,
    sort_order      INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_quote_items_quotation ON public.quotation_items(quotation_id);

-- ── 8. JOBS ─────────────────────────────────────────────────────────────
-- ACCOUNTING NOTE: jobs create RECEIVABLES, NOT cash sales.
-- Revenue is only recognised when payment is received (payments table).
CREATE TABLE IF NOT EXISTS public.jobs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_no          TEXT NOT NULL UNIQUE,
    order_no        TEXT NOT NULL,
    quotation_id    UUID REFERENCES public.quotations(id),
    customer_id     UUID REFERENCES public.customers(id),
    customer_name   TEXT NOT NULL,
    customer_phone  TEXT,
    branch_id       UUID REFERENCES public.branches(id),
    branch_name     TEXT NOT NULL,
    job_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date        DATE,
    service_type    TEXT,
    description     TEXT NOT NULL,
    qty             NUMERIC(10,2) NOT NULL DEFAULT 1,
    unit_price      NUMERIC(15,2) NOT NULL DEFAULT 0,
    subtotal        NUMERIC(15,2) GENERATED ALWAYS AS (qty * unit_price) STORED,
    media           TEXT,
    finishing       TEXT,
    status          TEXT NOT NULL DEFAULT 'Pending'
                        CHECK (status IN (
                            'Pending','In Production','Quality Check','Returned to CSO',
                            'Ready for Pickup','Completed','Cancelled')),
    payment_status  TEXT NOT NULL DEFAULT 'Unpaid'
                        CHECK (payment_status IN ('Unpaid','Partial','Paid','Void')),
    amount_paid     NUMERIC(15,2) NOT NULL DEFAULT 0,
    assigned_to_id  UUID REFERENCES public.user_profiles(id),
    assigned_to     TEXT,
    prepared_by_id  UUID REFERENCES public.user_profiles(id),
    prepared_by     TEXT,
    notes           TEXT,
    is_order_header BOOLEAN NOT NULL DEFAULT false,
    line_index      INTEGER DEFAULT 0,
    created_by_id   UUID REFERENCES public.user_profiles(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_jobs_branch         ON public.jobs(branch_id);
CREATE INDEX IF NOT EXISTS idx_jobs_order_no       ON public.jobs(order_no);
CREATE INDEX IF NOT EXISTS idx_jobs_customer       ON public.jobs(customer_id);
CREATE INDEX IF NOT EXISTS idx_jobs_status         ON public.jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_payment_status ON public.jobs(payment_status);

-- ── 9. PAYMENTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_ref     TEXT NOT NULL UNIQUE,
    job_id          UUID REFERENCES public.jobs(id),
    order_no        TEXT,
    quotation_id    UUID REFERENCES public.quotations(id),
    customer_name   TEXT NOT NULL,
    branch_id       UUID REFERENCES public.branches(id),
    branch_name     TEXT,
    payment_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    amount          NUMERIC(15,2) NOT NULL,
    method          TEXT NOT NULL DEFAULT 'Cash'
                        CHECK (method IN ('Cash','MoMo','Bank Transfer','Cheque','Card','Other')),
    notes           TEXT,
    received_by_id  UUID REFERENCES public.user_profiles(id),
    received_by     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payments_job   ON public.payments(job_id);
CREATE INDEX IF NOT EXISTS idx_payments_order ON public.payments(order_no);
CREATE INDEX IF NOT EXISTS idx_payments_date  ON public.payments(payment_date);

-- ── 10. SALES (Revenue ledger — created per payment received) ───────────
CREATE TABLE IF NOT EXISTS public.sales (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ref             TEXT NOT NULL UNIQUE,
    sale_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    customer_name   TEXT,
    service_type    TEXT,
    branch_id       UUID REFERENCES public.branches(id),
    branch_name     TEXT,
    payment_id      UUID REFERENCES public.payments(id),
    job_id          UUID REFERENCES public.jobs(id),
    subtotal        NUMERIC(15,2) NOT NULL DEFAULT 0,
    vat_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
    nhil_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
    getfund_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
    total           NUMERIC(15,2) NOT NULL DEFAULT 0,
    payment_method  TEXT,
    description     TEXT,
    recorded_by_id  UUID REFERENCES public.user_profiles(id),
    recorded_by     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sales_branch ON public.sales(branch_id);
CREATE INDEX IF NOT EXISTS idx_sales_date   ON public.sales(sale_date);

-- ── 11. EXPENSES ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.expenses (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ref             TEXT NOT NULL UNIQUE,
    expense_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    category        TEXT NOT NULL,
    vendor          TEXT,
    branch_id       UUID REFERENCES public.branches(id),
    branch_name     TEXT,
    subtotal        NUMERIC(15,2) NOT NULL DEFAULT 0,
    vat_input       NUMERIC(15,2) NOT NULL DEFAULT 0,
    total           NUMERIC(15,2) NOT NULL DEFAULT 0,
    payment_method  TEXT,
    description     TEXT,
    vat_claim       BOOLEAN NOT NULL DEFAULT false,
    receipt_ref     TEXT,
    recorded_by_id  UUID REFERENCES public.user_profiles(id),
    recorded_by     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_expenses_branch ON public.expenses(branch_id);
CREATE INDEX IF NOT EXISTS idx_expenses_date   ON public.expenses(expense_date);

-- ── 12. PETTY CASH ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.petty_cash (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    requested_by_id UUID REFERENCES public.user_profiles(id),
    requested_by    TEXT NOT NULL,
    branch_id       UUID REFERENCES public.branches(id),
    branch_name     TEXT,
    category        TEXT NOT NULL,
    purpose         TEXT NOT NULL,
    amount          NUMERIC(15,2) NOT NULL,
    status          TEXT NOT NULL DEFAULT 'Pending'
                        CHECK (status IN ('Pending','Approved','Rejected','Paid')),
    approved_by_id  UUID REFERENCES public.user_profiles(id),
    approved_by     TEXT,
    approved_at     TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_petty_cash_branch ON public.petty_cash(branch_id);
CREATE INDEX IF NOT EXISTS idx_petty_cash_status ON public.petty_cash(status);

-- ── 13. AUDIT LOGS (APPEND-ONLY) ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id          BIGSERIAL PRIMARY KEY,
    event_ts    TIMESTAMPTZ NOT NULL DEFAULT now(),
    category    TEXT NOT NULL,
    user_id     UUID REFERENCES public.user_profiles(id),
    user_name   TEXT,
    user_role   TEXT,
    branch_name TEXT,
    ref         TEXT,
    action      TEXT NOT NULL,
    detail      TEXT,
    ip_address  TEXT,
    user_agent  TEXT
);
CREATE INDEX IF NOT EXISTS idx_audit_ts       ON public.audit_logs(event_ts DESC);
CREATE INDEX IF NOT EXISTS idx_audit_category ON public.audit_logs(category);
CREATE INDEX IF NOT EXISTS idx_audit_user     ON public.audit_logs(user_id);

-- ── 14. JOB STATUS HISTORY ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.job_status_history (
    id            BIGSERIAL PRIMARY KEY,
    job_id        UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    from_status   TEXT,
    to_status     TEXT NOT NULL,
    changed_by_id UUID REFERENCES public.user_profiles(id),
    changed_by    TEXT,
    notes         TEXT,
    changed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_job_status_history_job ON public.job_status_history(job_id);

-- ── 15. REF SEQUENCES ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ref_sequences (
    prefix      TEXT PRIMARY KEY,
    last_value  BIGINT NOT NULL DEFAULT 0,
    year        INTEGER NOT NULL DEFAULT EXTRACT(YEAR FROM now())::INTEGER
);
INSERT INTO public.ref_sequences (prefix, last_value) VALUES
    ('QT',0),('JO',0),('ORD',0),('PMT',0),('SL',0),('EXP',0),('PC',0)
ON CONFLICT (prefix) DO NOTHING;

-- ── HELPER: next_ref() ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.next_ref(p_prefix TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_year INTEGER := EXTRACT(YEAR FROM now())::INTEGER;
    v_next BIGINT;
BEGIN
    UPDATE public.ref_sequences
    SET    last_value = CASE WHEN year < v_year THEN 1 ELSE last_value + 1 END,
           year = v_year
    WHERE  prefix = p_prefix
    RETURNING last_value INTO v_next;
    IF NOT FOUND THEN
        INSERT INTO public.ref_sequences (prefix, last_value, year)
        VALUES (p_prefix, 1, v_year) RETURNING last_value INTO v_next;
    END IF;
    RETURN p_prefix || '-' || v_year || '-' || LPAD(v_next::TEXT, 4, '0');
END;
$$;

-- ── TRIGGER: updated_at ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DO $$ DECLARE tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'branches','user_profiles','customers','quotations',
        'jobs','expenses','petty_cash','settings'
    ] LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_%I_updated_at ON public.%I;
             CREATE TRIGGER trg_%I_updated_at
             BEFORE UPDATE ON public.%I
             FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
            tbl, tbl, tbl, tbl);
    END LOOP;
END; $$;

-- ── TRIGGER: auto-create profile after auth signup ───────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO public.user_profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1)),
        COALESCE(NEW.raw_user_meta_data->>'role', 'cso')
    ) ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

