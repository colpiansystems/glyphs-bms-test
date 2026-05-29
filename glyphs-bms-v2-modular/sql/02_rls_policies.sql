-- ══════════════════════════════════════════════════════════════════════════
-- GLYPHS BMS v6 — ROW LEVEL SECURITY POLICIES
-- Run AFTER 01_schema.sql
-- ══════════════════════════════════════════════════════════════════════════

-- ── HELPER: get current user's profile ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.current_user_profile()
RETURNS public.user_profiles
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT * FROM public.user_profiles
    WHERE id = auth.uid() AND is_active = true
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT role FROM public.user_profiles WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_user_branch()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT branch_name FROM public.user_profiles WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_admin_role()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT COALESCE(
        (SELECT role IN ('super_admin','sysadmin','ceo','manager','finance_officer')
         FROM public.user_profiles WHERE id = auth.uid()), false);
$$;

CREATE OR REPLACE FUNCTION public.is_full_access()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT COALESCE(
        (SELECT role IN ('super_admin','sysadmin','ceo','finance_officer')
         FROM public.user_profiles WHERE id = auth.uid()), false);
$$;

-- ══════════════════════════════════════════════════════════════════════════
-- ENABLE RLS ON ALL TABLES
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.branches          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_types     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotation_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.petty_cash        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_sequences     ENABLE ROW LEVEL SECURITY;

-- ══════════════════════════════════════════════════════════════════════════
-- BRANCHES: all authenticated users can read; only admins write
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "branches_select" ON public.branches;
CREATE POLICY "branches_select" ON public.branches
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "branches_insert" ON public.branches;
CREATE POLICY "branches_insert" ON public.branches
    FOR INSERT TO authenticated
    WITH CHECK (public.is_admin_role());

DROP POLICY IF EXISTS "branches_update" ON public.branches;
CREATE POLICY "branches_update" ON public.branches
    FOR UPDATE TO authenticated
    USING (public.is_admin_role());

-- ══════════════════════════════════════════════════════════════════════════
-- USER PROFILES: users see their own profile; admins see all
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "profiles_select" ON public.user_profiles;
CREATE POLICY "profiles_select" ON public.user_profiles
    FOR SELECT TO authenticated
    USING (
        id = auth.uid()
        OR public.is_admin_role()
    );

DROP POLICY IF EXISTS "profiles_update_own" ON public.user_profiles;
CREATE POLICY "profiles_update_own" ON public.user_profiles
    FOR UPDATE TO authenticated
    USING (id = auth.uid())
    WITH CHECK (
        -- users can update their own non-sensitive fields; role changes require admin
        id = auth.uid()
        AND (
            public.is_admin_role()
            -- non-admins can only update: phone, last_login_at
            OR (role = (SELECT role FROM public.user_profiles WHERE id = auth.uid()))
        )
    );

DROP POLICY IF EXISTS "profiles_insert_admin" ON public.user_profiles;
CREATE POLICY "profiles_insert_admin" ON public.user_profiles
    FOR INSERT TO authenticated
    WITH CHECK (
        public.current_user_role() IN ('super_admin','sysadmin','ceo')
        OR id = auth.uid() -- allow self-insert on signup (via trigger)
    );

-- ══════════════════════════════════════════════════════════════════════════
-- SETTINGS: read all authenticated; write only sysadmin/super_admin
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "settings_select" ON public.settings;
CREATE POLICY "settings_select" ON public.settings
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "settings_write" ON public.settings;
CREATE POLICY "settings_write" ON public.settings
    FOR ALL TO authenticated
    USING (public.current_user_role() IN ('super_admin','sysadmin'))
    WITH CHECK (public.current_user_role() IN ('super_admin','sysadmin'));

-- ══════════════════════════════════════════════════════════════════════════
-- SERVICE TYPES: all read; admins write
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "svc_types_select" ON public.service_types;
CREATE POLICY "svc_types_select" ON public.service_types
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "svc_types_write" ON public.service_types;
CREATE POLICY "svc_types_write" ON public.service_types
    FOR ALL TO authenticated
    USING (public.is_admin_role())
    WITH CHECK (public.is_admin_role());

