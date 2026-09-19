-- 집회관리 DB 스키마 (Supabase).
--
-- 적용: Supabase 대시보드 → SQL Editor → 이 파일 내용을 통째로 붙여넣고 [Run].
-- 여러 번 돌려도 된다 — 테이블은 있으면 건너뛰고, 함수·권한·정책은 새로 덮어쓴다.
-- 로컬 검증: supabase/test.sql 맨 위 주석 참고.
--
-- 권한 요약
--   gatherings      누구나 읽기 / 운영자만 쓰기
--   registrations   신청자는 테이블에 직접 못 닿는다 — 아래 submit/lookup/update/cancel 함수로만.
--                   운영자는 전부.
--   room_plans      운영자만. 집회별 방배정(방·참석자·배정) 문서. 저장은 save_room_plan — 버전 검사.
--   운영자 = auth.users 에 있고 public.admins 에도 있는 사람.
--   가입 신청 = auth.users 에만 있는 사람. 누구나 가입(대시보드에서 가입 켜 둠)할 수 있지만
--   기존 운영자가 approve_admin 으로 승인하기 전엔 아무 데이터에도 못 닿는다.
--
-- 함수가 던지는 에러 메시지(앱이 이 문자열로 안내 문구를 고른다)
--   CLOSED  INVALID_PHONE  INVALID_PIN  INVALID_PEOPLE  INVALID_TEXT  INVALID_QUOTED
--   ALREADY_REGISTERED  TOO_MANY_ATTEMPTS  NOT_EDITABLE  FORBIDDEN  NOT_FOUND  CONFLICT

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 테이블
-- ---------------------------------------------------------------------------

create table if not exists public.admins (
  user_id uuid primary key references auth.users on delete cascade
);

create table if not exists public.gatherings (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null default 'gathering'     -- 'gathering' | 'homestay' (lib/gathering.dart)
    check (kind in ('gathering', 'homestay')),
  schedule jsonb not null default '[]',      -- 일정표 [{date, time, title}]
  themes text[] not null default '{}',
  place text,
  address text,
  notice text,
  start_date date not null,
  end_date date not null check (end_date >= start_date),
  poster_url text,
  background_url text,
  fee jsonb not null default '{}',          -- FeeRule (lib/gathering.dart)
  bank jsonb,                                -- {bank, account, holder}
  form_fields text[] not null default '{}',  -- 사용자 정의 항목
  hidden_fields text[] not null default '{}',  -- 신청서에서 뺀 기본 항목: birthYear, gender, cell, zone, minister
  required_fields text[] not null default '{birthYear,gender}',  -- 신청서에서 꼭 채워야 하는 기본 항목
  open boolean not null default false,
  deadline date,                             -- 이 날(한국 시간)까지 신청 받음
  minister_notice_on boolean not null default true,  -- 사역자를 체크한 신청자에게 안내 문구를 보일지
  minister_notice text,                      -- 그 문구. 비우면 앱 기본 문구
  created_at timestamptz not null default now()
);
-- 이미 만든 DB 에 새 칸 추가.
alter table public.gatherings add column if not exists kind text not null default 'gathering';
alter table public.gatherings drop constraint if exists gatherings_kind_check;
alter table public.gatherings add constraint gatherings_kind_check
  check (kind in ('gathering', 'homestay'));
alter table public.gatherings add column if not exists schedule jsonb not null default '[]';
alter table public.gatherings add column if not exists hidden_fields text[] not null default '{}';
alter table public.gatherings add column if not exists required_fields text[] not null default '{birthYear,gender}';
alter table public.gatherings add column if not exists minister_notice_on boolean not null default true;
alter table public.gatherings add column if not exists minister_notice text;

