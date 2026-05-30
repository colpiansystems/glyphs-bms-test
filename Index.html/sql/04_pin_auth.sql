-- ══════════════════════════════════════════════════════════════════════════
-- GLYPHS BMS v6 — PIN AUTHENTICATION
-- Run AFTER 01_schema.sql and 02_rls_policies.sql
-- ══════════════════════════════════════════════════════════════════════════
-- DESIGN:
--   Staff log in with Name + PIN (familiar UX, works on shared tablets).
--   PINs are stored ONLY as bcrypt hashes in the staff_pins table.
--   Verification happens inside PostgreSQL via pgcrypto crypt().
--   The verify-pin Edge Function calls verify_pin() using the service_role
--   key (server-side only), then creates a real Supabase JWT using the
--   generateLink + verifyOtp flow (the only supported server-side session
--   creation method in supabase-js v2.x — createSession does not exist).
--   The browser only enters the app when it holds a valid JWT.
-- ══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── STAFF PINS TABLE ─────────────────────────────────────────────────────
-- Isolated from user_profiles so PIN hashes are never exposed in profile queries.
-- No SELECT RLS policy exists — the table is completely opaque to all roles
-- except the SECURITY DEFINER functions below (called by the Edge Function).
CREATE TABLE IF NOT EXISTS public.staff_pins (
    id              UUID PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    pin_hash        TEXT NOT NULL,          -- bcrypt hash, work factor 10
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until    TIMESTAMPTZ,            -- NULL = not locked
    last_changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by_id   UUID REFERENCES public.user_profiles(id)
);

ALTER TABLE public.staff_pins ENABLE ROW LEVEL SECURITY;
-- No permissive policies defined on this table.
-- All access is via the SECURITY DEFINER functions below.

