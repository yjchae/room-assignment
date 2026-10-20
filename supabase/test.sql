-- schema.sql 로컬 검증. Supabase 전용 부분(auth, storage, anon/authenticated 역할)은 흉내만 낸다.
--
-- 실행 (빈 DB 에서, 이 파일이 있는 폴더 기준으로 schema.sql 을 읽는다):
--   psql -v ON_ERROR_STOP=1 -q -d <빈 DB> -f supabase/test.sql
-- 끝까지 가면 "ALL OK". 하나라도 틀리면 그 줄에서 FAIL 로 멈춘다.

\o /dev/null

-- ---------------------------------------------------------------------------
-- Supabase 흉내
-- ---------------------------------------------------------------------------
create role anon nologin;
create role authenticated nologin;

create schema auth;
create table auth.users (
  id uuid primary key, email varchar(255),
  raw_user_meta_data jsonb, created_at timestamptz default now(),
  email_confirmed_at timestamptz   -- 실제 Supabase 에도 있는 칸 (확인 메일을 누른 시각)
);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
-- 검사 문장이 계정 테이블을 들여다볼 수 있게. 실제 Supabase 에서도 앱은 이 테이블을 직접 읽지 않고
-- admin_requests()·approve_admin() 같은 security definer 함수로만 드나든다.
grant select on auth.users to anon, authenticated;

create schema storage;
create table storage.buckets (
  id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated;
grant all on storage.objects to anon, authenticated;

-- Supabase 의 public 기본값(새 테이블·함수를 anon/authenticated 에게 전부 연다)을 room 에도 걸어
-- 가장 느슨한 기본값에서도 schema.sql 이 막아내는지 본다.
create schema room;
alter default privileges in schema room grant all on tables to anon, authenticated;
alter default privileges in schema room grant all on functions to anon, authenticated;

\ir schema.sql
\ir schema.sql
-- ↑ 두 번 적용해도 에러가 없어야 한다 (대시보드에서 다시 Run 해도 되게)

-- ---------------------------------------------------------------------------
-- 검사 도구
-- ---------------------------------------------------------------------------
create schema t;
grant usage on schema t to anon, authenticated;

create function t.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', msg; end if;
end $$;

-- q 를 실행하면 want(정규식)에 맞는 에러가 나야 한다.
create function t.err(q text, want text) returns void language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    if sqlerrm ~ want then return; end if;
    raise exception 'FAIL: % → 기대 "%", 실제 "%"', q, want, sqlerrm;
  end;
  raise exception 'FAIL: % → 기대 "%" 인데 성공함', q, want;
end $$;

-- ---------------------------------------------------------------------------
-- 데이터: 운영자 a, 이 앱에 가입 신청만 한 b·c, 다른 앱(같은 프로젝트) 가입자 x,
--         집회 3개(열림 / 닫힘 / 마감 지남)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@x', null),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@x', '{"name":"비","room_signup":"true"}'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@x', '{"room_signup":"true"}'),
  ('99999999-9999-9999-9999-999999999999', 'x@x', '{"name":"다른 앱"}');
insert into room.admins values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into room.gatherings (id, name, start_date, end_date, open, deadline) values
  ('00000000-0000-0000-0000-000000000001', '열린 집회', '2026-10-09', '2026-10-11', true, null),
  ('00000000-0000-0000-0000-000000000002', '닫힌 집회', '2026-10-09', '2026-10-11', false, null),
  ('00000000-0000-0000-0000-000000000003', '마감 지난 집회', '2026-10-09', '2026-10-11', true, '2020-01-01');

-- ===========================================================================
-- 신청자 (로그인 안 함)
-- ===========================================================================
set role anon;
set request.jwt.claim.sub = '';

select t.ok((select count(*) from room.gatherings) = 3, '누구나 집회를 읽는다');
select t.ok((select bool_and(field_specs = '{}') from room.gatherings), '추가 항목 형식 칸은 기본이 {} (모두 텍스트)');
select t.err($q$insert into room.gatherings (name, start_date, end_date) values ('x', '2026-01-01', '2026-01-02')$q$,
             'permission denied');
select t.err($q$update room.gatherings set open = true$q$, 'permission denied');

-- 신청: 막혀야 하는 것
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000002', '01011112222', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'CLOSED');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000003', '01011112222', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'CLOSED');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-00000000dead', '01011112222', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'CLOSED');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '02-123-4567', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'INVALID_PHONE');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '12a4', '[{"name":"a"}]', null, null, 0)$q$, 'INVALID_PIN');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '12345', '[{"name":"a"}]', null, null, 0)$q$, 'INVALID_PIN');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '[]', null, null, 0)$q$, 'INVALID_PEOPLE');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '{"name":"a"}', null, null, 0)$q$, 'INVALID_PEOPLE');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', (select jsonb_agg(jsonb_build_object('name', i)) from generate_series(1, 21) i), null, null, 0)$q$, 'INVALID_PEOPLE');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '[{"name":"a"}]', repeat('가', 51), null, 0)$q$, 'INVALID_TEXT');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '[{"name":"a"}]', null, null, -1)$q$, 'INVALID_QUOTED');

-- 신청: 성공 (하이픈이 있어도 숫자만 저장)
select t.ok(room.submit_registration('00000000-0000-0000-0000-000000000001', '010-1234-5678', '1234',
  '[{"name":"홍길동","birthYear":1985},{"name":"홍아들","birthYear":2012}]', '홍길동', null, 415000) is not null,
  '신청이 된다');
