-- Run this script in Supabase Dashboard > SQL Editor.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null default 'student' check (role in ('student', 'admin')),
  name text not null default '',
  id_no text not null default '',
  program text not null default '',
  college text not null default 'College of Computer Studies',
  contact text not null default '',
  last_login timestamptz,
  prev_login timestamptz
);

create table if not exists public.rooms (
  id text primary key,
  number text not null unique,
  type text not null,
  building text not null,
  floor text not null,
  wing text not null,
  capacity integer not null check (capacity > 0),
  equipment text[] not null default '{}',
  status text not null default 'available'
    check (status in ('available', 'occupied', 'reserved', 'maintenance'))
);

create table if not exists public.bookings (
  id text primary key,
  room_no text not null,
  start_date date not null,
  end_date date not null,
  start_time text not null check (start_time ~ '^(0[7-9]|1[0-7]):[0-5][0-9]$' and start_time < '18:00'),
  end_time text not null check (end_time ~ '^(0[7-9]|1[0-7]):[0-5][0-9]$|^18:00$'),
  booked_by text not null,
  owner_email text not null,
  owner_id uuid not null references public.profiles(id),
  purpose text not null,
  group_size integer not null check (group_size > 0),
  status text not null check (status in ('reserved', 'confirmed', 'cancelled')),
  created_at timestamptz not null default now(),
  cancel_reason text,
  cancelled_at timestamptz,
  late_cancel boolean not null default false,
  check (end_date >= start_date),
  check (end_time > start_time)
);

create table if not exists public.booking_policy (
  id smallint primary key default 1 check (id = 1),
  default_status text not null default 'reserved'
    check (default_status in ('reserved', 'confirmed')),
  max_hours integer not null default 3 check (max_hours > 0),
  advance_days integer not null default 14 check (advance_days >= 0),
  max_days integer not null default 3 check (max_days > 0)
);

insert into public.booking_policy (id) values (1) on conflict (id) do nothing;

insert into public.rooms (id, number, type, building, floor, wing, capacity, equipment, status) values
  ('r301', '301', 'Computer Lab', 'Main Building', '3rd Floor', 'Right Side', 40, array['Air Conditioning','Computers / PCs','Projector'], 'available'),
  ('r302', '302', 'Lecture Room', 'Main Building', '3rd Floor', 'Left Side', 50, array['Projector','Whiteboard'], 'occupied'),
  ('r303', '303', 'Seminar Room', 'Main Building', '3rd Floor', 'Left Side', 80, array['Air Conditioning','AV System','Projector'], 'available'),
  ('r101', '101', 'Conference Room', 'Main Building', '1st Floor', 'Right Side', 20, array['Air Conditioning','Smart TV'], 'available'),
  ('r102', '102', 'Study Room', 'Main Building', '1st Floor', 'Right Side', 12, array['Air Conditioning','Whiteboard'], 'available'),
  ('r201', '201', 'Science Lab', 'Annex Building', '2nd Floor', 'Right Side', 30, array['Lab Benches'], 'maintenance'),
  ('r202', '202', 'Lecture Room', 'Annex Building', '2nd Floor', 'Left Side', 45, array['Projector','Whiteboard'], 'available'),
  ('r401', '401', 'Computer Lab', 'Annex Building', '4th Floor', 'Right Side', 35, array['Air Conditioning','Computers / PCs','Projector'], 'available'),
  ('r402', '402', 'Computer Lab', 'Annex Building', '4th Floor', 'Left Side', 35, array['Air Conditioning','Computers / PCs','Projector'], 'reserved'),
  ('r403', '403', 'Lecture Room', 'Annex Building', '4th Floor', 'Left Side', 60, array['Air Conditioning','Projector','Whiteboard'], 'available')
on conflict (id) do nothing;

create or replace function public.is_roomoptima_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

create or replace function public.create_roomoptima_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, email, name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

drop trigger if exists on_roomoptima_auth_user_created on auth.users;
create trigger on_roomoptima_auth_user_created
after insert on auth.users
for each row execute procedure public.create_roomoptima_profile();

create or replace function public.prevent_roomoptima_role_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (select auth.uid()) is not null
     and new.role is distinct from old.role
     and not exists (
       select 1 from public.profiles
       where id = (select auth.uid()) and role = 'admin'
     ) then
    raise exception 'Only an administrator can change a profile role';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_roomoptima_profile_role on public.profiles;
create trigger protect_roomoptima_profile_role
before update on public.profiles
for each row execute procedure public.prevent_roomoptima_role_change();

create or replace function public.protect_roomoptima_booking()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  room_capacity integer;
  booking_rules public.booking_policy%rowtype;