-- ── FUNCTION: set a PIN (hashes it, stores only the hash) ────────────────
-- Called via the admin_set_pin() wrapper below (admin-only gate).
-- The plain PIN is never stored anywhere — only the bcrypt hash.
CREATE OR REPLACE FUNCTION public.set_staff_pin(
    p_user_id   UUID,
    p_plain_pin TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_plain_pin !~ '^\d{4,6}$' THEN
        RAISE EXCEPTION 'PIN must be 4–6 digits only';
    END IF;

    INSERT INTO public.staff_pins (id, pin_hash, last_changed_at)
    VALUES (
        p_user_id,
        crypt(p_plain_pin, gen_salt('bf', 10)),
        now()
    )
    ON CONFLICT (id) DO UPDATE
        SET pin_hash        = crypt(p_plain_pin, gen_salt('bf', 10)),
            failed_attempts = 0,
            locked_until    = NULL,
            last_changed_at = now();

    INSERT INTO public.audit_logs (category, user_id, action, detail)
    VALUES ('settings', p_user_id, 'PIN set/changed',
            format('bcrypt PIN updated for user_id %s', p_user_id));
END;
$$;

-- ── FUNCTION: verify PIN and return profile ──────────────────────────────
-- Called ONLY by the verify-pin Edge Function (service_role key).
-- Implements: name lookup, lockout check, bcrypt compare, failure counter.
-- Returns JSONB so the Edge Function gets everything it needs in one call.
CREATE OR REPLACE FUNCTION public.verify_pin(
    p_staff_name TEXT,
    p_plain_pin  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile     public.user_profiles%ROWTYPE;
    v_pin_row     public.staff_pins%ROWTYPE;
    v_correct     BOOLEAN;
BEGIN
    -- Lookup by name (case-insensitive)
    SELECT * INTO v_profile
    FROM   public.user_profiles
    WHERE  lower(full_name) = lower(trim(p_staff_name))
      AND  is_active = true
    LIMIT  1;

    IF NOT FOUND THEN
        -- Constant-time path — do not reveal whether name exists
        PERFORM pg_sleep(0.3);
        RETURN jsonb_build_object('ok', false, 'reason', 'invalid_credentials');
    END IF;

    SELECT * INTO v_pin_row
    FROM   public.staff_pins
    WHERE  id = v_profile.id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'no_pin_set');
    END IF;

    -- Lockout check
    IF v_pin_row.locked_until IS NOT NULL AND v_pin_row.locked_until > now() THEN
        RETURN jsonb_build_object(
            'ok',          false,
            'reason',      'locked',
            'locked_until', v_pin_row.locked_until
        );
    END IF;

    -- bcrypt comparison (constant-time)
    v_correct := (v_pin_row.pin_hash = crypt(p_plain_pin, v_pin_row.pin_hash));

    IF NOT v_correct THEN
        UPDATE public.staff_pins
        SET    failed_attempts = failed_attempts + 1,
               locked_until    = CASE
                                    WHEN failed_attempts + 1 >= 5
                                    THEN now() + interval '15 minutes'
                                    ELSE NULL
                                  END
        WHERE  id = v_profile.id;

        INSERT INTO public.audit_logs
            (category, user_id, user_name, user_role, branch_name, action, detail)
        VALUES (
            'auth', v_profile.id, v_profile.full_name, v_profile.role,
            v_profile.branch_name, 'Failed PIN attempt',
            format('Attempt %s — %s',
                v_pin_row.failed_attempts + 1,
                CASE WHEN v_pin_row.failed_attempts + 1 >= 5
                     THEN 'LOCKED 15min' ELSE 'not locked' END)
        );

        RETURN jsonb_build_object('ok', false, 'reason', 'invalid_credentials');
    END IF;

    -- Correct — reset failure counter
    UPDATE public.staff_pins
    SET    failed_attempts = 0,
           locked_until    = NULL
    WHERE  id = v_profile.id;

    RETURN jsonb_build_object(
        'ok',          true,
        'user_id',     v_profile.id,
        'full_name',   v_profile.full_name,
        'role',        v_profile.role,
        'branch_name', v_profile.branch_name,
        'phone',       v_profile.phone
    );
END;
$$;

-- Revoke direct browser access — only service_role (Edge Function) can call verify_pin
REVOKE ALL ON FUNCTION public.verify_pin(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_pin(TEXT, TEXT) FROM authenticated;
REVOKE ALL ON FUNCTION public.verify_pin(TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION public.verify_pin(TEXT, TEXT) TO service_role;

-- ── ADMIN WRAPPER: set/reset PIN for a target user ────────────────────────
-- Called from the app's Reset PIN button via Supabase RPC.
-- Checks the caller's role before delegating to set_staff_pin().
CREATE OR REPLACE FUNCTION public.admin_set_pin(
    p_target_user_id UUID,
    p_plain_pin       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_role TEXT;
    v_target_name TEXT;
BEGIN
    SELECT role INTO v_caller_role
    FROM   public.user_profiles
    WHERE  id = auth.uid();

    IF v_caller_role NOT IN ('super_admin', 'sysadmin', 'ceo') THEN
        RAISE EXCEPTION 'Access denied: only Super Admin, SysAdmin, or CEO can set PINs';
    END IF;

    SELECT full_name INTO v_target_name
    FROM   public.user_profiles WHERE id = p_target_user_id;

    PERFORM public.set_staff_pin(p_target_user_id, p_plain_pin);

    INSERT INTO public.audit_logs (category, user_id, user_name, action, detail)
    VALUES ('settings', auth.uid(),
            (SELECT full_name FROM public.user_profiles WHERE id = auth.uid()),
            'PIN reset by admin',
            format('PIN reset for: %s (id: %s)', v_target_name, p_target_user_id));

    RETURN jsonb_build_object('ok', true, 'msg', 'PIN updated successfully');
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_pin(UUID, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.set_staff_pin(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_staff_pin(UUID, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.set_staff_pin(UUID, TEXT) FROM authenticated;
-- (admin_set_pin is the correct entry point; set_staff_pin is internal only)

-- ══════════════════════════════════════════════════════════════════════════
-- STAFF AUTH ACCOUNT SETUP
-- ══════════════════════════════════════════════════════════════════════════
-- The Edge Function uses generateLink + verifyOtp to create a JWT.
-- This requires each staff member to have an auth.users row.
-- The email is an internal placeholder — staff never see or use it.
-- Authentication is exclusively by Name + PIN via the Edge Function.
--
-- STEP 1 — Run this in Supabase SQL Editor to create auth accounts for all
--           staff who have user_profiles but no auth.users row yet.
--           (Safe to re-run — ON CONFLICT DO NOTHING)
--
-- INSERT INTO auth.users (
--     id,
--     instance_id,
--     email,
--     encrypted_password,
--     email_confirmed_at,
--     raw_user_meta_data,
--     created_at,
--     updated_at,
--     aud,
--     role
-- )
-- SELECT
--     up.id,
--     '00000000-0000-0000-0000-000000000000',
--     up.id::TEXT || '@glyphs.internal',
--     crypt(gen_random_uuid()::TEXT, gen_salt('bf', 10)),  -- random, unusable password
--     now(),
--     jsonb_build_object('full_name', up.full_name, 'role', up.role),
--     now(),
--     now(),
--     'authenticated',
--     'authenticated'
-- FROM public.user_profiles up
-- LEFT JOIN auth.users au ON au.id = up.id
-- WHERE au.id IS NULL
--   AND up.is_active = true;
--
-- STEP 2 — Set each staff member's PIN:
--
-- SELECT set_staff_pin(id, 'XXXX')
-- FROM user_profiles WHERE full_name = 'Lucy';
--
-- SELECT set_staff_pin(id, 'XXXX')
-- FROM user_profiles WHERE full_name = 'Stephen';
-- ... (repeat for each staff member, replacing XXXX with their actual PIN)
--
-- STEP 3 — Verify setup (run this to confirm everything is in order):
--
-- SELECT
--     up.full_name,
--     up.role,
--     up.branch_name,
--     CASE WHEN sp.id IS NOT NULL THEN '✓ PIN set'   ELSE '✗ No PIN'   END AS pin_status,
--     CASE WHEN au.id IS NOT NULL THEN '✓ Auth acct' ELSE '✗ No auth'  END AS auth_status
-- FROM public.user_profiles up
-- LEFT JOIN public.staff_pins sp ON sp.id = up.id
-- LEFT JOIN auth.users au        ON au.id = up.id
-- WHERE up.is_active = true
-- ORDER BY up.full_name;
-- ══════════════════════════════════════════════════════════════════════════

