-- Glyphs BMS petty cash compatibility fix
-- Run this once in Supabase SQL Editor.

-- Ensure columns exist even if your database was created from an older schema.
alter table public.petty_cash add column if not exists request_date date default current_date;
alter table public.petty_cash add column if not exists requested_by_id uuid;
alter table public.petty_cash add column if not exists requested_by text;
alter table public.petty_cash add column if not exists branch_name text;
alter table public.petty_cash add column if not exists category text;
alter table public.petty_cash add column if not exists purpose text;
alter table public.petty_cash add column if not exists amount numeric(15,2) default 0;
alter table public.petty_cash add column if not exists status text default 'Pending';
alter table public.petty_cash add column if not exists approved_by_id uuid;
alter table public.petty_cash add column if not exists approved_by text;
alter table public.petty_cash add column if not exists approved_at timestamptz;

-- Make current_user_branch work whether user_profiles stores branch_name directly
-- or stores only branch_id linked to branches.
create or replace function public.current_user_branch()
returns text
language sql
stable
security definer
as $$
  select coalesce(up.branch_name, b.name)
  from public.user_profiles up
  left join public.branches b on b.id = up.branch_id
  where up.id = auth.uid()
  limit 1;
$$;

grant execute on function public.current_user_branch() to authenticated;

alter table public.petty_cash enable row level security;

drop policy if exists "pc_select" on public.petty_cash;
create policy "pc_select" on public.petty_cash
for select to authenticated
using (
  public.is_full_access()
  or public.current_user_role() = 'manager'
  or branch_name = public.current_user_branch()
  or replace(branch_name, ' Branch', '') = replace(public.current_user_branch(), ' Branch', '')
);

drop policy if exists "pc_insert" on public.petty_cash;
create policy "pc_insert" on public.petty_cash
for insert to authenticated
with check (
  public.is_full_access()
  or branch_name = public.current_user_branch()
  or replace(branch_name, ' Branch', '') = replace(public.current_user_branch(), ' Branch', '')
);

drop policy if exists "pc_update_approve" on public.petty_cash;
create policy "pc_update_approve" on public.petty_cash
for update to authenticated
using (
  public.current_user_role() in ('super_admin','sysadmin','ceo','manager','finance_officer')
)
with check (
  public.current_user_role() in ('super_admin','sysadmin','ceo','manager','finance_officer')
);