select t.err($q$select room.submit_registration('00000000-0000-0000-0000-000000000001', '01012345678', '9999', '[{"name":"b"}]', null, null, 0)$q$,
             'ALREADY_REGISTERED');
select room.submit_registration('00000000-0000-0000-0000-000000000001', '01099998888', '1111', '[{"name":"c"}]', null, null, 150000);
select room.submit_registration('00000000-0000-0000-0000-000000000001', '01077776666', '2222', '[{"name":"d"}]', null, null, 150000);

-- 테이블·내부 함수 직접 접근은 전부 막힌다
select t.err('select * from room.registrations', 'permission denied');
select t.err($q$update room.registrations set status = 'confirmed'$q$, 'permission denied');
select t.err('select * from room.lookup_failures', 'permission denied');
select t.err('select * from room.admins', 'permission denied');
select t.err($q$select room._verify('00000000-0000-0000-0000-000000000001', '01012345678', '1234')$q$, 'permission denied');
select t.err($q$select room.reset_pin(gen_random_uuid(), '0000')$q$, 'permission denied');
select t.err($q$select room.admin_add_registration('00000000-0000-0000-0000-000000000001', '01055554444', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'permission denied');
select t.err($q$insert into room.admins values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$q$, 'permission denied');
select t.err('select * from room.room_plans', 'permission denied');
select t.err('select room.can_manage()', 'permission denied');  -- 실행 권한도 운영자에게만
select t.err($q$select room.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 0)$q$, 'permission denied');
select t.err('select * from room.admin_requests()', 'permission denied');
select t.err($q$select room.approve_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$q$, 'permission denied');

-- 조회
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000001', '010-1234-5678', '1234') ->> 'status' = 'pending',
  '휴대폰+PIN 이 맞으면 조회된다');
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') ->> 'quoted' = '415000',
  '하이픈 없이도 조회된다');
select t.ok(not (room.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') ?| array['pin_hash', 'admin_memo']),
  '조회 결과에 PIN 해시·운영자 메모가 없다');
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '0000') is null,
  'PIN 이 틀리면 null');
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000002', '01012345678', '1234') is null,
  '다른 집회로는 조회 안 된다');

-- PIN 5번 틀리면 맞는 PIN 으로도 잠긴다
select room.lookup_registration('00000000-0000-0000-0000-000000000001', '01099998888', '0000') from generate_series(1, 5);
select t.err($q$select room.lookup_registration('00000000-0000-0000-0000-000000000001', '01099998888', '1111')$q$, 'TOO_MANY_ATTEMPTS');
select t.err($q$select room.update_registration('00000000-0000-0000-0000-000000000001', '01099998888', '1111', '[{"name":"x"}]', null, null, 0)$q$, 'TOO_MANY_ATTEMPTS');

-- 수정: PIN 이 맞을 때만, 상태는 그대로
select t.ok(room.update_registration('00000000-0000-0000-0000-000000000001', '01012345678', '0000', '[{"name":"해커"}]', null, null, 0) is null,
  'PIN 이 틀리면 수정 안 된다');
select t.ok(room.update_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234',
  '[{"name":"홍길동","birthYear":1985},{"name":"홍아들","birthYear":2012},{"name":"홍딸","birthYear":2021}]', '홍길동', '막내 추가', 445000) ->> 'status' = 'pending',
  '입금대기일 때 수정된다');
select t.ok(jsonb_array_length(room.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') -> 'people') = 3,
  '수정한 인원이 저장된다');

-- 취소 → 같은 번호로 다시 신청 가능, 조회는 진행 중인 신청을 먼저
select t.ok(room.cancel_registration('00000000-0000-0000-0000-000000000001', '01077776666', '2222') ->> 'status' = 'cancelled',
  '입금대기일 때 취소된다');
select t.err($q$select room.update_registration('00000000-0000-0000-0000-000000000001', '01077776666', '2222', '[{"name":"d"}]', null, null, 0)$q$,
             'NOT_EDITABLE');
select room.submit_registration('00000000-0000-0000-0000-000000000001', '01077776666', '3333', '[{"name":"d2"}]', null, null, 150000);
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000001', '01077776666', '3333') ->> 'status' = 'pending',
  '취소 후 다시 신청하면 새 신청이 조회된다');

-- ===========================================================================
-- 로그인했지만 운영자가 아닌 사람
-- ===========================================================================
set role authenticated;
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

select t.ok(not room.is_admin(), 'b 는 운영자가 아니다');
select t.ok((select count(*) from room.registrations) = 0, '운영자가 아니면 신청이 하나도 안 보인다');
select t.err($q$insert into room.gatherings (name, start_date, end_date) values ('x', '2026-01-01', '2026-01-02')$q$, 'row-level security');
select t.err($q$select room.reset_pin(gen_random_uuid(), '0000')$q$, 'FORBIDDEN');
select t.err($q$select room.admin_add_registration('00000000-0000-0000-0000-000000000001', '01055554444', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'FORBIDDEN');
select t.err($q$insert into storage.objects (bucket_id, name) values ('gathering-images', 'x.jpg')$q$, 'row-level security');
select t.err($q$select room.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 0)$q$, 'FORBIDDEN');
select t.err($q$insert into room.room_plans (gathering_id, data) values ('00000000-0000-0000-0000-000000000001', '{}')$q$,
             'row-level security');