create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  gathering_id uuid not null references public.gatherings on delete cascade,
  phone text not null check (phone ~ '^01[0-9]{8,9}$'),   -- 숫자만
  pin_hash text not null,
  people jsonb not null check (jsonb_typeof(people) = 'array'),  -- [Person], [0] = 신청자
  depositor text,
  memo text,
  quoted int not null check (quoted >= 0),  -- 신청 때 보여준 금액(참고용, 관리자 앱이 다시 계산)
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'cancelled')),
  paid int not null default 0,
  paid_at date,
  admin_memo text,                           -- 신청자에게는 안 보인다
  -- 지정 할인 (운영자만 바꾼다. 신청자 조회에는 보인다)
  discount_pct int not null default 0 check (discount_pct between 0 and 100),
  discount_amount int not null default 0 check (discount_amount >= 0),
  discount_note text,
  created_at timestamptz not null default now(),  -- 사전등록 할인 기준. 앱이 못 바꾼다
  updated_at timestamptz not null default now()
);
-- 이미 만든 DB 에 새 칸 추가.
alter table public.registrations add column if not exists discount_pct int not null default 0
  check (discount_pct between 0 and 100);
alter table public.registrations add column if not exists discount_amount int not null default 0
  check (discount_amount >= 0);
alter table public.registrations add column if not exists discount_note text;

-- 휴대폰 1개 = 진행 중인 신청 1건. 취소한 사람은 다시 신청할 수 있다.
create unique index if not exists registrations_active_phone
  on public.registrations (gathering_id, phone) where status <> 'cancelled';

-- PIN 오답 기록. 30분에 5번 틀리면 그 번호는 잠긴다.
create table if not exists public.lookup_failures (
  phone text not null,
  at timestamptz not null default now()
);
create index if not exists lookup_failures_phone_at on public.lookup_failures (phone, at);

-- 방배정. 집회 하나 = 문서 하나 (lib/models.dart 의 Event JSON). 여러 PC·태블릿이 같은 문서를 연다.
create table if not exists public.room_plans (
  gathering_id uuid primary key references public.gatherings on delete cascade,
  data jsonb not null,
  version int not null default 1,            -- 저장할 때마다 +1. 동시 수정 검사용
  updated_at timestamptz not null default now()
);

create or replace function public._touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists touch on public.registrations;
create trigger touch before update on public.registrations
  for each row execute function public._touch();

-- ---------------------------------------------------------------------------
-- 권한 (RLS)
-- ---------------------------------------------------------------------------

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;

alter table public.admins enable row level security;           -- 정책 없음 = API 로는 아무도 못 봄
alter table public.gatherings enable row level security;
alter table public.registrations enable row level security;
alter table public.lookup_failures enable row level security;  -- 정책 없음
alter table public.room_plans enable row level security;

drop policy if exists "누구나 읽기" on public.gatherings;
create policy "누구나 읽기" on public.gatherings
  for select using (true);

drop policy if exists "운영자 쓰기" on public.gatherings;
create policy "운영자 쓰기" on public.gatherings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "운영자만" on public.registrations;
create policy "운영자만" on public.registrations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "운영자만" on public.room_plans;
create policy "운영자만" on public.room_plans
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 테이블 권한을 명시한다. Supabase 의 "새 테이블 자동 공개" 설정이 켜져 있든 꺼져 있든 같게 동작하도록.
revoke all on public.admins, public.gatherings, public.registrations, public.lookup_failures,
  public.room_plans
  from anon, authenticated;
grant select on public.gatherings to anon, authenticated;
grant insert, update, delete on public.gatherings to authenticated;
grant select, insert, update, delete on public.registrations to authenticated;  -- RLS 가 운영자로 제한
grant select, insert, update on public.room_plans to authenticated;  -- RLS 가 운영자로 제한. 저장은 save_room_plan 으로

-- ---------------------------------------------------------------------------
-- 내부 함수 (API 로 못 부른다)
-- ---------------------------------------------------------------------------

create or replace function public._assert_open(p_gathering uuid) returns void
language plpgsql set search_path = '' as $$
declare
  g public.gatherings;
begin
  select * into g from public.gatherings where id = p_gathering;
  if not found or not g.open
     or (g.deadline is not null and (now() at time zone 'Asia/Seoul')::date > g.deadline) then
    raise exception 'CLOSED';
  end if;
end $$;

