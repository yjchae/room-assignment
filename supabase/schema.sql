-- 집회관리 DB 스키마 (Supabase).
--
-- 적용: Supabase 대시보드 → SQL Editor → 이 파일 내용을 통째로 붙여넣고 [Run].
-- 여러 번 돌려도 된다 — 테이블은 있으면 건너뛰고, 함수·권한·정책은 새로 덮어쓴다.
-- 로컬 검증: supabase/test.sql 맨 위 주석 참고.
--
-- 같은 Supabase 프로젝트를 다른 앱도 쓴다. 그래서 이 앱은 전부 room 스키마에 둔다
-- (대시보드 → Project Settings → Data API → Exposed schemas 에 room 을 넣어야 앱이 닿는다).
-- 로그인 계정(auth.users)은 프로젝트에 하나라 나뉘지 않는다 — 이 앱 사람인지는 room.members 로 가린다.
--
-- 권한 요약
--   gatherings      누구나 읽기 / 운영자만 쓰기
--   registrations   신청자는 테이블에 직접 못 닿는다 — 아래 submit/lookup/update/cancel 함수로만.
--                   운영자는 전부.
--   room_plans      운영자만. 집회별 방배정(방·참석자·배정) 문서. 저장은 save_room_plan — 버전 검사.
--   운영자는 네 단계다 (PLAN_GATHERING.md §24).
--     수퍼어드민   room.admins. 모든 집회의 설정·삭제 + 집회관리자 가입 승인. 가입으로는 못 되고
--                  SQL Editor 에서 room.admins 에 직접 넣는다. (코드·주석의 "전체 운영자")
--     집회관리자   운영자 웹에서 가입 → 수퍼어드민 승인(members.status = owner) → 집회를 하나 만든다
--                  (gatherings.created_by). 그 집회의 설정·삭제 + 초대 링크 가입자 승인·역할 부여·해제.
--     보조운영자   초대 링크로 가입 → 집회관리자 승인 → 집회관리자가 역할을 올려 준다
--                  (gathering_admins.role = assistant). 그 집회의 설정·운영. 만들기·삭제·운영자 관리는 못 한다.
--     운영스탭     초대 링크로 가입 → 집회관리자 승인 (role = staff, 승인하면 이 역할로 시작).
--                  신청 확정·참석자·방·방배정·담당구역. 집회 설정은 못 연다.
--   판정 함수 셋 — 그 집회를 다루는가 room.manages, 설정을 고치는가 room.configures,
--   지우고 운영자를 관리하는가 room.owns. 승인 전(gathering_admins.approved = false)이면 아무것도 못 한다.
--   이 앱 가입자 = room.members. 운영자 웹에서 가입할 때 남긴 표시(room_signup)를 보고 첫 로그인에 넣는다.
--     pending  직접 가입, 전체 운영자 승인 대기. 아무 데이터에도 못 닿는다.
--     owner    승인됨. 집회를 하나 만들 수 있고 그 집회를 관리한다(gatherings.created_by).
--     helper   집회 초대 링크로 가입. 그 집회의 집회관리자가 승인하면 그 집회만 다룬다(gathering_admins).
--     rejected 거절됨. 계정은 지우지 않는다 — 다른 앱도 쓰는 계정일 수 있다.
--
-- 함수가 던지는 에러 메시지(앱이 이 문자열로 안내 문구를 고른다)
--   CLOSED  INVALID_PHONE  INVALID_PIN  INVALID_PEOPLE  INVALID_TEXT  INVALID_QUOTED
--   ALREADY_REGISTERED  TOO_MANY_ATTEMPTS  NOT_EDITABLE  FORBIDDEN  NOT_FOUND  CONFLICT
--   NO_ACCOUNT (집회 운영자로 등록하려는 이메일의 계정이 없음)  NO_SUCH_ADMIN (이미 해제된 운영자)
--   INVALID_ITEMS (스탭이 보낸 담당구역 할 일 표가 너무 크거나 배열이 아님)
--   BAD_INVITE (집회 초대 링크가 틀렸거나 새 링크로 바뀜)
--   INVALID_ROLE (집회 운영자 역할이 assistant / staff 가 아님)

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists room;
grant usage on schema room to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 테이블
-- ---------------------------------------------------------------------------

create table if not exists room.admins (
  user_id uuid primary key references auth.users on delete cascade
);

create table if not exists room.gatherings (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null default 'gathering'     -- 'gathering' | 'homestay' (lib/gathering.dart)
    check (kind in ('gathering', 'homestay')),
  dateless boolean not null default false,   -- 날짜 없이 참가/미참가만 받는 집회. 만들 때만 정함 (start_date = end_date = 기준일)
  schedule jsonb not null default '[]',      -- 일정표 [{date, time, title}]
  off_days date[] not null default '{}',     -- 일정 없는 날 (신청 웹에서 못 고름)
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
  field_specs jsonb not null default '{}',   -- 추가 항목 형식 {이름: {type, options}}. 없는 이름 = 텍스트
  hidden_fields text[] not null default '{}',  -- 신청서에서 뺀 기본 항목: birthYear, gender, cell, zone, minister
  shown_fields text[] not null default '{}',   -- 기본이 '안 받음'인 기본 항목 중 켠 것: staff
  required_fields text[] not null default '{birthYear,gender}',  -- 신청서에서 꼭 채워야 하는 기본 항목
  open boolean not null default false,
  deadline date,                             -- 이 날(한국 시간)까지 신청 받음
  minister_notice_on boolean not null default true,  -- 사역자를 체크한 신청자에게 안내 문구를 보일지
  minister_notice text,                      -- 그 문구. 비우면 앱 기본 문구
  created_at timestamptz not null default now()
);
-- 이미 만든 DB 에 새 칸 추가.
alter table room.gatherings add column if not exists kind text not null default 'gathering';
alter table room.gatherings drop constraint if exists gatherings_kind_check;
alter table room.gatherings add constraint gatherings_kind_check
  check (kind in ('gathering', 'homestay'));
