-- ============================================================
-- SAMS (School Activity Management System) — Supabase schema
-- Run this once in Supabase SQL Editor (Project > SQL Editor)
-- ============================================================

create extension if not exists pgcrypto;

-- One row per auth.users account. role decides student/staff/admin.
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  user_code   text unique not null,          -- e.g. "6511003", "T001", "AD001"
  role        text not null check (role in ('student','staff','admin')),
  name        text not null,
  staff_role  text,                          -- job title, staff/admin only
  faculty     text, major text, year text, section text, curriculum text,
  admit       text, dob text, address text, phone text, email text,
  facebook    text, line text, other text,
  created_at  timestamptz not null default now()
);

create table public.activity_types (
  name text primary key
);

create table public.academic_years (
  year       text primary key,
  is_current boolean not null default false
);

create table public.activities (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  type         text references public.activity_types(name),
  activity_date date,
  time_range   text,
  location     text,
  hours        numeric not null default 0,
  teacher_id   uuid references public.profiles(id),
  year         text references public.academic_years(year),
  description  text,
  created_at   timestamptz not null default now()
);

create table public.registrations (
  id          uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  student_id  uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'registered' check (status in ('registered','attended')),
  hours       numeric not null default 0,
  reg_date    date not null default current_date,
  unique (activity_id, student_id)
);

-- ---------- helper functions ----------
create or replace function public.is_staff_or_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role in ('staff','admin'));
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------- RLS ----------
alter table public.profiles        enable row level security;
alter table public.activity_types  enable row level security;
alter table public.academic_years  enable row level security;
alter table public.activities      enable row level security;
alter table public.registrations   enable row level security;

-- profiles: see your own row, or every row if you're staff/admin.
-- inserting your own row is only allowed for role='student' (self sign-up);
-- staff/admin accounts are created by the /api/create-user server function
-- with the service-role key, which bypasses RLS.
create policy "profiles_select" on public.profiles
  for select using (id = auth.uid() or public.is_staff_or_admin());
create policy "profiles_insert_self_student" on public.profiles
  for insert with check (id = auth.uid() and role = 'student');
create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid())
  with check (id = auth.uid() and role = (select role from public.profiles where id = auth.uid()));

-- activity_types: everyone signed in can read; only admin can write.
create policy "types_select" on public.activity_types
  for select using (auth.role() = 'authenticated');
create policy "types_admin_write" on public.activity_types
  for all using (public.is_admin()) with check (public.is_admin());

-- academic_years: everyone signed in can read; only admin can write.
create policy "years_select" on public.academic_years
  for select using (auth.role() = 'authenticated');
create policy "years_admin_write" on public.academic_years
  for all using (public.is_admin()) with check (public.is_admin());

-- activities: everyone signed in can read; only staff/admin can write.
create policy "activities_select" on public.activities
  for select using (auth.role() = 'authenticated');
create policy "activities_staff_write" on public.activities
  for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

-- registrations: student sees own rows, staff/admin sees all.
create policy "registrations_select" on public.registrations
  for select using (student_id = auth.uid() or public.is_staff_or_admin());
create policy "registrations_student_insert" on public.registrations
  for insert with check (student_id = auth.uid() and status = 'registered');
create policy "registrations_student_delete_own" on public.registrations
  for delete using (student_id = auth.uid() and status = 'registered');
create policy "registrations_staff_manage" on public.registrations
  for all using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

-- ---------- seed data ----------
insert into public.activity_types(name) values ('กีฬา'),('จิตอาสา'),('วิชาการ'),('ชุมนุม');
insert into public.academic_years(year,is_current) values ('2567',false),('2568',false),('2569',true);

-- ---------- first admin account ----------
-- Create the very first admin from the Supabase dashboard:
-- Authentication > Users > Add user, email: ad001@sams.local, password: your choice,
-- turn "Auto Confirm User" on. Then run (replace the uuid with the new user's id,
-- shown in the Users table):
--
-- insert into public.profiles (id, user_code, role, name, staff_role)
-- values ('paste-the-user-uuid-here', 'AD001', 'admin', 'กิตติ จัดการระบบ', 'ผู้ดูแลระบบ');
--
-- After that, this first admin can create every other admin/staff account
-- from the app's "จัดการผู้ใช้งาน" page.