begin
  if (select auth.uid()) is not null
     and not public.is_roomoptima_admin()
  then
    if tg_op = 'INSERT' then
      if new.status <> (select default_status from public.booking_policy where id = 1) then
        raise exception 'New bookings must use the configured default status';
      end if;
      if new.start_date < current_date then
        raise exception 'New bookings cannot start in the past';
      end if;
    elsif new.owner_id is distinct from old.owner_id
       or (new.status is distinct from old.status and new.status <> 'cancelled') then
      raise exception 'Only an administrator can transfer or confirm a booking';
    end if;
  end if;

  select capacity into room_capacity
  from public.rooms where number = new.room_no;
  if room_capacity is null then
    raise exception 'The selected room does not exist';
  end if;
  if new.group_size > room_capacity then
    raise exception 'Group size exceeds room capacity';
  end if;

  select * into strict booking_rules from public.booking_policy where id = 1;
  if new.end_date - new.start_date + 1 > booking_rules.max_days then
    raise exception 'Booking duration exceeds the configured limit';
  end if;
  if new.start_date > current_date + booking_rules.advance_days then
    raise exception 'Booking is outside the configured advance window';
  end if;
  if (new.end_time::time - new.start_time::time) > make_interval(hours => booking_rules.max_hours) then
    raise exception 'Booking duration exceeds the configured hourly limit';
  end if;

  if new.status <> 'cancelled' then
    if tg_op = 'UPDATE' and old.room_no <> new.room_no then
      if old.room_no < new.room_no then
        perform pg_advisory_xact_lock(hashtext('roomoptima:' || old.room_no));
        perform pg_advisory_xact_lock(hashtext('roomoptima:' || new.room_no));
      else
        perform pg_advisory_xact_lock(hashtext('roomoptima:' || new.room_no));
        perform pg_advisory_xact_lock(hashtext('roomoptima:' || old.room_no));
      end if;
    else
      perform pg_advisory_xact_lock(hashtext('roomoptima:' || new.room_no));
    end if;

    if exists (
      select 1 from public.bookings b
      where b.id <> new.id
        and b.room_no = new.room_no
        and b.status <> 'cancelled'
        and b.start_date <= new.end_date
        and new.start_date <= b.end_date
        and b.start_time < new.end_time
        and b.end_time > new.start_time
    ) then
      raise exception 'The selected room is already booked for that time';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_roomoptima_booking_fields on public.bookings;
create trigger protect_roomoptima_booking_fields
before insert or update on public.bookings
for each row execute procedure public.protect_roomoptima_booking();

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_policy enable row level security;

drop policy if exists "RoomOptima profiles readable by owner or admin" on public.profiles;
create policy "RoomOptima profiles readable by owner or admin" on public.profiles
for select to authenticated
using (id = (select auth.uid()) or public.is_roomoptima_admin());
drop policy if exists "RoomOptima profiles updatable by owner or admin" on public.profiles;
create policy "RoomOptima profiles updatable by owner or admin" on public.profiles
for update to authenticated
using (id = (select auth.uid()) or public.is_roomoptima_admin())
with check (id = (select auth.uid()) or public.is_roomoptima_admin());

drop policy if exists "RoomOptima rooms are public" on public.rooms;
create policy "RoomOptima rooms are public" on public.rooms
for select to anon, authenticated using (true);
drop policy if exists "RoomOptima rooms managed by admins" on public.rooms;
create policy "RoomOptima rooms managed by admins" on public.rooms
for all to authenticated
using (public.is_roomoptima_admin())
with check (public.is_roomoptima_admin());

drop policy if exists "RoomOptima bookings visible to signed-in users" on public.bookings;
drop policy if exists "RoomOptima bookings visible to owner or admin" on public.bookings;
create policy "RoomOptima bookings visible to owner or admin" on public.bookings
for select to authenticated
using (owner_id = (select auth.uid()) or public.is_roomoptima_admin());
drop policy if exists "RoomOptima users create their own bookings" on public.bookings;
create policy "RoomOptima users create their own bookings" on public.bookings
for insert to authenticated
with check (owner_id = (select auth.uid()) or public.is_roomoptima_admin());
drop policy if exists "RoomOptima users update their own bookings" on public.bookings;
create policy "RoomOptima users update their own bookings" on public.bookings
for update to authenticated
using (owner_id = (select auth.uid()) or public.is_roomoptima_admin())
with check (owner_id = (select auth.uid()) or public.is_roomoptima_admin());

drop policy if exists "RoomOptima booking policy is public" on public.booking_policy;
create policy "RoomOptima booking policy is public" on public.booking_policy
for select to anon, authenticated using (true);
drop policy if exists "RoomOptima booking policy managed by admins" on public.booking_policy;
create policy "RoomOptima booking policy managed by admins" on public.booking_policy
for all to authenticated
using (public.is_roomoptima_admin())
with check (public.is_roomoptima_admin());

create or replace view public.roomoptima_public_schedule as
select id, room_no, start_date, end_date, start_time, end_time, status
from public.bookings
where status <> 'cancelled';
grant select on public.roomoptima_public_schedule to anon, authenticated;

grant select, insert, update, delete on public.rooms to anon, authenticated;
grant select, insert, update on public.bookings to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update on public.booking_policy to anon, authenticated;

-- After creating the administrator in Supabase Authentication, run for that account:
-- update public.profiles set role = 'admin' where email = 'admin@gordoncollege.edu.ph';