-- 신청서 입력 검사. 앱에서도 검사하지만 여기가 최종 관문.
create or replace function public._check_input(
  p_people jsonb, p_depositor text, p_memo text, p_quoted int
) returns void
language plpgsql set search_path = '' as $$
begin
  if p_people is null or jsonb_typeof(p_people) <> 'array' then
    raise exception 'INVALID_PEOPLE';
  end if;
  if jsonb_array_length(p_people) not between 1 and 20 or length(p_people::text) > 20000 then
    raise exception 'INVALID_PEOPLE';
  end if;
  if length(coalesce(p_depositor, '')) > 50 or length(coalesce(p_memo, '')) > 1000 then
    raise exception 'INVALID_TEXT';
  end if;
  if p_quoted is null or p_quoted < 0 then
    raise exception 'INVALID_QUOTED';
  end if;
end $$;

-- 휴대폰+PIN 이 맞으면 그 신청(진행 중인 것 우선), 틀리면 null.
-- 틀렸을 때 에러를 던지지 않고 null 을 돌려주는 이유: 에러를 던지면 오답 기록 insert 까지 롤백돼서
-- 횟수 제한이 무력화된다.
create or replace function public._verify(p_gathering uuid, p_phone text, p_pin text)
returns public.registrations
language plpgsql set search_path = '' as $$
declare
  ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  r public.registrations;
begin
  -- 같은 번호로 동시에 여러 요청을 보내 횟수 검사를 앞질러 가는 걸 막는다
  perform pg_advisory_xact_lock(hashtext('lookup:' || ph));
  delete from public.lookup_failures where at < now() - interval '1 day';

  if (select count(*) from public.lookup_failures
       where phone = ph and at > now() - interval '30 minutes') >= 5 then
    raise exception 'TOO_MANY_ATTEMPTS';
  end if;

  select * into r from public.registrations
   where gathering_id = p_gathering and phone = ph
   order by status = 'cancelled', created_at desc
   limit 1;

  if not found or r.pin_hash is distinct from extensions.crypt(coalesce(p_pin, ''), r.pin_hash) then
    insert into public.lookup_failures (phone) values (ph);
    return null;
  end if;
  return r;
end $$;

-- 홈스테이: 이 신청으로 만든 방(가정)에 배정된 참석자. 없으면 빈 배열.
-- 신청자에게 보일 내용만 고른다 — 운영자 메모(note)·방 id 는 빼고 준다.
-- 일반 집회는 registrationId 를 가진 방이 없어 항상 [] 다.
create or replace function public._assigned(p_gathering uuid, p_registration uuid)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', a->>'name', 'gender', a->>'gender', 'age', a->'age',
           'phone', a->>'phone', 'cell', a->>'cell', 'zone', a->>'zone')), '[]'::jsonb)
    from public.room_plans p,
         lateral jsonb_array_elements(p.data->'rooms') r,
         lateral jsonb_array_elements(p.data->'attendees') a
   where p.gathering_id = p_gathering
     and r->>'registrationId' = p_registration::text
     and a->>'roomId' = r->>'id'
$$;

-- ---------------------------------------------------------------------------
-- 신청 웹이 부르는 함수
-- ---------------------------------------------------------------------------

