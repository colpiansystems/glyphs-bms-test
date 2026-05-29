-- Glyphs BMS stabilization schema + policies
-- Run in Supabase SQL Editor before/after uploading the audited index.html.

-- =========================
-- 1) Schema compatibility columns
-- =========================

alter table customers add column if not exists branch text;
alter table customers add column if not exists branch_name text;
alter table customers add column if not exists created_by_id text;
update customers set branch = coalesce(branch, branch_name), branch_name = coalesce(branch_name, branch) where true;

alter table quotations add column if not exists description text;
alter table quotations add column if not exists service_type text;
alter table quotations add column if not exists qty numeric(10,2) default 0;
alter table quotations add column if not exists unit_price numeric(15,2) default 0;
alter table quotations add column if not exists branch text;
alter table quotations add column if not exists branch_name text;
alter table quotations add column if not exists no_vat boolean default false;
alter table quotations add column if not exists vat_enabled boolean default true;
alter table quotations add column if not exists amount_paid numeric(15,2) default 0;
alter table quotations add column if not exists payment_status text default 'Unpaid';
update quotations
set branch = coalesce(branch, branch_name),
    branch_name = coalesce(branch_name, branch),
    no_vat = coalesce(no_vat,false),
    vat_enabled = case when coalesce(no_vat,false)=true then false else coalesce(vat_enabled,true) end,
    amount_paid = coalesce(amount_paid,0),
    payment_status = coalesce(payment_status,'Unpaid')
where true;

alter table quotation_items add column if not exists notes text;
alter table quotation_items add column if not exists no_vat boolean default false;
alter table quotation_items add column if not exists media text;
alter table quotation_items add column if not exists finishing text;
alter table quotation_items add column if not exists sort_order int4 default 0;

alter table jobs add column if not exists branch text;
alter table jobs add column if not exists branch_name text;
alter table jobs add column if not exists assigned_to text;
alter table jobs add column if not exists assigned_to_id uuid;
alter table jobs add column if not exists prepared_by text;
alter table jobs add column if not exists prepared_by_id uuid;
alter table jobs add column if not exists no_vat boolean default false;
alter table jobs add column if not exists vat_enabled boolean default true;
alter table jobs add column if not exists vat_amount numeric(15,2) default 0;
alter table jobs add column if not exists nhil_amount numeric(15,2) default 0;
alter table jobs add column if not exists getfund_amount numeric(15,2) default 0;
alter table jobs add column if not exists amount_paid numeric(15,2) default 0;
alter table jobs add column if not exists payment_status text default 'Unpaid';
alter table jobs add column if not exists total numeric(15,2) default 0;
alter table jobs add column if not exists is_order_header boolean default true;
alter table jobs add column if not exists line_index int4 default 0;
update jobs
set branch = coalesce(branch, branch_name),
    branch_name = coalesce(branch_name, branch),
    no_vat = coalesce(no_vat,false),
    vat_enabled = case when coalesce(no_vat,false)=true then false else coalesce(vat_enabled,true) end,
    amount_paid = coalesce(amount_paid,0),
    payment_status = coalesce(payment_status,'Unpaid'),
    total = case when coalesce(total,0)=0 then coalesce(subtotal,0) else total end
where true;

alter table user_profiles add column if not exists branch_name text;
update user_profiles up
set branch_name = coalesce(up.branch_name, b.name)
from branches b
where up.branch_id = b.id;

alter table payments add column if not exists payment_ref text;
alter table payments add column if not exists quotation_id uuid;
alter table payments add column if not exists job_id uuid;
alter table payments add column if not exists order_no text;
alter table payments add column if not exists customer_name text;
alter table payments add column if not exists branch_name text;
alter table payments add column if not exists payment_date date default current_date;
alter table payments add column if not exists amount numeric(15,2) default 0;
alter table payments add column if not exists method text;
alter table payments add column if not exists notes text;
alter table payments add column if not exists received_by text;
alter table payments add column if not exists received_by_id uuid;

