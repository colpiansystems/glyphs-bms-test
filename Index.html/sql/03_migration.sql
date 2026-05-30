-- ══════════════════════════════════════════════════════════════════════════
-- GLYPHS BMS v6 — MIGRATION SCRIPT
-- Migrates data exported from localStorage (v5) to PostgreSQL (v6)
-- ══════════════════════════════════════════════════════════════════════════
-- USAGE:
--   1. Export JSON from v5: Settings → Export JSON → save as v5_backup.json
--   2. Load the JSON and call migrate_v5_data() via a one-time script
--   3. Verify record counts before going live
-- ══════════════════════════════════════════════════════════════════════════

-- Temporary staging table for v5 JSON import
CREATE TABLE IF NOT EXISTS public._migration_v5 (
    id          SERIAL PRIMARY KEY,
    loaded_at   TIMESTAMPTZ DEFAULT now(),
    raw_data    JSONB NOT NULL
);

-- ── MIGRATION FUNCTION ───────────────────────────────────────────────────
-- Call this after inserting one row into _migration_v5 with the full v5 JSON blob
CREATE OR REPLACE FUNCTION public.migrate_v5_data(p_migration_id INTEGER DEFAULT 1)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_data        JSONB;
    v_result      JSONB := '{}';
    v_cust        JSONB;
    v_job         JSONB;
    v_quote       JSONB;
    v_sale        JSONB;
    v_exp         JSONB;
    v_pc          JSONB;
    v_audit       JSONB;
    v_branch_id   UUID;
    v_cust_count  INTEGER := 0;
    v_job_count   INTEGER := 0;
    v_quote_count INTEGER := 0;
    v_sale_count  INTEGER := 0;
    v_exp_count   INTEGER := 0;
    v_pc_count    INTEGER := 0;
    v_audit_count INTEGER := 0;