do $$ begin
  update room.registrations set status = 'confirmed';
  perform t.ok(not found, '운영자가 아니면 신청을 못 고친다');
end $$;
select t.ok((select count(*) from room.admin_requests()) = 0, '운영자가 아니면 가입 신청 목록이 비어 있다');
select t.err($q$select room.approve_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$q$, 'FORBIDDEN');
select t.err($q$select room.reject_admin('cccccccc-cccc-cccc-cccc-cccccccccccc')$q$, 'FORBIDDEN');

-- ===========================================================================
-- 운영자
-- ===========================================================================
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select t.ok(room.is_admin(), 'a 는 운영자다');
select t.ok((select count(*) from room.registrations) = 4, '운영자는 신청(취소 포함)이 전부 보인다');
update room.registrations set status = 'confirmed', paid = 445000, paid_at = current_date
 where phone = '01012345678';
update room.gatherings set notice = '준비물: 성경' where id = '00000000-0000-0000-0000-000000000001';
insert into storage.objects (bucket_id, name) values ('gathering-images', 'g1/poster-1.jpg');
select room.reset_pin(id, '4444') from room.registrations where phone = '01099998888';

-- 운영자 대신 접수: 닫힌 집회에도 되고, 신청자는 그 PIN 으로 조회한다
select t.ok(room.admin_add_registration('00000000-0000-0000-0000-000000000002', '010-5555-4444', '5555',
  '[{"name":"현장"}]', null, null, 150000) is not null, '운영자는 닫힌 집회에도 신청을 넣는다');
select t.err($q$select room.admin_add_registration('00000000-0000-0000-0000-000000000002', '01055554444', '1111', '[{"name":"b"}]', null, null, 0)$q$,
             'ALREADY_REGISTERED');
select t.err($q$select room.admin_add_registration('00000000-0000-0000-0000-000000000002', '0212345678', '1111', '[{"name":"b"}]', null, null, 0)$q$,
             'INVALID_PHONE');

-- 방배정: 읽은 버전으로만 저장된다 (두 기기가 동시에 고치면 늦은 쪽이 CONFLICT)
select t.ok(room.save_room_plan('00000000-0000-0000-0000-000000000001', '{"rooms":[]}', 0) = 1,
  '방배정 첫 저장 = 버전 1');
select t.err($q$select room.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 0)$q$, 'CONFLICT');
select t.ok(room.save_room_plan('00000000-0000-0000-0000-000000000001', '{"rooms":[1]}', 1) = 2,
  '읽은 버전으로 저장하면 버전이 오른다');
select t.err($q$select room.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 1)$q$, 'CONFLICT');
select t.ok((select data from room.room_plans) = '{"rooms":[1]}', '늦게 온 저장은 덮어쓰지 않는다');

-- 홈스테이: 신청마다 방 하나가 생기고, 그 방에 배정된 참석자를 신청자가 조회한다
select t.err($q$insert into room.gatherings (id, name, kind, start_date, end_date)
              values (gen_random_uuid(), 'x', '엉뚱', '2026-10-09', '2026-10-11')$q$, 'kind_check');
insert into room.gatherings (id, name, kind, start_date, end_date, open, schedule) values
  ('00000000-0000-0000-0000-000000000004', '홈스테이', 'homestay', '2026-10-09', '2026-10-11', true,
   '[{"date":"2026-10-09","time":"19:30","title":"개회예배"}]');
select room.admin_add_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234',
  '[{"name":"김호스트","extra":{"수용 인원":"3"}}]', null, null, 0);
select room.save_room_plan('00000000-0000-0000-0000-000000000004', jsonb_build_object(
  'rooms', jsonb_build_array(
    jsonb_build_object('id', 'r1', 'roomNo', '김호스트', 'capacity', 3,
      'registrationId', (select id from room.registrations where phone = '01033332222')),
    jsonb_build_object('id', 'r2', 'roomNo', '102', 'capacity', 4)),
  'attendees', jsonb_build_array(
    jsonb_build_object('name', '손님1', 'gender', 'M', 'age', 30, 'phone', '010-1111-0001',
      'roomId', 'r1', 'note', '운영자 메모'),
    jsonb_build_object('name', '손님2', 'gender', 'F', 'age', 20, 'roomId', 'r2'))), 0);

-- 가입 승인·거절
select t.ok((select array_agg(email order by email) from room.admin_requests()) = array['b@x', 'c@x'],
  '운영자는 이 앱 가입 신청만 본다 (같은 프로젝트의 다른 앱 가입자 x 는 안 보인다)');