alter table sales add column if not exists payment_id uuid;
alter table sales add column if not exists job_id uuid;
alter table sales add column if not exists recorded_by text;
alter table sales add column if not exists recorded_by_id uuid;

alter table job_status_history add column if not exists changed_by text;
alter table job_status_history add column if not exists changed_by_id uuid;
alter table job_status_history add column if not exists notes text;

-- =========================
-- 2) RLS policies for current PIN-auth/browser REST model
-- =========================

alter table customers enable row level security;
alter table quotations enable row level security;
alter table quotation_items enable row level security;
alter table jobs enable row level security;
alter table job_status_history enable row level security;
alter table payments enable row level security;
alter table sales enable row level security;
alter table user_profiles enable row level security;
alter table branches enable row level security;
alter table audit_logs enable row level security;

drop policy if exists "Allow anon select customers" on customers;
drop policy if exists "Allow anon insert customers" on customers;
drop policy if exists "Allow anon update customers" on customers;
create policy "Allow anon select customers" on customers for select to anon using (true);
create policy "Allow anon insert customers" on customers for insert to anon with check (true);
create policy "Allow anon update customers" on customers for update to anon using (true) with check (true);

drop policy if exists "Allow anon select quotations" on quotations;
drop policy if exists "Allow anon insert quotations" on quotations;
drop policy if exists "Allow anon update quotations" on quotations;
create policy "Allow anon select quotations" on quotations for select to anon using (true);
create policy "Allow anon insert quotations" on quotations for insert to anon with check (true);
create policy "Allow anon update quotations" on quotations for update to anon using (true) with check (true);

drop policy if exists "Allow anon select quotation_items" on quotation_items;
drop policy if exists "Allow anon insert quotation_items" on quotation_items;
drop policy if exists "Allow anon update quotation_items" on quotation_items;
create policy "Allow anon select quotation_items" on quotation_items for select to anon using (true);
create policy "Allow anon insert quotation_items" on quotation_items for insert to anon with check (true);
create policy "Allow anon update quotation_items" on quotation_items for update to anon using (true) with check (true);

drop policy if exists "Allow anon select jobs" on jobs;
drop policy if exists "Allow anon insert jobs" on jobs;
drop policy if exists "Allow anon update jobs" on jobs;
create policy "Allow anon select jobs" on jobs for select to anon using (true);
create policy "Allow anon insert jobs" on jobs for insert to anon with check (true);
create policy "Allow anon update jobs" on jobs for update to anon using (true) with check (true);

drop policy if exists "Allow anon select job status history" on job_status_history;
drop policy if exists "Allow anon insert job status history" on job_status_history;
create policy "Allow anon select job status history" on job_status_history for select to anon using (true);
create policy "Allow anon insert job status history" on job_status_history for insert to anon with check (true);

drop policy if exists "Allow anon select payments" on payments;
drop policy if exists "Allow anon insert payments" on payments;
drop policy if exists "Allow anon update payments" on payments;
create policy "Allow anon select payments" on payments for select to anon using (true);
create policy "Allow anon insert payments" on payments for insert to anon with check (true);
create policy "Allow anon update payments" on payments for update to anon using (true) with check (true);

drop policy if exists "Allow anon select sales" on sales;
drop policy if exists "Allow anon insert sales" on sales;
drop policy if exists "Allow anon update sales" on sales;
create policy "Allow anon select sales" on sales for select to anon using (true);
create policy "Allow anon insert sales" on sales for insert to anon with check (true);
create policy "Allow anon update sales" on sales for update to anon using (true) with check (true);

drop policy if exists "Allow anon select user profiles" on user_profiles;
create policy "Allow anon select user profiles" on user_profiles for select to anon using (true);

drop policy if exists "Allow anon select branches" on branches;
create policy "Allow anon select branches" on branches for select to anon using (true);

drop policy if exists "Allow anon select audit logs" on audit_logs;
drop policy if exists "Allow anon insert audit logs" on audit_logs;
create policy "Allow anon select audit logs" on audit_logs for select to anon using (true);
create policy "Allow anon insert audit logs" on audit_logs for insert to anon with check (true);