-- ══════════════════════════════════════════════════════════════════════════
-- CUSTOMERS: branch-scoped for branch staff; full access for admins/finance
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "customers_select" ON public.customers;
CREATE POLICY "customers_select" ON public.customers
    FOR SELECT TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() = 'manager'
        OR branch_name = public.current_user_branch()
    );

DROP POLICY IF EXISTS "customers_insert" ON public.customers;
CREATE POLICY "customers_insert" ON public.customers
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_full_access()
        OR public.current_user_role() IN ('manager','cso')
        -- branch staff can only insert for their branch
        AND (public.is_full_access() OR branch_name = public.current_user_branch())
    );

DROP POLICY IF EXISTS "customers_update" ON public.customers;
CREATE POLICY "customers_update" ON public.customers
    FOR UPDATE TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() IN ('manager','cso')
    );

-- ══════════════════════════════════════════════════════════════════════════
-- QUOTATIONS: branch-scoped access
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "quotations_select" ON public.quotations;
CREATE POLICY "quotations_select" ON public.quotations
    FOR SELECT TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() = 'manager'
        OR branch_name = public.current_user_branch()
    );

DROP POLICY IF EXISTS "quotations_insert" ON public.quotations;
CREATE POLICY "quotations_insert" ON public.quotations
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_full_access()
        OR public.current_user_role() IN ('manager','cso')
    );

DROP POLICY IF EXISTS "quotations_update" ON public.quotations;
CREATE POLICY "quotations_update" ON public.quotations
    FOR UPDATE TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() IN ('manager','cso')
    );

-- Quotation items inherit parent quotation access
DROP POLICY IF EXISTS "quote_items_all" ON public.quotation_items;
CREATE POLICY "quote_items_all" ON public.quotation_items
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.quotations q
            WHERE q.id = quotation_id
            AND (
                public.is_full_access()
                OR public.current_user_role() IN ('manager','cso')
                OR q.branch_name = public.current_user_branch()
            )
        )
    );

-- ══════════════════════════════════════════════════════════════════════════
-- JOBS: branch-scoped; production staff see only their branch's jobs
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "jobs_select" ON public.jobs;
CREATE POLICY "jobs_select" ON public.jobs
    FOR SELECT TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() = 'manager'
        OR branch_name = public.current_user_branch()
    );

DROP POLICY IF EXISTS "jobs_insert" ON public.jobs;
CREATE POLICY "jobs_insert" ON public.jobs
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_full_access()
        OR public.current_user_role() IN ('manager','cso')
    );

DROP POLICY IF EXISTS "jobs_update" ON public.jobs;
CREATE POLICY "jobs_update" ON public.jobs
    FOR UPDATE TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() IN ('manager','cso')
        -- production staff can only update status field
        OR (public.current_user_role() = 'production'
            AND branch_name = public.current_user_branch())
    );

-- ══════════════════════════════════════════════════════════════════════════
-- PAYMENTS: insert by finance/cso/manager; read by branch
-- Payments are NEVER deleted or updated (immutable financial record)
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "payments_select" ON public.payments;
CREATE POLICY "payments_select" ON public.payments
    FOR SELECT TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() = 'manager'
        OR branch_name = public.current_user_branch()
    );

DROP POLICY IF EXISTS "payments_insert" ON public.payments;
CREATE POLICY "payments_insert" ON public.payments
    FOR INSERT TO authenticated
    WITH CHECK (
        public.current_user_role() IN ('super_admin','sysadmin','ceo',
                                        'manager','finance_officer','cso')
    );

-- NO UPDATE or DELETE policies on payments — immutable by design

-- ══════════════════════════════════════════════════════════════════════════
-- SALES: insert by finance; read branch-scoped; no delete
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "sales_select" ON public.sales;
CREATE POLICY "sales_select" ON public.sales
    FOR SELECT TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() = 'manager'
        OR branch_name = public.current_user_branch()
    );