select t.ok((select name from room.admin_requests() where email = 'b@x') = '비', '가입 때 넣은 이름이 보인다');
select room.reject_admin('cccccccc-cccc-cccc-cccc-cccccccccccc');
select t.ok(exists (select 1 from auth.users where email = 'c@x'), '거절해도 계정은 남는다 (다른 앱도 쓰는 계정일 수 있다)');
select t.ok((select array_agg(email) from room.admin_requests()) = array['b@x'], '거절하면 목록에서 빠진다');
select t.err($q$select room.reset_pin(gen_random_uuid(), '1234')$q$, 'NOT_FOUND');  -- 없는 신청은 조용히 성공하지 않는다
select t.err($q$select room.reject_admin('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$q$, 'NOT_FOUND');
select t.err($q$select room.approve_admin(gen_random_uuid())$q$, 'NOT_FOUND');
-- 승인 전 b: 로그인하면 가입자 표에 들어가지만 아직 아무것도 못 한다
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select t.ok(room.enter_app() = 'pending', '승인 전엔 대기 중');
select t.ok(not room.can_create(), '승인 전엔 집회를 못 만든다');
set request.jwt.claim.sub = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
select t.ok(room.enter_app() = 'rejected', '거절된 사람');
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
select t.ok(room.enter_app() = 'none', '다른 앱 가입자는 이 앱 계정이 아니다');
select t.err('select * from room.members', 'permission denied');
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select t.ok((select array_agg(email) from room.admin_requests()) = array['b@x'], '로그인해도 대기 목록 그대로');
select room.approve_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select t.ok((select count(*) from room.admin_requests()) = 0, '승인하면 목록에서 빠진다');
reset role;
select t.ok((select email_confirmed_at from auth.users where email = 'b@x') is not null,
  '승인하면 메일 확인도 끝난다 (확인 메일을 못 받아도 로그인된다)');
select t.ok((select email_confirmed_at from auth.users where email = 'c@x') is null, '거절한 사람은 그대로');
select t.ok((select array_agg(user_id::text || ':' || status order by status) from room.members)
              = array['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:owner', 'cccccccc-cccc-cccc-cccc-cccccccccccc:rejected'],
  '가입자 표: b 승인, c 거절, x 는 없다');
set role authenticated;

-- 승인된 b: 전체 운영자는 아니고, 집회를 하나만 만들어 그 집회를 관리한다
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select t.ok(not room.is_admin(), '승인돼도 전체 운영자는 아니다');
select t.ok(room.enter_app() = 'ok', '승인되면 관리자 앱에 들어온다');
select t.ok(room.can_create(), '아직 만든 집회가 없으니 만들 수 있다');
select t.err($q$insert into room.gatherings (name, start_date, end_date, created_by) values ('남 이름', '2026-01-01', '2026-01-02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$q$,
             'row-level security');
insert into room.gatherings (id, name, start_date, end_date)
values ('00000000-0000-0000-0000-0000000000b1', '비 집회', '2026-01-01', '2026-01-02');
select t.ok((select created_by from room.gatherings where id = '00000000-0000-0000-0000-0000000000b1')
              = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '만든 사람이 기록된다');
select t.ok(room.manages('00000000-0000-0000-0000-0000000000b1'), '만든 집회를 관리한다');
select t.ok(not room.manages('00000000-0000-0000-0000-000000000001'), '남의 집회는 관리하지 않는다');
select t.ok((select array_agg(x) from room.my_gatherings() x) = array['00000000-0000-0000-0000-0000000000b1'::uuid],
  '내 집회 목록에 만든 집회가 있다');
select t.ok(not room.can_create(), '하나 만들면 더 못 만든다');
select t.err($q$insert into room.gatherings (name, start_date, end_date) values ('둘째', '2026-01-01', '2026-01-02')$q$,
             'row-level security');
update room.gatherings set created_by = null, place = '여기' where id = '00000000-0000-0000-0000-0000000000b1';
select t.ok((select created_by from room.gatherings where id = '00000000-0000-0000-0000-0000000000b1')
              = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '만든 사람은 고쳐도 안 바뀐다');
select room.save_room_plan('00000000-0000-0000-0000-0000000000b1', '{"rooms":[]}', 0);
do $$ begin
  delete from room.gatherings where id = '00000000-0000-0000-0000-000000000001';
  perform t.ok(not found, '집회관리자는 남의 집회를 못 지운다');
end $$;
select t.ok((select count(*) from room.admin_requests()) = 0, '승인된 사람도 가입 신청은 못 본다');
select t.err($q$select room.approve_admin('cccccccc-cccc-cccc-cccc-cccccccccccc')$q$, 'FORBIDDEN');

-- 초대 링크: 집회를 관리하는 사람이 코드를 만들고, 그 링크로 가입하면 그 집회만 관리한다
select t.err($q$select room.gathering_invite('00000000-0000-0000-0000-000000000001', false)$q$, 'FORBIDDEN');
select set_config('t.code', room.gathering_invite('00000000-0000-0000-0000-0000000000b1', false), false);
select t.ok(room.gathering_invite('00000000-0000-0000-0000-0000000000b1', false) = current_setting('t.code'),
  '다시 물어도 같은 코드');
select room.join_app(current_setting('t.code'));
select t.ok((select count(*) from room.gathering_admin_list('00000000-0000-0000-0000-0000000000b1')) = 0,
  '주인이 자기 초대 링크를 열어도 승인 대기에 들어가지 않는다');
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'f@x',
   jsonb_build_object('room_signup', 'true', 'room_invite', current_setting('t.code')));
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select t.ok((select count(*) from room.admin_requests()) = 0, '초대 링크 가입자는 승인 목록에 안 나온다');
set request.jwt.claim.sub = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
select t.ok(room.enter_app() = 'waiting', '초대 링크로 가입하면 집회관리자 승인을 기다린다');
select t.ok(not room.can_manage(), '승인 전에는 관리자 앱에 못 들어온다');
select t.ok(not room.manages('00000000-0000-0000-0000-0000000000b1'), '승인 전에는 그 집회를 못 다룬다');
select t.ok((select count(*) from room.my_gatherings()) = 0, '승인 전에는 맡은 집회 목록도 비어 있다');
-- 다른 앱 계정 x 가 초대 링크로 로그인하면 이 앱 가입 + 그 집회 승인 대기
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
select t.err($q$select room.join_app('틀린코드')$q$, 'BAD_INVITE');
select t.ok(room.enter_app() = 'none', '틀린 코드로는 가입되지 않는다');
select room.join_app(current_setting('t.code'));
select t.ok(room.enter_app() = 'waiting', '맞는 코드면 가입되고 승인을 기다린다');

-- 집회관리자 b 가 승인한다 → 운영스탭으로 시작
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select t.ok((select count(*) from room.gathering_admin_list('00000000-0000-0000-0000-0000000000b1') where not approved) = 2,
  '집회관리자는 승인 대기 목록을 본다');
select room.approve_gathering_admin('00000000-0000-0000-0000-0000000000b1', 'ffffffff-ffff-ffff-ffff-ffffffffffff');
select t.err($q$select room.approve_gathering_admin('00000000-0000-0000-0000-0000000000b1', 'ffffffff-ffff-ffff-ffff-ffffffffffff')$q$, 'NO_SUCH_ADMIN');
set request.jwt.claim.sub = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
select t.ok(room.enter_app() = 'ok', '승인되면 관리자 앱에 들어온다');
select t.ok(room.manages('00000000-0000-0000-0000-0000000000b1'), '승인되면 그 집회를 다룬다');
select t.ok(not room.can_create(), '초대받은 사람은 집회를 못 만든다');
select t.ok(not room.configures('00000000-0000-0000-0000-0000000000b1'), '승인되면 운영스탭으로 시작한다 (설정은 못 고친다)');
select t.err($q$select room.gathering_invite('00000000-0000-0000-0000-0000000000b1', false)$q$, 'FORBIDDEN');

-- 보조운영자로 올리면 설정은 고치지만, 승인·역할·해제·삭제는 집회관리자만
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select t.err($q$select room.set_gathering_admin_role('00000000-0000-0000-0000-0000000000b1', '99999999-9999-9999-9999-999999999999', 'assistant')$q$, 'NO_SUCH_ADMIN');
select room.set_gathering_admin_role('00000000-0000-0000-0000-0000000000b1', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'assistant');
set request.jwt.claim.sub = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
select t.ok(room.configures('00000000-0000-0000-0000-0000000000b1'), '보조운영자는 설정을 고친다');
do $$ begin
  update room.gatherings set place = '보조' where id = '00000000-0000-0000-0000-0000000000b1';
  perform t.ok(found, '보조운영자는 집회 설정을 고친다 (RLS)');
  delete from room.gatherings where id = '00000000-0000-0000-0000-0000000000b1';
  perform t.ok(not found, '보조운영자는 집회를 못 지운다');
end $$;
select t.err($q$select room.gathering_invite('00000000-0000-0000-0000-0000000000b1', true)$q$, 'FORBIDDEN');  -- 초대 링크는 주인만
select t.err($q$select room.approve_gathering_admin('00000000-0000-0000-0000-0000000000b1', '99999999-9999-9999-9999-999999999999')$q$, 'FORBIDDEN');
select t.err($q$select room.set_gathering_admin_role('00000000-0000-0000-0000-0000000000b1', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'staff')$q$, 'FORBIDDEN');
select t.err($q$select room.remove_gathering_admin('00000000-0000-0000-0000-0000000000b1', '99999999-9999-9999-9999-999999999999')$q$, 'FORBIDDEN');
select t.err($q$select room.add_gathering_admin('00000000-0000-0000-0000-0000000000b1', 'd@x')$q$, 'FORBIDDEN');
select t.ok(not room.can_create(), '보조운영자도 집회는 못 만든다');

-- 새 코드로 바꾸면 예전 링크는 막힌다. 거절·해제하면 다시 못 들어온다
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select set_config('t.code2', room.gathering_invite('00000000-0000-0000-0000-0000000000b1', true), false);
select t.ok(current_setting('t.code2') <> current_setting('t.code'), '새 코드로 바꾼다');
set role anon;
select t.ok(room.invite_ok(current_setting('t.code2')) and not room.invite_ok(current_setting('t.code')),
  '가입 전(로그인 안 함)에도 코드가 맞는지 본다');
set role authenticated;
select t.ok((select count(*) from room.gathering_admin_list('00000000-0000-0000-0000-0000000000b1')) = 2,
  '만든 사람이 초대한 운영자 목록을 본다');
select room.remove_gathering_admin('00000000-0000-0000-0000-0000000000b1', '99999999-9999-9999-9999-999999999999');  -- 승인 대기 거절
select room.remove_gathering_admin('00000000-0000-0000-0000-0000000000b1', 'ffffffff-ffff-ffff-ffff-ffffffffffff');
select t.ok(room.gathering_invite('00000000-0000-0000-0000-0000000000b1', false) <> current_setting('t.code2'),
  '해제·거절하면 초대 링크가 바뀐다 (같은 링크로 다시 대기에 오르지 않게)');
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
select t.ok(room.enter_app() = 'helper', '거절된 사람은 들어오지 못한다');
set request.jwt.claim.sub = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
select t.err($q$select room.join_app(current_setting('t.code2'))$q$, 'BAD_INVITE');
select t.ok(room.enter_app() = 'helper', '해제된 사람은 다음 로그인에 가입 때 코드로 되살아나지 않는다');

-- 옛 링크로 가입한 사람: 집회관리자 신청 목록(수퍼어드민)에 엉뚱하게 오르지 않는다
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('77777777-7777-7777-7777-777777777777', 'old@x', '{"room_signup":"true","room_invite":"옛코드"}');
set role authenticated;
set request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
select t.ok(room.enter_app() = 'none', '옛 코드로 가입한 사람은 가입자 표에 안 들어간다');
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select t.ok((select count(*) from room.admin_requests() where email = 'old@x') = 0, '수퍼어드민 신청 목록에도 없다');

-- 승인했던 집회관리자를 나중에 거절하면, 남은 세션으로도 자기 집회를 못 다룬다
select room.reject_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select t.ok(room.enter_app() = 'rejected', '거절되면 로그인이 막힌다');
select t.ok(not room.owns('00000000-0000-0000-0000-0000000000b1')
            and not room.manages('00000000-0000-0000-0000-0000000000b1'), '만든 집회도 못 다룬다');
select t.ok((select count(*) from room.my_gatherings()) = 0, '맡은 집회 목록도 비어 있다');
select t.ok((select count(*) from room.registrations) = 0, '신청(전화번호)도 안 보인다');
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select room.approve_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');  -- 아래 검사들을 위해 되돌린다

-- 집회관리자는 자기 집회를 지운다. 지우면 다시 하나를 만들 수 있다(한 번에 하나)
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
do $$ begin
  delete from room.gatherings where id = '00000000-0000-0000-0000-0000000000b1';
  perform t.ok(found, '집회관리자는 자기 집회를 지운다');
end $$;
select t.ok(room.can_create(), '지우고 나면 다시 하나를 만들 수 있다');
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 집회별 운영자: 맡은 집회만, 새 집회는 못 만든다
-- ===========================================================================
-- d 는 이 앱에 가입만 한 계정 (전체 운영자 승인 없음). 1번 집회의 운영자로만 등록한다.
-- y 는 같은 프로젝트의 다른 앱 가입자 — 이메일로도 못 찾아야 한다.
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'd@x', '{"room_signup":"true"}'),
  ('88888888-8888-8888-8888-888888888888', 'y@x', null);
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select t.err($q$select room.add_gathering_admin('00000000-0000-0000-0000-000000000001', 'none@x')$q$,
             'NO_ACCOUNT');
select t.err($q$select room.add_gathering_admin('00000000-0000-0000-0000-000000000001', 'y@x')$q$,
             'NO_ACCOUNT');
select t.ok(room.add_gathering_admin('00000000-0000-0000-0000-000000000001', ' D@X ')
              = 'dddddddd-dddd-dddd-dddd-dddddddddddd',
  '이메일로 찾아 집회 운영자로 등록한다 (공백·대소문자 무시)');
select t.ok((select approved from room.gathering_admin_list('00000000-0000-0000-0000-000000000001')),
  '이메일로 직접 등록하면 승인도 끝난 것이다');
-- 같은 주소로 계정이 둘이면(확인 안 된 가입 등) 확인된 쪽을 고른다 — 아무거나 뽑으면 엉뚱한 사람에게 권한이 간다
reset role;
update auth.users set email_confirmed_at = now() where email = 'd@x';
insert into auth.users (id, email, raw_user_meta_data, created_at) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'd@x', '{"room_signup":"true"}', now() - interval '1 day');
set role authenticated;
select t.ok(room.add_gathering_admin('00000000-0000-0000-0000-000000000002', 'd@x')
              = 'dddddddd-dddd-dddd-dddd-dddddddddddd',
  '같은 이메일이 여럿이면 확인된 계정을 고른다');