alter table room.gatherings add column if not exists schedule jsonb not null default '[]';
alter table room.gatherings add column if not exists off_days date[] not null default '{}';
alter table room.gatherings add column if not exists hidden_fields text[] not null default '{}';
alter table room.gatherings add column if not exists required_fields text[] not null default '{birthYear,gender}';
-- 나중에 생긴 기본 항목(staff)은 여기에 담는다. 없으면 신청서에 안 나오므로 예전 집회가 그대로 있다.
alter table room.gatherings add column if not exists shown_fields text[] not null default '{}';
alter table room.gatherings add column if not exists minister_notice_on boolean not null default true;
alter table room.gatherings add column if not exists minister_notice text;
alter table room.gatherings add column if not exists field_specs jsonb not null default '{}';
alter table room.gatherings add column if not exists dateless boolean not null default false;

-- 집회별 운영자. 이 집회의 설정·신청·방배정만 만질 수 있다 (새 집회는 못 만든다).
-- 전체 운영자(room.admins)는 모든 집회를 관리하므로 여기 없어도 된다.
create table if not exists room.gathering_admins (
  gathering_id uuid not null references room.gatherings on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (gathering_id, user_id)
);
-- 역할(보조운영자 assistant / 운영스탭 staff)과 승인. 이미 등록된 사람은 지금처럼 설정까지 고치고
-- 승인도 끝난 것으로 채운다(덧씌워도 권한이 줄지 않게). 새로 들어오는 사람은 승인 대기 + 운영스탭.
alter table room.gathering_admins add column if not exists role text not null default 'assistant';
alter table room.gathering_admins alter column role set default 'staff';
alter table room.gathering_admins drop constraint if exists gathering_admins_role_check;
update room.gathering_admins set role = 'assistant' where role = 'manager';  -- 역할 첫 판의 이름
alter table room.gathering_admins add constraint gathering_admins_role_check
  check (role in ('assistant', 'staff'));
alter table room.gathering_admins add column if not exists approved boolean not null default true;
alter table room.gathering_admins alter column approved set default false;

-- 이 집회를 만든 사람 (승인된 가입자 owner 는 하나만 만들 수 있다). 고쳐도 바뀌지 않는다(_keep_owner).
alter table room.gatherings add column if not exists created_by uuid
  default auth.uid() references auth.users on delete set null;

-- 이 앱 가입자. 맨 위 주석의 pending / owner / helper / rejected.
create table if not exists room.members (
  user_id uuid primary key references auth.users on delete cascade,
  status text not null check (status in ('pending', 'owner', 'helper', 'rejected')),
  created_at timestamptz not null default now()
);

-- 집회 초대 링크의 코드. gatherings 는 누구나 읽으므로 거기 두면 코드가 샌다.
create table if not exists room.gathering_invites (
  gathering_id uuid primary key references room.gatherings on delete cascade,
  code text not null unique
);

create table if not exists room.registrations (
  id uuid primary key default gen_random_uuid(),
  gathering_id uuid not null references room.gatherings on delete cascade,
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
  paid_ref text,                             -- 은행 내역으로 자동 확인한 근거 거래. null = 수동 확인
  admin_memo text,                           -- 신청자에게는 안 보인다
  -- 지정 할인 (운영자만 바꾼다. 신청자 조회에는 보인다)
  discount_pct int not null default 0 check (discount_pct between 0 and 100),
  discount_amount int not null default 0 check (discount_amount >= 0),
  discount_note text,
  created_at timestamptz not null default now(),  -- 사전등록 할인 기준. 앱이 못 바꾼다
  updated_at timestamptz not null default now()
);
-- 이미 만든 DB 에 새 칸 추가.
alter table room.registrations add column if not exists discount_pct int not null default 0
  check (discount_pct between 0 and 100);
alter table room.registrations add column if not exists discount_amount int not null default 0
  check (discount_amount >= 0);
alter table room.registrations add column if not exists discount_note text;
alter table room.registrations add column if not exists paid_ref text;

-- 휴대폰 1개 = 진행 중인 신청 1건. 취소한 사람은 다시 신청할 수 있다.
create unique index if not exists registrations_active_phone
  on room.registrations (gathering_id, phone) where status <> 'cancelled';

-- PIN 오답 기록. 30분에 5번 틀리면 그 번호는 잠긴다.
create table if not exists room.lookup_failures (
  phone text not null,
  at timestamptz not null default now()
);
create index if not exists lookup_failures_phone_at on room.lookup_failures (phone, at);

-- 방배정. 집회 하나 = 문서 하나 (lib/models.dart 의 Event JSON). 여러 PC·태블릿이 같은 문서를 연다.
create table if not exists room.room_plans (
  gathering_id uuid primary key references room.gatherings on delete cascade,
  data jsonb not null,
  version int not null default 1,            -- 저장할 때마다 +1. 동시 수정 검사용
  updated_at timestamptz not null default now()
);

create or replace function room._touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists touch on room.registrations;
create trigger touch before update on room.registrations
  for each row execute function room._touch();

-- 만든 사람은 바꿀 수 없다. 바꿀 수 있으면 owner 가 자기 집회를 남에게 넘기고 하나 더 만든다.
create or replace function room._keep_owner() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.created_by := old.created_by;
  return new;
end $$;

drop trigger if exists keep_owner on room.gatherings;
create trigger keep_owner before update on room.gatherings
  for each row execute function room._keep_owner();