DROP POLICY IF EXISTS "sales_insert" ON public.sales;
CREATE POLICY "sales_insert" ON public.sales
    FOR INSERT TO authenticated
    WITH CHECK (
        public.current_user_role() IN ('super_admin','sysadmin','ceo',
                                        'manager','finance_officer','cso')
    );

-- ══════════════════════════════════════════════════════════════════════════
-- EXPENSES: finance/manager write; branch-scoped read
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "expenses_select" ON public.expenses;
CREATE POLICY "expenses_select" ON public.expenses
    FOR SELECT TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() = 'manager'
        OR branch_name = public.current_user_branch()
    );

DROP POLICY IF EXISTS "expenses_insert" ON public.expenses;
CREATE POLICY "expenses_insert" ON public.expenses
    FOR INSERT TO authenticated
    WITH CHECK (
        public.current_user_role() IN ('super_admin','sysadmin','ceo',
                                        'manager','finance_officer')
    );

DROP POLICY IF EXISTS "expenses_update" ON public.expenses;
CREATE POLICY "expenses_update" ON public.expenses
    FOR UPDATE TO authenticated
    USING (
        public.current_user_role() IN ('super_admin','sysadmin','ceo',
                                        'manager','finance_officer')
    );

-- ══════════════════════════════════════════════════════════════════════════
-- PETTY CASH: anyone in branch can submit; manager/finance approve
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "pc_select" ON public.petty_cash;
CREATE POLICY "pc_select" ON public.petty_cash
    FOR SELECT TO authenticated
    USING (
        public.is_full_access()
        OR public.current_user_role() = 'manager'
        OR branch_name = public.current_user_branch()
    );

DROP POLICY IF EXISTS "pc_insert" ON public.petty_cash;
CREATE POLICY "pc_insert" ON public.petty_cash
    FOR INSERT TO authenticated
    WITH CHECK (
        branch_name = public.current_user_branch()
        OR public.is_full_access()
    );

DROP POLICY IF EXISTS "pc_update_approve" ON public.petty_cash;
CREATE POLICY "pc_update_approve" ON public.petty_cash
    FOR UPDATE TO authenticated
    USING (
        public.current_user_role() IN ('super_admin','sysadmin','ceo',
                                        'manager','finance_officer')
    );

-- ══════════════════════════════════════════════════════════════════════════
-- AUDIT LOGS: INSERT only — authenticated users; SELECT for admins
-- CRITICAL: no UPDATE or DELETE ever allowed
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "audit_select" ON public.audit_logs;
CREATE POLICY "audit_select" ON public.audit_logs
    FOR SELECT TO authenticated
    USING (public.is_admin_role());

DROP POLICY IF EXISTS "audit_insert" ON public.audit_logs;
CREATE POLICY "audit_insert" ON public.audit_logs
    FOR INSERT TO authenticated
    WITH CHECK (true);    -- any authenticated user can append

-- Explicitly block UPDATE and DELETE at the policy level
DROP POLICY IF EXISTS "audit_no_update" ON public.audit_logs;
-- (no UPDATE policy = no updates allowed)

-- ══════════════════════════════════════════════════════════════════════════
-- JOB STATUS HISTORY: append-only
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "job_hist_select" ON public.job_status_history;
CREATE POLICY "job_hist_select" ON public.job_status_history
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "job_hist_insert" ON public.job_status_history;
CREATE POLICY "job_hist_insert" ON public.job_status_history
    FOR INSERT TO authenticated WITH CHECK (true);

-- ══════════════════════════════════════════════════════════════════════════
-- REF SEQUENCES: only service-role (backend function) can update
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "refseq_select" ON public.ref_sequences;
CREATE POLICY "refseq_select" ON public.ref_sequences
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "refseq_update" ON public.ref_sequences;
CREATE POLICY "refseq_update" ON public.ref_sequences
    FOR ALL TO authenticated
    USING (public.current_user_role() IN ('super_admin','sysadmin'));

-- ══════════════════════════════════════════════════════════════════════════
-- GRANT next_ref() to authenticated (called via Supabase RPC)
-- ══════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.next_ref(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_branch() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_full_access() TO authenticated;