select room.remove_gathering_admin('00000000-0000-0000-0000-000000000002',
  'dddddddd-dddd-dddd-dddd-dddddddddddd');
select room.add_gathering_admin('00000000-0000-0000-0000-000000000001', 'd@x');  -- 두 번 넣어도 된다
select t.ok((select role from room.gathering_admin_list('00000000-0000-0000-0000-000000000001')) = 'staff',
  '집회 운영자 목록이 보이고, 이메일로 등록한 사람은 운영스탭이다');

-- 운영스탭 d: 신청·방배정은 다루지만 집회 설정·운영자·이미지는 못 고친다
set request.jwt.claim.sub = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
select t.ok(room.manages('00000000-0000-0000-0000-000000000001'), '운영스탭도 맡은 집회를 다룬다');
select t.ok(not room.configures('00000000-0000-0000-0000-000000000001'), '운영스탭은 설정을 못 고친다');
select t.ok((select count(*) from room.my_configured()) = 0, '운영스탭에게 설정할 집회 목록은 비어 있다');
do $$ begin
  update room.gatherings set place = '스탭' where id = '00000000-0000-0000-0000-000000000001';
  perform t.ok(not found, '운영스탭은 집회 설정을 못 고친다 (RLS)');
end $$;
select t.err($q$select room.gathering_invite('00000000-0000-0000-0000-000000000001', false)$q$, 'FORBIDDEN');
select t.err($q$select room.add_gathering_admin('00000000-0000-0000-0000-000000000001', 'f@x')$q$, 'FORBIDDEN');
select t.err($q$select room.set_gathering_admin_role('00000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'assistant')$q$,
             'FORBIDDEN');
select t.err($q$insert into storage.objects (bucket_id, name) values ('gathering-images', '00000000-0000-0000-0000-000000000001/s.jpg')$q$,
             'row-level security');

-- 보조운영자로 올리면 설정까지 고친다 (수퍼어드민도 역할을 바꾼다)
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select t.err($q$select room.set_gathering_admin_role('00000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'owner')$q$,
             'INVALID_ROLE');
select t.err($q$select room.set_gathering_admin_role('00000000-0000-0000-0000-000000000001', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'staff')$q$,
             'NO_SUCH_ADMIN');
select room.set_gathering_admin_role('00000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'assistant');

set request.jwt.claim.sub = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
select t.ok(not room.is_admin(), 'd 는 전체 운영자가 아니다');
select t.ok(room.can_manage(), 'd 는 관리자 앱에 들어올 수 있다');
select t.ok((select array_agg(x) from room.my_gatherings() x)
              = array['00000000-0000-0000-0000-000000000001'::uuid],
  '내가 맡은 집회만 돌려준다');
select t.ok((select array_agg(x) from room.my_configured() x)
              = array['00000000-0000-0000-0000-000000000001'::uuid],
  '보조운영자가 되면 설정할 집회 목록에 들어온다');

-- 맡은 집회: 신청·방배정이 보이고 고칠 수 있다
select t.ok((select count(*) from room.registrations
              where gathering_id = '00000000-0000-0000-0000-000000000001') > 0,
  '맡은 집회의 신청이 보인다');
select t.ok((select count(*) from room.registrations
              where gathering_id = '00000000-0000-0000-0000-000000000002') = 0,
  '안 맡은 집회의 신청은 안 보인다');
select t.ok(room.save_room_plan('00000000-0000-0000-0000-000000000001',
              '{"rooms":[2]}', (select version from room.room_plans
                                 where gathering_id = '00000000-0000-0000-0000-000000000001')) > 0,
  '맡은 집회의 방배정을 저장한다');
select t.err($q$select room.save_room_plan('00000000-0000-0000-0000-000000000004', '{}', 0)$q$,
             'FORBIDDEN');
select t.err($q$select room.admin_add_registration('00000000-0000-0000-0000-000000000004', '01012340000', '1234', '[{"name":"x"}]', null, null, 0)$q$,
             'FORBIDDEN');
do $$ begin
  update room.gatherings set place = '여기' where id = '00000000-0000-0000-0000-000000000001';
  perform t.ok(found, '맡은 집회 설정은 고친다');
  update room.gatherings set place = '저기' where id = '00000000-0000-0000-0000-000000000002';
  perform t.ok(not found, '안 맡은 집회 설정은 못 고친다');
  delete from room.gatherings where id = '00000000-0000-0000-0000-000000000001';
  perform t.ok(not found, '보조운영자는 집회를 못 지운다');
end $$;
select t.err($q$insert into room.gatherings (name, start_date, end_date) values ('새', '2026-01-01', '2026-01-02')$q$,
             'row-level security');
-- 계정 승인은 전체 운영자만
select t.ok((select count(*) from room.admin_requests()) = 0, '집회 운영자는 가입 신청을 못 본다');
select t.err($q$select room.approve_admin('dddddddd-dddd-dddd-dddd-dddddddddddd')$q$, 'FORBIDDEN');
-- 이미지도 맡은 집회 폴더만
select t.err($q$insert into storage.objects (bucket_id, name) values ('gathering-images', '00000000-0000-0000-0000-000000000004/p.jpg')$q$,
             'row-level security');
insert into storage.objects (bucket_id, name)
values ('gathering-images', '00000000-0000-0000-0000-000000000001/p.jpg');
select t.ok((select count(*) from storage.objects
              where name = '00000000-0000-0000-0000-000000000001/p.jpg') = 1,
  '맡은 집회 폴더에는 이미지를 올린다');

set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select room.remove_gathering_admin('00000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd');
select t.err($q$select room.remove_gathering_admin('00000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd')$q$,
             'NO_SUCH_ADMIN');
set request.jwt.claim.sub = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
select t.ok(not room.can_manage(), '빼고 나면 관리자 앱에 못 들어온다');
select t.ok((select count(*) from room.registrations) = 0, '빼고 나면 신청도 안 보인다');
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 다시 신청자: 확정 후엔 못 고치고, 운영자가 PIN 을 바꾸면 잠금이 풀린다
-- ===========================================================================
set role anon;
set request.jwt.claim.sub = '';

select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') ->> 'status' = 'confirmed',
  '확정된 상태가 조회된다');
select t.err($q$select room.update_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234', '[{"name":"x"}]', null, null, 0)$q$,
             'NOT_EDITABLE');
select t.err($q$select room.cancel_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234')$q$,
             'NOT_EDITABLE');
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000001', '01099998888', '4444') is not null,
  'PIN 재설정 후 새 PIN 으로 조회되고 잠금도 풀린다');
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000002', '01055554444', '5555') ->> 'status' = 'pending',
  '운영자가 넣은 신청도 휴대폰+PIN 으로 조회된다');