BEGIN
    SELECT raw_data INTO v_data FROM public._migration_v5 WHERE id = p_migration_id;
    IF v_data IS NULL THEN
        RAISE EXCEPTION 'Migration data not found for id %', p_migration_id;
    END IF;

    -- ── CUSTOMERS ────────────────────────────────────────────────────────
    FOR v_cust IN SELECT * FROM jsonb_array_elements(v_data->'customers') LOOP
        SELECT id INTO v_branch_id FROM public.branches
        WHERE name = v_cust->>'branch' LIMIT 1;

        INSERT INTO public.customers (
            id, name, phone, whatsapp, email, branch_id, branch_name, notes
        ) VALUES (
            COALESCE((v_cust->>'id')::UUID, uuid_generate_v4()),
            v_cust->>'name',
            v_cust->>'phone',
            v_cust->>'whatsapp',
            v_cust->>'email',
            v_branch_id,
            v_cust->>'branch',
            v_cust->>'notes'
        ) ON CONFLICT (id) DO NOTHING;
        v_cust_count := v_cust_count + 1;
    END LOOP;

    -- ── QUOTATIONS ───────────────────────────────────────────────────────
    FOR v_quote IN SELECT * FROM jsonb_array_elements(v_data->'quotations') LOOP
        SELECT id INTO v_branch_id FROM public.branches
        WHERE name = v_quote->>'branch' LIMIT 1;

        INSERT INTO public.quotations (
            id, quote_no, customer_name, customer_phone,
            branch_id, branch_name, quote_date, valid_until,
            status, notes, subtotal, vat_amount, total, amount_paid, prepared_by
        ) VALUES (
            COALESCE((v_quote->>'id')::UUID, uuid_generate_v4()),
            COALESCE(v_quote->>'quoteNo', 'QT-MIGR-' || nextval('public.ref_sequences_id_seq'::regclass)),
            v_quote->>'client',
            v_quote->>'phone',
            v_branch_id,
            COALESCE(v_quote->>'branch', 'North Kaneshie'),
            COALESCE((v_quote->>'date')::DATE, CURRENT_DATE),
            CASE WHEN v_quote->>'validUntil' <> '' THEN (v_quote->>'validUntil')::DATE END,
            COALESCE(v_quote->>'status', 'Draft'),
            v_quote->>'notes',
            COALESCE((v_quote->>'subtotal')::NUMERIC, 0),
            COALESCE((v_quote->>'vat')::NUMERIC, 0),
            COALESCE((v_quote->>'total')::NUMERIC, 0),
            COALESCE((v_quote->>'amountPaid')::NUMERIC, 0),
            v_quote->>'preparedBy'
        ) ON CONFLICT (id) DO NOTHING;
        v_quote_count := v_quote_count + 1;
    END LOOP;

    -- ── JOBS ─────────────────────────────────────────────────────────────
    FOR v_job IN SELECT * FROM jsonb_array_elements(v_data->'jobs') LOOP
        SELECT id INTO v_branch_id FROM public.branches
        WHERE name = v_job->>'branch' LIMIT 1;

        INSERT INTO public.jobs (
            id, job_no, order_no, customer_name, customer_phone,
            branch_id, branch_name, job_date, due_date,
            service_type, description, qty, unit_price,
            media, finishing, status,
            payment_status, amount_paid,
            assigned_to, prepared_by, notes,
            is_order_header, line_index
        ) VALUES (
            COALESCE((v_job->>'id')::UUID, uuid_generate_v4()),
            COALESCE(v_job->>'jobNo', 'JO-MIGR-' || floor(random()*99999)::TEXT),
            COALESCE(v_job->>'orderNo', v_job->>'jobNo', 'ORD-MIGR'),
            COALESCE(v_job->>'client', ''),
            v_job->>'phone',
            v_branch_id,
            COALESCE(v_job->>'branch', 'North Kaneshie'),
            COALESCE((v_job->>'date')::DATE, CURRENT_DATE),
            CASE WHEN v_job->>'dueDate' <> '' AND v_job->>'dueDate' IS NOT NULL
                 THEN (v_job->>'dueDate')::DATE END,
            v_job->>'type',
            COALESCE(v_job->>'desc', ''),
            COALESCE((v_job->>'qty')::NUMERIC, 1),
            COALESCE((v_job->>'unitPrice')::NUMERIC, 0),
            v_job->>'media',
            v_job->>'finishing',
            COALESCE(v_job->>'status', 'Pending'),
            -- Map old paid boolean to payment_status
            CASE
                WHEN (v_job->>'paid')::BOOLEAN = true THEN 'Paid'
                WHEN COALESCE((v_job->>'amountPaid')::NUMERIC, 0) > 0 THEN 'Partial'
                ELSE 'Unpaid'
            END,
            COALESCE((v_job->>'amountPaid')::NUMERIC, 0),
            v_job->>'assignedTo',
            v_job->>'preparedBy',
            v_job->>'notes',
            COALESCE((v_job->>'isOrderHeader')::BOOLEAN, false),
            COALESCE((v_job->>'lineIndex')::INTEGER, 0)
        ) ON CONFLICT (id) DO NOTHING;
        v_job_count := v_job_count + 1;
    END LOOP;

    -- ── SALES ────────────────────────────────────────────────────────────
    FOR v_sale IN SELECT * FROM jsonb_array_elements(v_data->'sales') LOOP
        SELECT id INTO v_branch_id FROM public.branches
        WHERE name = v_sale->>'branch' LIMIT 1;

        INSERT INTO public.sales (
            id, ref, sale_date, customer_name, service_type,
            branch_id, branch_name,
            subtotal, vat_amount, total, payment_method, description
        ) VALUES (
            COALESCE((v_sale->>'id')::UUID, uuid_generate_v4()),
            COALESCE(v_sale->>'ref', 'SL-MIGR-' || floor(random()*99999)::TEXT),
            COALESCE((v_sale->>'date')::DATE, CURRENT_DATE),
            v_sale->>'customer',
            v_sale->>'serviceType',
            v_branch_id,
            COALESCE(v_sale->>'branch', 'North Kaneshie'),
            COALESCE((v_sale->>'subtotal')::NUMERIC, 0),
            COALESCE((v_sale->>'vat')::NUMERIC, 0),
            COALESCE((v_sale->>'credit')::NUMERIC, 0),
            v_sale->>'payment',
            v_sale->>'desc'
        ) ON CONFLICT (id) DO NOTHING;
        v_sale_count := v_sale_count + 1;
    END LOOP;

    -- ── EXPENSES ─────────────────────────────────────────────────────────
    FOR v_exp IN SELECT * FROM jsonb_array_elements(v_data->'expenses') LOOP
        SELECT id INTO v_branch_id FROM public.branches
        WHERE name = v_exp->>'branch' LIMIT 1;

        INSERT INTO public.expenses (
            id, ref, expense_date, category, vendor,
            branch_id, branch_name,
            subtotal, vat_input, total, payment_method, description, vat_claim
        ) VALUES (
            COALESCE((v_exp->>'id')::UUID, uuid_generate_v4()),
            COALESCE(v_exp->>'ref', 'EXP-MIGR-' || floor(random()*99999)::TEXT),
            COALESCE((v_exp->>'date')::DATE, CURRENT_DATE),
            COALESCE(v_exp->>'category', 'General'),
            v_exp->>'vendor',
            v_branch_id,
            COALESCE(v_exp->>'branch', 'North Kaneshie'),
            COALESCE((v_exp->>'subtotal')::NUMERIC, 0),
            COALESCE((v_exp->>'vatInput')::NUMERIC, 0),
            COALESCE((v_exp->>'debit')::NUMERIC, 0),
            v_exp->>'payment',
            v_exp->>'desc',
            COALESCE((v_exp->>'vatClaim')::BOOLEAN, false)
        ) ON CONFLICT (id) DO NOTHING;
        v_exp_count := v_exp_count + 1;
    END LOOP;

    -- ── PETTY CASH ────────────────────────────────────────────────────────
    FOR v_pc IN SELECT * FROM jsonb_array_elements(v_data->'pettyCash') LOOP
        SELECT id INTO v_branch_id FROM public.branches
        WHERE name = v_pc->>'branch' LIMIT 1;

        INSERT INTO public.petty_cash (
            id, request_date, requested_by, branch_id, branch_name,
            category, purpose, amount, status, approved_by
        ) VALUES (
            COALESCE((v_pc->>'id')::UUID, uuid_generate_v4()),
            COALESCE((v_pc->>'date')::DATE, CURRENT_DATE),
            COALESCE(v_pc->>'requestedBy', 'Unknown'),
            v_branch_id,
            COALESCE(v_pc->>'branch', 'North Kaneshie'),
            COALESCE(v_pc->>'category', 'General'),
            COALESCE(v_pc->>'purpose', ''),
            COALESCE((v_pc->>'amount')::NUMERIC, 0),
            COALESCE(v_pc->>'status', 'Pending'),
            v_pc->>'approvedBy'
        ) ON CONFLICT (id) DO NOTHING;
        v_pc_count := v_pc_count + 1;
    END LOOP;

    -- ── AUDIT LOGS ───────────────────────────────────────────────────────
    FOR v_audit IN SELECT * FROM jsonb_array_elements(v_data->'auditLog') LOOP
        INSERT INTO public.audit_logs (
            event_ts, category, user_name, user_role, branch_name, ref, action, detail
        ) VALUES (
            COALESCE((v_audit->>'ts')::TIMESTAMPTZ, now()),
            COALESCE(v_audit->>'type', 'system'),
            v_audit->>'user',
            v_audit->>'role',
            v_audit->>'branch',
            v_audit->>'ref',
            COALESCE(v_audit->>'msg', ''),
            v_audit->>'detail'
        );
        v_audit_count := v_audit_count + 1;
    END LOOP;

    -- Return summary
    v_result := jsonb_build_object(
        'status', 'success',
        'customers',   v_cust_count,
        'quotations',  v_quote_count,
        'jobs',        v_job_count,
        'sales',       v_sale_count,
        'expenses',    v_exp_count,
        'petty_cash',  v_pc_count,
        'audit_logs',  v_audit_count
    );

    -- Log the migration itself
    INSERT INTO public.audit_logs (category, action, detail)
    VALUES ('system', 'DATA MIGRATION v5→v6',
            v_result::TEXT);

    RETURN v_result;
END;
$$;

-- Grant execute to authenticated users (sysadmin only via RLS)
GRANT EXECUTE ON FUNCTION public.migrate_v5_data(INTEGER) TO authenticated;