-- 신청. 성공하면 신청 id.
create or replace function public.submit_registration(
  p_gathering uuid, p_phone text, p_pin text, p_people jsonb,
  p_depositor text, p_memo text, p_quoted int
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  new_id uuid;
begin
  perform public._assert_open(p_gathering);
  if ph !~ '^01[0-9]{8,9}$' then raise exception 'INVALID_PHONE'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN'; end if;
  perform public._check_input(p_people, p_depositor, p_memo, p_quoted);

  insert into public.registrations (gathering_id, phone, pin_hash, people, depositor, memo, quoted)
  values (p_gathering, ph, extensions.crypt(p_pin, extensions.gen_salt('bf', 8)), p_people,
          nullif(trim(p_depositor), ''), nullif(trim(p_memo), ''), p_quoted)
  returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'ALREADY_REGISTERED';
end $$;

-- 조회. 맞으면 신청(jsonb, PIN 해시·운영자 메모 제외), 틀리면 null.
create or replace function public.lookup_registration(p_gathering uuid, p_phone text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.registrations := public._verify(p_gathering, p_phone, p_pin);
begin
  if r.id is null then return null; end if;
  return (to_jsonb(r) - 'pin_hash' - 'admin_memo')
      || jsonb_build_object('assigned', public._assigned(p_gathering, r.id));
end $$;

-- 수정. 입금대기 + 신청 받는 중일 때만. 상태·입금액은 못 건드린다. 틀리면 null.
create or replace function public.update_registration(
  p_gathering uuid, p_phone text, p_pin text, p_people jsonb,
  p_depositor text, p_memo text, p_quoted int
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.registrations := public._verify(p_gathering, p_phone, p_pin);
begin
  if r.id is null then return null; end if;
  if r.status <> 'pending' then raise exception 'NOT_EDITABLE'; end if;
  perform public._assert_open(p_gathering);
  perform public._check_input(p_people, p_depositor, p_memo, p_quoted);

  update public.registrations
     set people = p_people, depositor = nullif(trim(p_depositor), ''),
         memo = nullif(trim(p_memo), ''), quoted = p_quoted
   where id = r.id
  returning * into r;
  return to_jsonb(r) - 'pin_hash' - 'admin_memo';
end $$;

-- 취소. 입금대기일 때만 (마감 후에도 가능). 틀리면 null.
create or replace function public.cancel_registration(p_gathering uuid, p_phone text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.registrations := public._verify(p_gathering, p_phone, p_pin);
begin
  if r.id is null then return null; end if;
  if r.status <> 'pending' then raise exception 'NOT_EDITABLE'; end if;

  update public.registrations set status = 'cancelled' where id = r.id
  returning * into r;
  return to_jsonb(r) - 'pin_hash' - 'admin_memo';
end $$;

-- ---------------------------------------------------------------------------
-- 운영자 함수
-- ---------------------------------------------------------------------------

-- PIN 재설정. 그 번호의 오답 기록(잠금)도 같이 푼다.
create or replace function public.reset_pin(p_registration uuid, p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  ph text;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN'; end if;

  update public.registrations
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 8))
   where id = p_registration
  returning phone into ph;
  if not found then raise exception 'NOT_FOUND'; end if;
  delete from public.lookup_failures where phone = ph;
end $$;

-- 운영자가 대신 받는 신청 (전화·현장 접수). 신청 받는 중이 아니어도 된다. 성공하면 신청 id.
-- 입력 검사·PIN 해시는 submit_registration 과 같다 — 신청자가 나중에 휴대폰+PIN 으로 조회한다.
create or replace function public.admin_add_registration(
  p_gathering uuid, p_phone text, p_pin text, p_people jsonb,
  p_depositor text, p_memo text, p_quoted int
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  new_id uuid;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if ph !~ '^01[0-9]{8,9}$' then raise exception 'INVALID_PHONE'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN'; end if;
  perform public._check_input(p_people, p_depositor, p_memo, p_quoted);

  insert into public.registrations (gathering_id, phone, pin_hash, people, depositor, memo, quoted)
  values (p_gathering, ph, extensions.crypt(p_pin, extensions.gen_salt('bf', 8)), p_people,
          nullif(trim(p_depositor), ''), nullif(trim(p_memo), ''), p_quoted)
  returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'ALREADY_REGISTERED';
end $$;

-- 방배정 저장. p_version = 마지막으로 읽은 버전(서버에 아직 없으면 0). 성공하면 새 버전.
-- 그사이 다른 기기가 저장했으면 CONFLICT — 앱은 덮어쓰지 않고 최신 문서를 다시 읽는다.
create or replace function public.save_room_plan(p_gathering uuid, p_data jsonb, p_version int)
returns int
language plpgsql set search_path = '' as $$
declare
  v int;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if p_version = 0 then
    insert into public.room_plans (gathering_id, data) values (p_gathering, p_data)
    on conflict (gathering_id) do nothing
    returning version into v;
  else
    update public.room_plans
       set data = p_data, version = version + 1, updated_at = now()
     where gathering_id = p_gathering and version = p_version
    returning version into v;
  end if;
  if v is null then raise exception 'CONFLICT'; end if;
  return v;
end $$;

-- 승인을 기다리는 가입 신청. 운영자가 아니면 빈 목록.
create or replace function public.admin_requests()
returns table (id uuid, email text, name text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select u.id, u.email::text, u.raw_user_meta_data->>'name', u.created_at
    from auth.users u
   where public.is_admin()
     and not exists (select 1 from public.admins a where a.user_id = u.id)
   order by u.created_at
$$;

-- 가입 승인 = 운영자로 등록.
create or replace function public.approve_admin(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'NOT_FOUND'; end if;
  insert into public.admins (user_id) values (p_user) on conflict do nothing;
end $$;

-- 가입 거절 = 그 계정을 지운다. 이미 운영자인 계정은 못 지운다.
create or replace function public.reject_admin(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  delete from auth.users u
   where u.id = p_user
     and not exists (select 1 from public.admins a where a.user_id = u.id);
  if not found then raise exception 'NOT_FOUND'; end if;
end $$;

-- 함수 실행 권한도 명시한다 (Postgres 기본값은 "누구나 실행 가능").
revoke execute on function
  public._touch(),
  public._assert_open(uuid),
  public._check_input(jsonb, text, text, int),
  public._verify(uuid, text, text),
  public._assigned(uuid, uuid),
  public.reset_pin(uuid, text),
  public.admin_add_registration(uuid, text, text, jsonb, text, text, int),
  public.save_room_plan(uuid, jsonb, int),
  public.admin_requests(),
  public.approve_admin(uuid),
  public.reject_admin(uuid)
  from public, anon, authenticated;

grant execute on function
  public.is_admin(),  -- RLS 정책 안에서 불리므로 모두에게 필요
  public.submit_registration(uuid, text, text, jsonb, text, text, int),
  public.lookup_registration(uuid, text, text),
  public.update_registration(uuid, text, text, jsonb, text, text, int),
  public.cancel_registration(uuid, text, text)
  to anon, authenticated;

grant execute on function
  public.reset_pin(uuid, text),
  public.admin_add_registration(uuid, text, text, jsonb, text, text, int),
  public.save_room_plan(uuid, jsonb, int),
  public.admin_requests(),
  public.approve_admin(uuid),
  public.reject_admin(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 이미지 저장소 — 누구나 보기(공개 버킷) / 운영자만 올리기·지우기
-- 앱이 JPEG 로 줄여서 올리므로(포스터 ≤250KB, 배경 ≤80KB) 1MB·JPEG 로 막아둔다.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gathering-images', 'gathering-images', true, 1048576, array['image/jpeg'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "집회 이미지: 운영자 관리" on storage.objects;
create policy "집회 이미지: 운영자 관리" on storage.objects
  for all to authenticated
  using (bucket_id = 'gathering-images' and public.is_admin())
  with check (bucket_id = 'gathering-images' and public.is_admin());

-- ---------------------------------------------------------------------------
-- 존은 대문자로 통일 ('a존' → 'A존'). 앱은 이제 대문자로만 저장하고, 이건 예전 데이터 정리용.
-- 바꿀 게 없는 행은 건드리지 않아 여러 번 돌려도 된다. 함수는 이 세션에만 있는 임시 함수다.
-- room_plans 는 version 을 올리지 않는다 — 올리면 열어 둔 기기의 다음 저장이 충돌로 버려진다.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.upper_zones(arr jsonb) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(
           case when jsonb_typeof(e->'zone') = 'string'
                then jsonb_set(e, '{zone}', to_jsonb(upper(e->>'zone')))
                else e end
           order by i), '[]'::jsonb)
  from jsonb_array_elements(arr) with ordinality as t(e, i)
$$;

update public.registrations
   set people = pg_temp.upper_zones(people)
 where people <> pg_temp.upper_zones(people);

update public.room_plans
   set data = jsonb_set(data, '{attendees}', pg_temp.upper_zones(data->'attendees'))
 where jsonb_typeof(data->'attendees') = 'array'
   and data->'attendees' <> pg_temp.upper_zones(data->'attendees');