select t.err($q$insert into storage.objects (bucket_id, name) values ('gathering-images', 'y.jpg')$q$, 'row-level security');

-- 홈스테이 신청자: 우리 집에 배정된 사람만, 운영자 메모는 빼고 보인다
select t.ok((select schedule -> 0 ->> 'title' from room.gatherings
              where id = '00000000-0000-0000-0000-000000000004') = '개회예배',
  '일정표는 누구나 읽는다');
select t.ok(jsonb_array_length(
    room.lookup_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234') -> 'assigned') = 1,
  '다른 방(102)에 배정된 사람은 안 보인다');
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234')
              -> 'assigned' -> 0 ->> 'phone' = '010-1111-0001', '배정된 참석자의 연락처가 보인다');
select t.ok(not (room.lookup_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234')
              -> 'assigned' -> 0 ? 'note'), '운영자 메모는 신청자에게 안 준다');
select t.ok(room.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234')
              ->> 'assigned' = '[]', '일반 집회는 배정 목록이 비어 있다');
select t.err($q$select room._assigned('00000000-0000-0000-0000-000000000004', gen_random_uuid())$q$,
             'permission denied');

-- 마감되면 수정은 막히고 취소는 된다
reset role;
update room.gatherings set open = false where id = '00000000-0000-0000-0000-000000000001';
set role anon;
select t.err($q$select room.update_registration('00000000-0000-0000-0000-000000000001', '01099998888', '4444', '[{"name":"c"}]', null, null, 0)$q$,
             'CLOSED');
