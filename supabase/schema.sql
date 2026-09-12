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
--   운영자 = auth.users 에 있고 public.admins 에도 있는 사람. 공개 회원가입은 대시보드에서 끈다.
--
-- 함수가 던지는 에러 메시지(앱이 이 문자열로 안내 문구를 고른다)
--   CLOSED  INVALID_PHONE  INVALID_PIN  INVALID_PEOPLE  INVALID_TEXT  INVALID_QUOTED
--   ALREADY_REGISTERED  TOO_MANY_ATTEMPTS  NOT_EDITABLE  FORBIDDEN  NOT_FOUND

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
  open boolean not null default false,
  deadline date,                             -- 이 날(한국 시간)까지 신청 받음
  created_at timestamptz not null default now()
);

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
  created_at timestamptz not null default now(),  -- 기간 할인 기준. 앱이 못 바꾼다
  updated_at timestamptz not null default now()
);

-- 휴대폰 1개 = 진행 중인 신청 1건. 취소한 사람은 다시 신청할 수 있다.
create unique index if not exists registrations_active_phone
  on public.registrations (gathering_id, phone) where status <> 'cancelled';

-- PIN 오답 기록. 30분에 5번 틀리면 그 번호는 잠긴다.
create table if not exists public.lookup_failures (
  phone text not null,
  at timestamptz not null default now()
);
create index if not exists lookup_failures_phone_at on public.lookup_failures (phone, at);

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

drop policy if exists "누구나 읽기" on public.gatherings;
create policy "누구나 읽기" on public.gatherings
  for select using (true);

drop policy if exists "운영자 쓰기" on public.gatherings;
create policy "운영자 쓰기" on public.gatherings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "운영자만" on public.registrations;
create policy "운영자만" on public.registrations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 테이블 권한을 명시한다. Supabase 의 "새 테이블 자동 공개" 설정이 켜져 있든 꺼져 있든 같게 동작하도록.
revoke all on public.admins, public.gatherings, public.registrations, public.lookup_failures
  from anon, authenticated;
grant select on public.gatherings to anon, authenticated;
grant insert, update, delete on public.gatherings to authenticated;
grant select, insert, update, delete on public.registrations to authenticated;  -- RLS 가 운영자로 제한

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
  return to_jsonb(r) - 'pin_hash' - 'admin_memo';
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

-- 함수 실행 권한도 명시한다 (Postgres 기본값은 "누구나 실행 가능").
revoke execute on function
  public._touch(),
  public._assert_open(uuid),
  public._check_input(jsonb, text, text, int),
  public._verify(uuid, text, text),
  public.reset_pin(uuid, text)
  from public, anon, authenticated;

grant execute on function
  public.is_admin(),  -- RLS 정책 안에서 불리므로 모두에게 필요
  public.submit_registration(uuid, text, text, jsonb, text, text, int),
  public.lookup_registration(uuid, text, text),
  public.update_registration(uuid, text, text, jsonb, text, text, int),
  public.cancel_registration(uuid, text, text)
  to anon, authenticated;

grant execute on function public.reset_pin(uuid, text) to authenticated;

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