-- ---------------------------------------------------------------------------
-- 권한 (RLS)
-- ---------------------------------------------------------------------------

-- 전체 운영자 (모든 집회 + 계정 승인 + 새 집회 만들기).
create or replace function room.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from room.admins where user_id = auth.uid())
$$;

-- 승인된 집회관리자(owner)인가. 거절(rejected)되면 만든 집회도 못 다룬다.
create or replace function room._is_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from room.members where user_id = auth.uid() and status = 'owner')
$$;

-- 이 집회의 주인인가 = 수퍼어드민이거나 이 집회를 만든 집회관리자.
-- 집회 삭제, 초대 링크(만들기·바꾸기), 초대 링크 가입자 승인·역할 부여·해제, 이메일로 운영자 등록.
-- 만든 사람이 지금도 승인된 집회관리자(owner)여야 한다 — 나중에 거절되면 남은 세션으로도 못 다룬다.
create or replace function room.owns(p_gathering uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select room.is_admin()
      or (exists (select 1 from room.gatherings
                   where id = p_gathering and created_by = auth.uid())
          and room._is_owner())
$$;

-- 이 집회를 다루는가(신청·방배정) = 주인이거나, 승인된 보조운영자·운영스탭.
create or replace function room.manages(p_gathering uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select room.owns(p_gathering)
      or exists (select 1 from room.gathering_admins
                  where gathering_id = p_gathering and user_id = auth.uid() and approved)
$$;

-- 이 집회의 설정(이름·날짜·회비·신청서·이미지)을 고치는가 = 주인이거나, 승인된 보조운영자.
-- 운영스탭(staff)은 manages 만 통과한다.
create or replace function room.configures(p_gathering uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select room.owns(p_gathering)
      or exists (select 1 from room.gathering_admins
                  where gathering_id = p_gathering and user_id = auth.uid()
                    and approved and role = 'assistant')
$$;

-- 관리자 앱에 들어올 수 있는 사람인가 (수퍼어드민, 승인된 집회관리자, 승인된 집회별 운영자).
create or replace function room.can_manage() returns boolean
language sql stable security definer set search_path = '' as $$
  select room.is_admin()
      or exists (select 1 from room.members where user_id = auth.uid() and status = 'owner')
      or exists (select 1 from room.gathering_admins where user_id = auth.uid() and approved)
$$;

-- 새 집회를 만들 수 있는가 = 전체 운영자이거나, 승인된 가입자(owner)인데 아직 만든 집회가 없다.
-- ponytail: 두 기기에서 동시에 [만들기]를 누르면 둘 다 통과할 수 있다. 문제가 되면 created_by 에
--           owner 용 부분 unique 인덱스를 건다(전체 운영자 행은 빼고).
create or replace function room.can_create() returns boolean
language sql stable security definer set search_path = '' as $$
  select room.is_admin() or (
    exists (select 1 from room.members where user_id = auth.uid() and status = 'owner')
    and not exists (select 1 from room.gatherings where created_by = auth.uid()))
$$;

-- 내가 관리하는 집회들(만든 것 + 운영자로 등록된 것). 전체 운영자는 목록을 가릴 필요가 없다
-- (앱은 is_admin 이 true 면 전부 보여준다).
create or replace function room.my_gatherings() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select gathering_id from room.gathering_admins where user_id = auth.uid() and approved
  union
  select id from room.gatherings where created_by = auth.uid() and room._is_owner()
$$;

-- 내가 설정까지 고칠 수 있는 집회들. 앱이 운영스탭에게 [집회 설정] 메뉴를 막는 데 쓴다.
create or replace function room.my_configured() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select gathering_id from room.gathering_admins
   where user_id = auth.uid() and approved and role = 'assistant'
  union
  select id from room.gatherings where created_by = auth.uid() and room._is_owner()
$$;

alter table room.admins enable row level security;           -- 정책 없음 = API 로는 아무도 못 봄
alter table room.gathering_admins enable row level security; -- 정책 없음 — 아래 함수로만 드나든다
alter table room.members enable row level security;          -- 정책 없음
alter table room.gathering_invites enable row level security; -- 정책 없음
alter table room.gatherings enable row level security;
alter table room.registrations enable row level security;
alter table room.lookup_failures enable row level security;  -- 정책 없음
alter table room.room_plans enable row level security;

drop policy if exists "누구나 읽기" on room.gatherings;
create policy "누구나 읽기" on room.gatherings
  for select using (true);

-- 새 집회는 수퍼어드민, 또는 집회관리자가 하나만. 지우는 건 수퍼어드민과 그 집회를 만든 집회관리자.
-- 고치는 건 거기에 보조운영자까지(운영스탭은 못 고친다).
drop policy if exists "운영자 쓰기" on room.gatherings;
drop policy if exists "전체 운영자만 만들기" on room.gatherings;
drop policy if exists "만들 수 있는 사람만" on room.gatherings;
create policy "만들 수 있는 사람만" on room.gatherings
  for insert to authenticated
  with check (room.is_admin() or (room.can_create() and created_by = auth.uid()));

drop policy if exists "맡은 집회 고치기" on room.gatherings;
create policy "맡은 집회 고치기" on room.gatherings
  for update to authenticated using (room.configures(id)) with check (room.configures(id));

drop policy if exists "전체 운영자만 삭제" on room.gatherings;
drop policy if exists "주인만 삭제" on room.gatherings;
create policy "주인만 삭제" on room.gatherings
  for delete to authenticated using (room.owns(id));

drop policy if exists "운영자만" on room.registrations;
create policy "운영자만" on room.registrations
  for all to authenticated
  using (room.manages(gathering_id)) with check (room.manages(gathering_id));

drop policy if exists "운영자만" on room.room_plans;
create policy "운영자만" on room.room_plans
  for all to authenticated
  using (room.manages(gathering_id)) with check (room.manages(gathering_id));

-- 테이블 권한을 명시한다. Supabase 의 "새 테이블 자동 공개" 설정이 켜져 있든 꺼져 있든 같게 동작하도록.
revoke all on room.admins, room.gathering_admins, room.gatherings, room.registrations,
  room.lookup_failures, room.room_plans, room.members, room.gathering_invites
  from anon, authenticated;
grant select on room.gatherings to anon, authenticated;
grant insert, update, delete on room.gatherings to authenticated;
grant select, insert, update, delete on room.registrations to authenticated;  -- RLS 가 운영자로 제한
grant select, insert, update on room.room_plans to authenticated;  -- RLS 가 운영자로 제한. 저장은 save_room_plan 으로

-- ---------------------------------------------------------------------------
-- 내부 함수 (API 로 못 부른다)
-- ---------------------------------------------------------------------------

create or replace function room._assert_open(p_gathering uuid) returns void
language plpgsql set search_path = '' as $$
declare
  g room.gatherings;
begin
  select * into g from room.gatherings where id = p_gathering;
  if not found or not g.open
     or (g.deadline is not null and (now() at time zone 'Asia/Seoul')::date > g.deadline) then
    raise exception 'CLOSED';
  end if;
end $$;

-- 신청서 입력 검사. 앱에서도 검사하지만 여기가 최종 관문.
create or replace function room._check_input(
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
create or replace function room._verify(p_gathering uuid, p_phone text, p_pin text)
returns room.registrations
language plpgsql set search_path = '' as $$
declare
  ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  r room.registrations;
begin
  -- 같은 번호로 동시에 여러 요청을 보내 횟수 검사를 앞질러 가는 걸 막는다
  perform pg_advisory_xact_lock(hashtext('lookup:' || ph));
  delete from room.lookup_failures where at < now() - interval '1 day';

  if (select count(*) from room.lookup_failures
       where phone = ph and at > now() - interval '30 minutes') >= 5 then
    raise exception 'TOO_MANY_ATTEMPTS';
  end if;

  select * into r from room.registrations
   where gathering_id = p_gathering and phone = ph
   order by status = 'cancelled', created_at desc
   limit 1;

  if not found or r.pin_hash is distinct from extensions.crypt(coalesce(p_pin, ''), r.pin_hash) then
    insert into room.lookup_failures (phone) values (ph);
    return null;
  end if;
  return r;
end $$;

-- 홈스테이: 이 신청으로 만든 방(가정)에 배정된 참석자. 없으면 빈 배열.
-- 신청자에게 보일 내용만 고른다 — 운영자 메모(note)·방 id 는 빼고 준다.
-- 묵는 기간(checkIn·checkOut, 띄엄띄엄이면 nights)도 같이 준다 — 기간을 나눈 조각은 제 기간을 갖는다.
-- 일반 집회는 registrationId 를 가진 방이 없어 항상 [] 다.
create or replace function room._assigned(p_gathering uuid, p_registration uuid)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', a->>'name', 'gender', a->>'gender', 'age', a->'age',
           'phone', a->>'phone', 'cell', a->>'cell', 'zone', a->>'zone',
           'checkIn', a->>'checkIn', 'checkOut', a->>'checkOut',
           'nights', a->'stayNights')), '[]'::jsonb)
    from room.room_plans p,
         lateral jsonb_array_elements(p.data->'rooms') r,
         lateral jsonb_array_elements(p.data->'attendees') a
   where p.gathering_id = p_gathering
     and r->>'registrationId' = p_registration::text
     and a->>'roomId' = r->>'id'
$$;

-- 이 신청의 사람들이 맡은 담당구역. 없으면 빈 배열.
-- 신청서의 people[].id 가 곧 참석자의 personId 라 (lib/store.dart attendeeOf) 신청 한 건만 보면 된다.
-- 같이 일하는 사람은 이름만 준다 — 연락처·운영자 메모는 신청자에게 줄 내용이 아니다.
create or replace function room._my_duties(p_gathering uuid, p_people jsonb)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d->>'id', 'name', d->>'name', 'tasks', d->>'tasks',
           'capacity', d->'capacity', 'items', coalesce(d->'items', '[]'::jsonb),
           'members', coalesce((
             select jsonb_agg(a->>'name')
               from jsonb_array_elements(p.data->'attendees') a
              where a->>'splitOf' is null
                and d->'personIds' ? (a->>'id')), '[]'::jsonb)) order by d->>'name'), '[]'::jsonb)
    from room.room_plans p,
         lateral jsonb_array_elements(p.data->'duties') d
   where p.gathering_id = p_gathering
     and exists (select 1 from jsonb_array_elements(p_people) x
                  where d->'personIds' ? (x->>'id'))