select t.ok(room.cancel_registration('00000000-0000-0000-0000-000000000001', '01099998888', '4444') ->> 'status' = 'cancelled',
  '마감 후에도 입금대기면 취소된다');

-- ===========================================================================
-- 스탭 페이지: 내 담당구역만 보이고, 그 구역의 할 일만 고칠 수 있다
-- ===========================================================================
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select room.admin_add_registration('00000000-0000-0000-0000-000000000001', '01088881111', '1234',
  '[{"id":"p-staff","name":"김스탭","staff":true}]', null, null, 0);
select room.admin_add_registration('00000000-0000-0000-0000-000000000001', '01088882222', '1234',
  '[{"id":"p-other","name":"박참석"}]', null, null, 0);
-- 운영자가 담당구역을 만들고 사람을 배정한 상태 (신청서의 사람 id = 참석자 personId)
select room.save_room_plan('00000000-0000-0000-0000-000000000001', jsonb_build_object(
  'attendees', jsonb_build_array(
    jsonb_build_object('id', 'p-staff', 'name', '김스탭'),
    jsonb_build_object('id', 'p-other', 'name', '박참석')),
  'duties', jsonb_build_array(
    jsonb_build_object('id', 'd1', 'name', '주방', 'tasks', '배식',
      'personIds', jsonb_build_array('p-staff')),
    jsonb_build_object('id', 'd2', 'name', '차량',
      'personIds', jsonb_build_array('p-other')))),
  (select version from room.room_plans where gathering_id = '00000000-0000-0000-0000-000000000001'));

set role anon;
set request.jwt.claim.sub = '';

-- 마감된 집회여도 스탭은 들어온다 (집회 기간에 쓰는 화면이라 _assert_open 을 보지 않는다)
select t.ok(jsonb_array_length(room.lookup_duties('00000000-0000-0000-0000-000000000001', '01088881111', '1234') -> 'duties') = 1,
  '내 담당구역만 보인다');
select t.ok(room.lookup_duties('00000000-0000-0000-0000-000000000001', '01088881111', '1234') -> 'duties' -> 0 ->> 'name' = '주방',
  '배정된 구역 이름이 보인다');
select t.ok(room.lookup_duties('00000000-0000-0000-0000-000000000001', '01088881111', '1234') -> 'duties' -> 0 -> 'members' ? '김스탭',
  '같이 맡은 사람 이름이 보인다');
select t.ok(room.lookup_duties('00000000-0000-0000-0000-000000000001', '01088881111', '0000') is null, 'PIN 이 틀리면 null');
select t.ok(jsonb_array_length(room.lookup_duties('00000000-0000-0000-0000-000000000001', '01012345678', '1234') -> 'duties') = 0,
  '담당구역이 없으면 빈 목록');

select room.save_duty_items('00000000-0000-0000-0000-000000000001', '01088881111', '1234', 'd1',
  '[{"id":"t1","kind":"준비물","content":"국자","qty":"2","done":true}]');
select t.ok(room.lookup_duties('00000000-0000-0000-0000-000000000001', '01088881111', '1234')
              -> 'duties' -> 0 -> 'items' -> 0 ->> 'content' = '국자', '적은 할 일이 저장된다');
select t.err($q$select room.save_duty_items('00000000-0000-0000-0000-000000000001', '01088881111', '1234', 'd2', '[]')$q$,
             'FORBIDDEN');  -- 남의 구역
select t.err($q$select room.save_duty_items('00000000-0000-0000-0000-000000000001', '01088881111', '1234', 'd1', '{"a":1}')$q$,
             'INVALID_ITEMS');
select t.ok(room.save_duty_items('00000000-0000-0000-0000-000000000001', '01088881111', '0000', 'd1', '[]') is null,
  'PIN 이 틀리면 저장하지 않는다');
select t.err($q$select room._my_duties('00000000-0000-0000-0000-000000000001', '[]')$q$, 'permission denied');

-- 문서의 나머지는 그대로인지 본다 (신청자는 room_plans 를 직접 못 읽으므로 역할을 푼다)
reset role;
select t.ok((select data -> 'duties' -> 1 ->> 'name' from room.room_plans where gathering_id = '00000000-0000-0000-0000-000000000001') = '차량',
  '다른 구역·방배정은 스탭이 건드리지 못한다');
select t.ok((select data -> 'attendees' -> 0 ->> 'name' from room.room_plans where gathering_id = '00000000-0000-0000-0000-000000000001') = '김스탭',
  '참석자 목록도 그대로다');
\o
\echo ALL OK