$$;

-- ---------------------------------------------------------------------------
-- 신청 웹이 부르는 함수
-- ---------------------------------------------------------------------------

-- 신청. 성공하면 신청 id.
create or replace function room.submit_registration(
  p_gathering uuid, p_phone text, p_pin text, p_people jsonb,
  p_depositor text, p_memo text, p_quoted int
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  new_id uuid;
begin
  perform room._assert_open(p_gathering);
  if ph !~ '^01[0-9]{8,9}$' then raise exception 'INVALID_PHONE'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN'; end if;
  perform room._check_input(p_people, p_depositor, p_memo, p_quoted);

  insert into room.registrations (gathering_id, phone, pin_hash, people, depositor, memo, quoted)
  values (p_gathering, ph, extensions.crypt(p_pin, extensions.gen_salt('bf', 8)), p_people,
          nullif(trim(p_depositor), ''), nullif(trim(p_memo), ''), p_quoted)
  returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'ALREADY_REGISTERED';
end $$;

-- 조회. 맞으면 신청(jsonb, PIN 해시·운영자 메모 제외), 틀리면 null.
create or replace function room.lookup_registration(p_gathering uuid, p_phone text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r room.registrations := room._verify(p_gathering, p_phone, p_pin);
begin
  if r.id is null then return null; end if;
  return (to_jsonb(r) - 'pin_hash' - 'admin_memo')
      || jsonb_build_object('assigned', room._assigned(p_gathering, r.id));
end $$;

-- 수정. 입금대기 + 신청 받는 중일 때만. 상태·입금액은 못 건드린다. 틀리면 null.
create or replace function room.update_registration(
  p_gathering uuid, p_phone text, p_pin text, p_people jsonb,
  p_depositor text, p_memo text, p_quoted int
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r room.registrations := room._verify(p_gathering, p_phone, p_pin);
begin
  if r.id is null then return null; end if;
  if r.status <> 'pending' then raise exception 'NOT_EDITABLE'; end if;
  perform room._assert_open(p_gathering);
  perform room._check_input(p_people, p_depositor, p_memo, p_quoted);

  update room.registrations
     set people = p_people, depositor = nullif(trim(p_depositor), ''),
         memo = nullif(trim(p_memo), ''), quoted = p_quoted
   where id = r.id
  returning * into r;
  return to_jsonb(r) - 'pin_hash' - 'admin_memo';
end $$;

-- 취소. 입금대기일 때만 (마감 후에도 가능). 틀리면 null.
create or replace function room.cancel_registration(p_gathering uuid, p_phone text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r room.registrations := room._verify(p_gathering, p_phone, p_pin);
begin
  if r.id is null then return null; end if;
  if r.status <> 'pending' then raise exception 'NOT_EDITABLE'; end if;

  update room.registrations set status = 'cancelled' where id = r.id
  returning * into r;
  return to_jsonb(r) - 'pin_hash' - 'admin_memo';
end $$;

-- ---------------------------------------------------------------------------
-- 스탭 페이지가 부르는 함수 (신청 웹과 같은 관문: 휴대폰 + PIN)
-- ---------------------------------------------------------------------------

-- 내 담당구역과 할 일. 휴대폰+PIN 이 틀리면 null, 맡은 구역이 없으면 duties 가 빈 배열.
-- 취소한 신청은 들어갈 수 없다.
create or replace function room.lookup_duties(p_gathering uuid, p_phone text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r room.registrations := room._verify(p_gathering, p_phone, p_pin);
begin
  if r.id is null or r.status = 'cancelled' then return null; end if;
  return jsonb_build_object(
    'name', coalesce(r.people->0->>'name', ''),
    'duties', room._my_duties(p_gathering, r.people));
end $$;

-- 내가 맡은 담당구역의 할 일 표를 통째로 바꾼다. 바뀐 표를 돌려준다.
-- 구역 하나의 items 만 건드리므로 다른 구역·방배정은 스탭이 덮어쓸 수 없다.
-- ponytail: 버전 검사를 하지 않는다 — 같은 구역을 둘이 동시에 고치면 나중 저장이 이긴다.
-- 문제가 되면 save_room_plan 처럼 p_version 을 받아 CONFLICT 를 던지면 된다.
create or replace function room.save_duty_items(
  p_gathering uuid, p_phone text, p_pin text, p_duty text, p_items jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r room.registrations := room._verify(p_gathering, p_phone, p_pin);
  idx int;
begin
  if r.id is null or r.status = 'cancelled' then return null; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) > 200 or length(p_items::text) > 20000 then
    raise exception 'INVALID_ITEMS';
  end if;
  -- 내가 배정된 구역인지 본다 (_my_duties 와 같은 규칙).
  if not exists (select 1 from jsonb_array_elements(room._my_duties(p_gathering, r.people)) d
                  where d->>'id' = p_duty) then
    raise exception 'FORBIDDEN';
  end if;

  select i - 1 into idx
    from room.room_plans p, lateral jsonb_array_elements(p.data->'duties') with ordinality t(e, i)
   where p.gathering_id = p_gathering and e->>'id' = p_duty;
  if idx is null then raise exception 'NOT_FOUND'; end if;

  update room.room_plans
     set data = jsonb_set(data, array['duties', idx::text, 'items'], p_items),
         version = version + 1, updated_at = now()
   where gathering_id = p_gathering;
  return p_items;
end $$;

-- ---------------------------------------------------------------------------
-- 운영자 함수
-- ---------------------------------------------------------------------------

-- PIN 재설정. 그 번호의 오답 기록(잠금)도 같이 푼다.
create or replace function room.reset_pin(p_registration uuid, p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  ph text;
  gid uuid;
begin
  -- 없는 신청이면 manages(null) 이 전체 운영자를 통과시켜 "성공했는데 0행" 이 된다.
  -- 다만 운영자가 아닌 사람에게 신청의 있고 없음을 알려주지 않도록 FORBIDDEN 을 먼저 본다.
  select gathering_id into gid from room.registrations where id = p_registration;
  if gid is null then
    if not room.can_manage() then raise exception 'FORBIDDEN'; end if;
    raise exception 'NOT_FOUND';
  end if;
  if not room.manages(gid) then raise exception 'FORBIDDEN'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN'; end if;

  update room.registrations
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 8))
   where id = p_registration
  returning phone into ph;
  if not found then raise exception 'NOT_FOUND'; end if;
  delete from room.lookup_failures where phone = ph;
end $$;

-- 운영자가 대신 받는 신청 (전화·현장 접수). 신청 받는 중이 아니어도 된다. 성공하면 신청 id.
-- 입력 검사·PIN 해시는 submit_registration 과 같다 — 신청자가 나중에 휴대폰+PIN 으로 조회한다.
create or replace function room.admin_add_registration(
  p_gathering uuid, p_phone text, p_pin text, p_people jsonb,
  p_depositor text, p_memo text, p_quoted int
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  new_id uuid;
begin
  if not room.manages(p_gathering) then raise exception 'FORBIDDEN'; end if;
  if ph !~ '^01[0-9]{8,9}$' then raise exception 'INVALID_PHONE'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN'; end if;
  perform room._check_input(p_people, p_depositor, p_memo, p_quoted);

  insert into room.registrations (gathering_id, phone, pin_hash, people, depositor, memo, quoted)
  values (p_gathering, ph, extensions.crypt(p_pin, extensions.gen_salt('bf', 8)), p_people,
          nullif(trim(p_depositor), ''), nullif(trim(p_memo), ''), p_quoted)
  returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'ALREADY_REGISTERED';
end $$;

-- 방배정 저장. p_version = 마지막으로 읽은 버전(서버에 아직 없으면 0). 성공하면 새 버전.
-- 그사이 다른 기기가 저장했으면 CONFLICT — 앱은 덮어쓰지 않고 최신 문서를 다시 읽는다.
create or replace function room.save_room_plan(p_gathering uuid, p_data jsonb, p_version int)
returns int
language plpgsql set search_path = '' as $$
declare
  v int;
begin
  if not room.manages(p_gathering) then raise exception 'FORBIDDEN'; end if;
  if p_version = 0 then
    insert into room.room_plans (gathering_id, data) values (p_gathering, p_data)
    on conflict (gathering_id) do nothing
    returning version into v;
  else
    update room.room_plans
       set data = p_data, version = version + 1, updated_at = now()
     where gathering_id = p_gathering and version = p_version
    returning version into v;
  end if;
  if v is null then raise exception 'CONFLICT'; end if;
  return v;
end $$;

-- 이 집회의 보조운영자·운영스탭 목록(승인 대기 포함). 집회 설정 화면이 쓰므로 설정을 고치는 사람만 본다.
-- 돌려주는 칸이 늘어 create or replace 로는 못 바꾼다 — 지우고 다시 만든다(권한은 아래에서 다시 준다).
drop function if exists room.gathering_admin_list(uuid);
create or replace function room.gathering_admin_list(p_gathering uuid)
returns table (user_id uuid, email text, created_at timestamptz, role text, approved boolean)
language sql stable security definer set search_path = '' as $$
  select a.user_id, u.email::text, a.created_at, a.role, a.approved
    from room.gathering_admins a
    join auth.users u on u.id = a.user_id
   where a.gathering_id = p_gathering and room.configures(p_gathering)
   order by a.approved, a.created_at
$$;

-- 이메일로 계정을 찾아 이 집회의 운영스탭으로 등록한다(집회관리자가 직접 넣으므로 승인도 끝난 것으로).
-- 이 앱 계정이 없으면 NO_ACCOUNT (먼저 초대 링크를 보낸다). 같은 프로젝트의 다른 앱 계정은 못 찾는다.
create or replace function room.add_gathering_admin(p_gathering uuid, p_email text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid;
begin
  if not room.owns(p_gathering) then raise exception 'FORBIDDEN'; end if;
  -- 같은 주소로 계정이 여럿일 수 있다(확인 안 된 가입 등). 확인된 계정을 먼저, 그다음 먼저 만든 것.
  -- order 가 없으면 매번 다른 계정이 뽑혀 엉뚱한 사람에게 권한이 간다.
  select u.id into uid from auth.users u
   where lower(u.email) = lower(trim(coalesce(p_email, '')))
     and (exists (select 1 from room.members m where m.user_id = u.id)
          or exists (select 1 from room.admins a where a.user_id = u.id)
          or u.raw_user_meta_data->>'room_signup' = 'true')
   order by (u.email_confirmed_at is null), u.created_at
   limit 1;
  if uid is null then raise exception 'NO_ACCOUNT'; end if;
  insert into room.gathering_admins (gathering_id, user_id, approved) values (p_gathering, uid, true)
  on conflict (gathering_id, user_id) do update set approved = true;
  return uid;
end $$;

-- 초대 링크로 들어온 사람을 승인한다(운영스탭으로 시작). 이미 승인됐거나 없으면 NO_SUCH_ADMIN.
create or replace function room.approve_gathering_admin(p_gathering uuid, p_user uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not room.owns(p_gathering) then raise exception 'FORBIDDEN'; end if;
  update room.gathering_admins set approved = true
   where gathering_id = p_gathering and user_id = p_user and not approved;
  if not found then raise exception 'NO_SUCH_ADMIN'; end if;
end $$;

-- 해제. 승인 대기인 사람을 거절할 때도 이걸 쓴다.
create or replace function room.remove_gathering_admin(p_gathering uuid, p_user uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not room.owns(p_gathering) then raise exception 'FORBIDDEN'; end if;
  delete from room.gathering_admins
   where gathering_id = p_gathering and user_id = p_user;
  -- NOT_FOUND 는 신청 조회에서 쓰는 코드라 안내 문구가 엉뚱해진다.
  if not found then raise exception 'NO_SUCH_ADMIN'; end if;
  -- 초대 링크를 바꾼다. 안 바꾸면 해제·거절한 사람이 같은 링크로 다시 승인 대기에 오른다.
  update room.gathering_invites set code = encode(extensions.gen_random_bytes(12), 'hex')
   where gathering_id = p_gathering;
end $$;

-- 승인된 사람의 역할을 바꾼다: assistant(보조운영자) / staff(운영스탭). 집회관리자·수퍼어드민만.
create or replace function room.set_gathering_admin_role(p_gathering uuid, p_user uuid, p_role text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not room.owns(p_gathering) then raise exception 'FORBIDDEN'; end if;
  if p_role is null or p_role not in ('assistant', 'staff') then raise exception 'INVALID_ROLE'; end if;
  update room.gathering_admins set role = p_role
   where gathering_id = p_gathering and user_id = p_user and approved;
  if not found then raise exception 'NO_SUCH_ADMIN'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- 이 앱 가입 · 초대 링크 · 승인
-- ---------------------------------------------------------------------------

-- 지금 로그인한 사람을 이 앱 가입자로 넣는다. 초대 코드가 맞으면 helper + 그 집회의 승인 대기 운영자,
-- 아니면 pending(수퍼어드민 승인 대기). 이미 가입자면 상태는 그대로 두고 초대받은 집회만 더한다.
-- 초대받은 집회 id 를 돌려준다(없으면 null).
create or replace function room._join(p_invite text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  g uuid;
begin
  select gathering_id into g from room.gathering_invites where code = nullif(trim(p_invite), '');
  if not room.is_admin() then  -- 전체 운영자는 가입자 표가 필요 없다
    insert into room.members (user_id, status)
    values (auth.uid(), case when g is null then 'pending' else 'helper' end)
    on conflict do nothing;
  end if;
  -- 주인(만든 집회관리자·수퍼어드민)이 자기 링크를 눌러 봐도 승인 대기에 끼지 않게 한다.
  if g is not null and not room.owns(g) then
    insert into room.gathering_admins (gathering_id, user_id) values (g, auth.uid())
    on conflict do nothing;
  end if;
  return g;
end $$;

-- 앱이 로그인할 때마다 부른다. 운영자 웹에서 가입한 계정(room_signup 표시)이 아직 가입자 표에
-- 없으면 여기서 넣는다 — 메일 확인을 켜 두면 가입 순간엔 로그인이 안 되기 때문이다.
-- 첫 번째 때만 넣는다: 해제된 helper 가 다음 로그인에 같은 초대 코드로 되살아나지 않게.
-- 돌려주는 값: ok(관리자 앱에 들어온다) / waiting(초대 링크 가입, 집회관리자 승인 대기) / pending /
--   rejected / helper(맡은 집회가 없어짐) / none(이 앱 계정 아님)
create or replace function room.enter_app() returns text
language plpgsql security definer set search_path = '' as $$
declare
  meta jsonb;
begin
  if auth.uid() is null then raise exception 'FORBIDDEN'; end if;
  if not room.is_admin() and not exists (select 1 from room.members where user_id = auth.uid()) then
    select raw_user_meta_data into meta from auth.users where id = auth.uid();
    -- 가입 때 남긴 초대 코드가 지금은 틀리면(새 링크로 바뀜) 넣지 않는다 — 넣으면 초대받으려던 사람이
    -- 수퍼어드민의 집회관리자 신청 목록에 엉뚱하게 오른다. 새 링크로 로그인하면 join_app 이 넣는다.
    if meta->>'room_signup' = 'true'
       and (coalesce(meta->>'room_invite', '') = ''
            or exists (select 1 from room.gathering_invites where code = meta->>'room_invite')) then
      perform room._join(meta->>'room_invite');
    end if;
  end if;
  if room.can_manage() then return 'ok'; end if;
  -- 초대 링크로 들어와 그 집회의 집회관리자 승인을 기다리는 중
  if exists (select 1 from room.gathering_admins where user_id = auth.uid() and not approved) then
    return 'waiting';
  end if;
  return coalesce((select status from room.members where user_id = auth.uid()), 'none');
end $$;

-- 초대 링크로 로그인했거나, 다른 앱에서 이미 만든 계정으로 이 앱에 가입할 때.
-- p_invite 가 비었으면 가입 신청(pending)만, 있는데 틀렸으면 BAD_INVITE.
create or replace function room.join_app(p_invite text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'FORBIDDEN'; end if;
  if nullif(trim(p_invite), '') is not null
     and not exists (select 1 from room.gathering_invites where code = trim(p_invite)) then
    raise exception 'BAD_INVITE';
  end if;
  perform room._join(p_invite);
end $$;

-- 초대 코드가 지금 맞는가. 가입 창이 계정을 만들기 전에 본다(틀린 링크로 계정만 생기지 않게).
create or replace function room.invite_ok(p_invite text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from room.gathering_invites where code = nullif(trim(p_invite), ''))
$$;

-- 이 집회의 초대 코드. 없으면 만든다. p_renew 면 새 코드로 바꿔 예전 링크를 막는다.
create or replace function room.gathering_invite(p_gathering uuid, p_renew boolean)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  c text;
begin
  if not room.owns(p_gathering) then raise exception 'FORBIDDEN'; end if;
  insert into room.gathering_invites (gathering_id, code)
  values (p_gathering, encode(extensions.gen_random_bytes(12), 'hex'))
  on conflict (gathering_id) do update
    set code = case when p_renew then excluded.code else room.gathering_invites.code end
  returning code into c;
  return c;
end $$;

-- 승인을 기다리는 가입 신청 = 운영자 웹에서 직접 가입한 사람(초대 링크 아님) 중 아직 정해지지 않은 사람.
-- 메일 확인 전이라 가입자 표에 아직 없는 사람도 보인다. 다른 앱 계정은 안 보인다.
-- 전체 운영자가 아니면 빈 목록.
create or replace function room.admin_requests()
returns table (id uuid, email text, name text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select u.id, u.email::text, u.raw_user_meta_data->>'name', u.created_at
    from auth.users u
    left join room.members m on m.user_id = u.id
   where room.is_admin()
     and not exists (select 1 from room.admins a where a.user_id = u.id)
     and (m.status = 'pending'
          or (m.user_id is null
              and u.raw_user_meta_data->>'room_signup' = 'true'
              and coalesce(u.raw_user_meta_data->>'room_invite', '') = ''))
   order by u.created_at
$$;

-- 가입 승인 = 집회 하나를 만들 수 있게 한다(owner). 전체 운영자로 만들지는 않는다.
-- 메일 확인도 끝낸 것으로 친다 — 전체 운영자가 사람을 보고 승인한 게 본인 확인이다.
-- (기본 메일 서버는 프로젝트 팀원에게만 메일을 보내서, 확인 메일을 못 받아 로그인을 못 한다.)
create or replace function room.approve_admin(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not room.is_admin() then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'NOT_FOUND'; end if;
  insert into room.members (user_id, status) values (p_user, 'owner')
  on conflict (user_id) do update set status = 'owner';
  update auth.users set email_confirmed_at = now()
   where id = p_user and email_confirmed_at is null;
end $$;

-- 가입 거절. 계정은 지우지 않는다 — 같은 프로젝트의 다른 앱도 쓰는 계정일 수 있다.
-- 초대받아 맡은 집회가 있으면 그건 그대로 쓴다.
create or replace function room.reject_admin(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not room.is_admin() then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from auth.users where id = p_user)
     or exists (select 1 from room.admins where user_id = p_user) then
    raise exception 'NOT_FOUND';
  end if;
  insert into room.members (user_id, status) values (p_user, 'rejected')
  on conflict (user_id) do update set status = 'rejected';
end $$;

-- 함수 실행 권한도 명시한다 (Postgres 기본값은 "누구나 실행 가능").
revoke execute on function
  room._touch(),
  room._keep_owner(),
  room._join(text),
  room._is_owner(),
  room.enter_app(),
  room.join_app(text),
  room.gathering_invite(uuid, boolean),
  room.can_create(),
  room.can_manage(),
  room.add_gathering_admin(uuid, text),
  room.remove_gathering_admin(uuid, uuid),
  room.set_gathering_admin_role(uuid, uuid, text),
  room.approve_gathering_admin(uuid, uuid),
  room.gathering_admin_list(uuid),
  room.my_gatherings(),
  room.my_configured(),
  room._assert_open(uuid),
  room._check_input(jsonb, text, text, int),
  room._verify(uuid, text, text),
  room._assigned(uuid, uuid),
  room._my_duties(uuid, jsonb),
  room.reset_pin(uuid, text),
  room.admin_add_registration(uuid, text, text, jsonb, text, text, int),
  room.save_room_plan(uuid, jsonb, int),
  room.admin_requests(),
  room.approve_admin(uuid),
  room.reject_admin(uuid)
  from public, anon, authenticated;

grant execute on function
  room.is_admin(),  -- RLS 정책 안에서 불리므로 모두에게 필요
  room.owns(uuid),
  room.manages(uuid),
  room.configures(uuid),
  room.submit_registration(uuid, text, text, jsonb, text, text, int),
  room.lookup_registration(uuid, text, text),
  room.update_registration(uuid, text, text, jsonb, text, text, int),
  room.cancel_registration(uuid, text, text),
  room.lookup_duties(uuid, text, text),
  room.save_duty_items(uuid, text, text, text, jsonb),
  room.invite_ok(text)
  to anon, authenticated;

grant execute on function
  room.reset_pin(uuid, text),
  room.admin_add_registration(uuid, text, text, jsonb, text, text, int),
  room.save_room_plan(uuid, jsonb, int),
  room.admin_requests(),
  room.approve_admin(uuid),
  room.reject_admin(uuid),
  room.add_gathering_admin(uuid, text),
  room.remove_gathering_admin(uuid, uuid),
  room.set_gathering_admin_role(uuid, uuid, text),
  room.approve_gathering_admin(uuid, uuid),
  room.gathering_admin_list(uuid),
  room.my_gatherings(),
  room.my_configured(),
  room.can_manage(),
  room.can_create(),  -- 집회 만들기 정책 안에서도 불린다
  room.enter_app(),
  room.join_app(text),
  room.gathering_invite(uuid, boolean)
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

-- 파일 경로가 '<집회id>/...' 라 첫 칸으로 그 집회의 설정을 고칠 수 있는지 본다(포스터·배경은 집회 설정).
-- 집회 id 모양이 아니면 null 이 되고, 그때는 전체 운영자만 통과한다.
drop policy if exists "집회 이미지: 운영자 관리" on storage.objects;
create policy "집회 이미지: 운영자 관리" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'gathering-images'
    and room.configures(
      case when split_part(name, '/', 1) ~ '^[0-9a-fA-F-]{36}$'
           then split_part(name, '/', 1)::uuid end)
  )
  with check (
    bucket_id = 'gathering-images'
    and room.configures(
      case when split_part(name, '/', 1) ~ '^[0-9a-fA-F-]{36}$'
           then split_part(name, '/', 1)::uuid end)
  );

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

update room.registrations
   set people = pg_temp.upper_zones(people)
 where people <> pg_temp.upper_zones(people);

update room.room_plans
   set data = jsonb_set(data, '{attendees}', pg_temp.upper_zones(data->'attendees'))
 where jsonb_typeof(data->'attendees') = 'array'
   and data->'attendees' <> pg_temp.upper_zones(data->'attendees');
