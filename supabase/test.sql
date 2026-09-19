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
  raw_user_meta_data jsonb, created_at timestamptz default now()
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

-- Supabase 기본값: public 스키마의 새 테이블·함수는 anon/authenticated 에게 전부 열린다.
-- 가장 느슨한 기본값에서도 schema.sql 이 막아내는지 본다.
grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on functions to anon, authenticated;

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
-- 데이터: 운영자 a, 가입 신청만 한 b·c, 집회 3개(열림 / 닫힘 / 마감 지남)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@x', null),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@x', '{"name":"비"}'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@x', null);
insert into public.admins values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into public.gatherings (id, name, start_date, end_date, open, deadline) values
  ('00000000-0000-0000-0000-000000000001', '열린 집회', '2026-10-09', '2026-10-11', true, null),
  ('00000000-0000-0000-0000-000000000002', '닫힌 집회', '2026-10-09', '2026-10-11', false, null),
  ('00000000-0000-0000-0000-000000000003', '마감 지난 집회', '2026-10-09', '2026-10-11', true, '2020-01-01');

-- ===========================================================================
-- 신청자 (로그인 안 함)
-- ===========================================================================
set role anon;
set request.jwt.claim.sub = '';

select t.ok((select count(*) from public.gatherings) = 3, '누구나 집회를 읽는다');
select t.err($q$insert into public.gatherings (name, start_date, end_date) values ('x', '2026-01-01', '2026-01-02')$q$,
             'permission denied');
select t.err($q$update public.gatherings set open = true$q$, 'permission denied');

-- 신청: 막혀야 하는 것
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000002', '01011112222', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'CLOSED');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000003', '01011112222', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'CLOSED');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-00000000dead', '01011112222', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'CLOSED');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '02-123-4567', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'INVALID_PHONE');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '12a4', '[{"name":"a"}]', null, null, 0)$q$, 'INVALID_PIN');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '12345', '[{"name":"a"}]', null, null, 0)$q$, 'INVALID_PIN');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '[]', null, null, 0)$q$, 'INVALID_PEOPLE');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '{"name":"a"}', null, null, 0)$q$, 'INVALID_PEOPLE');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', (select jsonb_agg(jsonb_build_object('name', i)) from generate_series(1, 21) i), null, null, 0)$q$, 'INVALID_PEOPLE');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '[{"name":"a"}]', repeat('가', 51), null, 0)$q$, 'INVALID_TEXT');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01011112222', '1234', '[{"name":"a"}]', null, null, -1)$q$, 'INVALID_QUOTED');

-- 신청: 성공 (하이픈이 있어도 숫자만 저장)
select t.ok(public.submit_registration('00000000-0000-0000-0000-000000000001', '010-1234-5678', '1234',
  '[{"name":"홍길동","birthYear":1985},{"name":"홍아들","birthYear":2012}]', '홍길동', null, 415000) is not null,
  '신청이 된다');
select t.err($q$select public.submit_registration('00000000-0000-0000-0000-000000000001', '01012345678', '9999', '[{"name":"b"}]', null, null, 0)$q$,
             'ALREADY_REGISTERED');
select public.submit_registration('00000000-0000-0000-0000-000000000001', '01099998888', '1111', '[{"name":"c"}]', null, null, 150000);
select public.submit_registration('00000000-0000-0000-0000-000000000001', '01077776666', '2222', '[{"name":"d"}]', null, null, 150000);

-- 테이블·내부 함수 직접 접근은 전부 막힌다
select t.err('select * from public.registrations', 'permission denied');
select t.err($q$update public.registrations set status = 'confirmed'$q$, 'permission denied');
select t.err('select * from public.lookup_failures', 'permission denied');
select t.err('select * from public.admins', 'permission denied');
select t.err($q$select public._verify('00000000-0000-0000-0000-000000000001', '01012345678', '1234')$q$, 'permission denied');
select t.err($q$select public.reset_pin(gen_random_uuid(), '0000')$q$, 'permission denied');
select t.err($q$select public.admin_add_registration('00000000-0000-0000-0000-000000000001', '01055554444', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'permission denied');
select t.err($q$insert into public.admins values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$q$, 'permission denied');
select t.err('select * from public.room_plans', 'permission denied');
select t.err($q$select public.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 0)$q$, 'permission denied');
select t.err('select * from public.admin_requests()', 'permission denied');
select t.err($q$select public.approve_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$q$, 'permission denied');

-- 조회
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000001', '010-1234-5678', '1234') ->> 'status' = 'pending',
  '휴대폰+PIN 이 맞으면 조회된다');
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') ->> 'quoted' = '415000',
  '하이픈 없이도 조회된다');
select t.ok(not (public.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') ?| array['pin_hash', 'admin_memo']),
  '조회 결과에 PIN 해시·운영자 메모가 없다');
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '0000') is null,
  'PIN 이 틀리면 null');
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000002', '01012345678', '1234') is null,
  '다른 집회로는 조회 안 된다');

-- PIN 5번 틀리면 맞는 PIN 으로도 잠긴다
select public.lookup_registration('00000000-0000-0000-0000-000000000001', '01099998888', '0000') from generate_series(1, 5);
select t.err($q$select public.lookup_registration('00000000-0000-0000-0000-000000000001', '01099998888', '1111')$q$, 'TOO_MANY_ATTEMPTS');
select t.err($q$select public.update_registration('00000000-0000-0000-0000-000000000001', '01099998888', '1111', '[{"name":"x"}]', null, null, 0)$q$, 'TOO_MANY_ATTEMPTS');

-- 수정: PIN 이 맞을 때만, 상태는 그대로
select t.ok(public.update_registration('00000000-0000-0000-0000-000000000001', '01012345678', '0000', '[{"name":"해커"}]', null, null, 0) is null,
  'PIN 이 틀리면 수정 안 된다');
select t.ok(public.update_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234',
  '[{"name":"홍길동","birthYear":1985},{"name":"홍아들","birthYear":2012},{"name":"홍딸","birthYear":2021}]', '홍길동', '막내 추가', 445000) ->> 'status' = 'pending',
  '입금대기일 때 수정된다');
select t.ok(jsonb_array_length(public.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') -> 'people') = 3,
  '수정한 인원이 저장된다');

-- 취소 → 같은 번호로 다시 신청 가능, 조회는 진행 중인 신청을 먼저
select t.ok(public.cancel_registration('00000000-0000-0000-0000-000000000001', '01077776666', '2222') ->> 'status' = 'cancelled',
  '입금대기일 때 취소된다');
select t.err($q$select public.update_registration('00000000-0000-0000-0000-000000000001', '01077776666', '2222', '[{"name":"d"}]', null, null, 0)$q$,
             'NOT_EDITABLE');
select public.submit_registration('00000000-0000-0000-0000-000000000001', '01077776666', '3333', '[{"name":"d2"}]', null, null, 150000);
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000001', '01077776666', '3333') ->> 'status' = 'pending',
  '취소 후 다시 신청하면 새 신청이 조회된다');

-- ===========================================================================
-- 로그인했지만 운영자가 아닌 사람
-- ===========================================================================
set role authenticated;
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

select t.ok(not public.is_admin(), 'b 는 운영자가 아니다');
select t.ok((select count(*) from public.registrations) = 0, '운영자가 아니면 신청이 하나도 안 보인다');
select t.err($q$insert into public.gatherings (name, start_date, end_date) values ('x', '2026-01-01', '2026-01-02')$q$, 'row-level security');
select t.err($q$select public.reset_pin(gen_random_uuid(), '0000')$q$, 'FORBIDDEN');
select t.err($q$select public.admin_add_registration('00000000-0000-0000-0000-000000000001', '01055554444', '1234', '[{"name":"a"}]', null, null, 0)$q$, 'FORBIDDEN');
select t.err($q$insert into storage.objects (bucket_id, name) values ('gathering-images', 'x.jpg')$q$, 'row-level security');
select t.err($q$select public.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 0)$q$, 'FORBIDDEN');
select t.err($q$insert into public.room_plans (gathering_id, data) values ('00000000-0000-0000-0000-000000000001', '{}')$q$,
             'row-level security');
do $$ begin
  update public.registrations set status = 'confirmed';
  perform t.ok(not found, '운영자가 아니면 신청을 못 고친다');
end $$;
select t.ok((select count(*) from public.admin_requests()) = 0, '운영자가 아니면 가입 신청 목록이 비어 있다');
select t.err($q$select public.approve_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$q$, 'FORBIDDEN');
select t.err($q$select public.reject_admin('cccccccc-cccc-cccc-cccc-cccccccccccc')$q$, 'FORBIDDEN');

-- ===========================================================================
-- 운영자
-- ===========================================================================
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select t.ok(public.is_admin(), 'a 는 운영자다');
select t.ok((select count(*) from public.registrations) = 4, '운영자는 신청(취소 포함)이 전부 보인다');
update public.registrations set status = 'confirmed', paid = 445000, paid_at = current_date
 where phone = '01012345678';
update public.gatherings set notice = '준비물: 성경' where id = '00000000-0000-0000-0000-000000000001';
insert into storage.objects (bucket_id, name) values ('gathering-images', 'g1/poster-1.jpg');
select public.reset_pin(id, '4444') from public.registrations where phone = '01099998888';

-- 운영자 대신 접수: 닫힌 집회에도 되고, 신청자는 그 PIN 으로 조회한다
select t.ok(public.admin_add_registration('00000000-0000-0000-0000-000000000002', '010-5555-4444', '5555',
  '[{"name":"현장"}]', null, null, 150000) is not null, '운영자는 닫힌 집회에도 신청을 넣는다');
select t.err($q$select public.admin_add_registration('00000000-0000-0000-0000-000000000002', '01055554444', '1111', '[{"name":"b"}]', null, null, 0)$q$,
             'ALREADY_REGISTERED');
select t.err($q$select public.admin_add_registration('00000000-0000-0000-0000-000000000002', '0212345678', '1111', '[{"name":"b"}]', null, null, 0)$q$,
             'INVALID_PHONE');

-- 방배정: 읽은 버전으로만 저장된다 (두 기기가 동시에 고치면 늦은 쪽이 CONFLICT)
select t.ok(public.save_room_plan('00000000-0000-0000-0000-000000000001', '{"rooms":[]}', 0) = 1,
  '방배정 첫 저장 = 버전 1');
select t.err($q$select public.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 0)$q$, 'CONFLICT');
select t.ok(public.save_room_plan('00000000-0000-0000-0000-000000000001', '{"rooms":[1]}', 1) = 2,
  '읽은 버전으로 저장하면 버전이 오른다');
select t.err($q$select public.save_room_plan('00000000-0000-0000-0000-000000000001', '{}', 1)$q$, 'CONFLICT');
select t.ok((select data from public.room_plans) = '{"rooms":[1]}', '늦게 온 저장은 덮어쓰지 않는다');

-- 홈스테이: 신청마다 방 하나가 생기고, 그 방에 배정된 참석자를 신청자가 조회한다
select t.err($q$insert into public.gatherings (id, name, kind, start_date, end_date)
              values (gen_random_uuid(), 'x', '엉뚱', '2026-10-09', '2026-10-11')$q$, 'kind_check');
insert into public.gatherings (id, name, kind, start_date, end_date, open, schedule) values
  ('00000000-0000-0000-0000-000000000004', '홈스테이', 'homestay', '2026-10-09', '2026-10-11', true,
   '[{"date":"2026-10-09","time":"19:30","title":"개회예배"}]');
select public.admin_add_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234',
  '[{"name":"김호스트","extra":{"수용 인원":"3"}}]', null, null, 0);
select public.save_room_plan('00000000-0000-0000-0000-000000000004', jsonb_build_object(
  'rooms', jsonb_build_array(
    jsonb_build_object('id', 'r1', 'roomNo', '김호스트', 'capacity', 3,
      'registrationId', (select id from public.registrations where phone = '01033332222')),
    jsonb_build_object('id', 'r2', 'roomNo', '102', 'capacity', 4)),
  'attendees', jsonb_build_array(
    jsonb_build_object('name', '손님1', 'gender', 'M', 'age', 30, 'phone', '010-1111-0001',
      'roomId', 'r1', 'note', '운영자 메모'),
    jsonb_build_object('name', '손님2', 'gender', 'F', 'age', 20, 'roomId', 'r2'))), 0);

-- 가입 승인·거절
select t.ok((select array_agg(email order by email) from public.admin_requests()) = array['b@x', 'c@x'],
  '운영자는 가입 신청(운영자 아닌 계정)만 본다');
select t.ok((select name from public.admin_requests() where email = 'b@x') = '비', '가입 때 넣은 이름이 보인다');
select public.reject_admin('cccccccc-cccc-cccc-cccc-cccccccccccc');
select t.ok(not exists (select 1 from auth.users where email = 'c@x'), '거절하면 계정이 지워진다');
select t.err($q$select public.reject_admin('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$q$, 'NOT_FOUND');
select t.err($q$select public.approve_admin(gen_random_uuid())$q$, 'NOT_FOUND');
select public.approve_admin('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select t.ok((select count(*) from public.admin_requests()) = 0, '승인하면 목록에서 빠진다');
set request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select t.ok(public.is_admin(), '승인된 b 는 운영자다');
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 집회별 운영자: 맡은 집회만, 새 집회는 못 만든다
-- ===========================================================================
-- d 는 가입만 한 계정 (전체 운영자 승인 없음). 1번 집회의 운영자로만 등록한다.
reset role;
insert into auth.users (id, email) values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'd@x');
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select t.err($q$select public.add_gathering_admin('00000000-0000-0000-0000-000000000001', 'none@x')$q$,
             'NO_ACCOUNT');
select t.ok(public.add_gathering_admin('00000000-0000-0000-0000-000000000001', ' D@X ')
              = 'dddddddd-dddd-dddd-dddd-dddddddddddd',
  '이메일로 찾아 집회 운영자로 등록한다 (공백·대소문자 무시)');
select public.add_gathering_admin('00000000-0000-0000-0000-000000000001', 'd@x');  -- 두 번 넣어도 된다
select t.ok((select count(*) from public.gathering_admin_list('00000000-0000-0000-0000-000000000001')) = 1,
  '집회 운영자 목록이 보인다');

set request.jwt.claim.sub = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
select t.ok(not public.is_admin(), 'd 는 전체 운영자가 아니다');
select t.ok(public.can_manage(), 'd 는 관리자 앱에 들어올 수 있다');
select t.ok((select array_agg(x) from public.my_gatherings() x)
              = array['00000000-0000-0000-0000-000000000001'::uuid],
  '내가 맡은 집회만 돌려준다');

-- 맡은 집회: 신청·방배정이 보이고 고칠 수 있다
select t.ok((select count(*) from public.registrations
              where gathering_id = '00000000-0000-0000-0000-000000000001') > 0,
  '맡은 집회의 신청이 보인다');
select t.ok((select count(*) from public.registrations
              where gathering_id = '00000000-0000-0000-0000-000000000002') = 0,
  '안 맡은 집회의 신청은 안 보인다');
select t.ok(public.save_room_plan('00000000-0000-0000-0000-000000000001',
              '{"rooms":[2]}', (select version from public.room_plans
                                 where gathering_id = '00000000-0000-0000-0000-000000000001')) > 0,
  '맡은 집회의 방배정을 저장한다');
select t.err($q$select public.save_room_plan('00000000-0000-0000-0000-000000000004', '{}', 0)$q$,
             'FORBIDDEN');
select t.err($q$select public.admin_add_registration('00000000-0000-0000-0000-000000000004', '01012340000', '1234', '[{"name":"x"}]', null, null, 0)$q$,
             'FORBIDDEN');
do $$ begin
  update public.gatherings set place = '여기' where id = '00000000-0000-0000-0000-000000000001';
  perform t.ok(found, '맡은 집회 설정은 고친다');
  update public.gatherings set place = '저기' where id = '00000000-0000-0000-0000-000000000002';
  perform t.ok(not found, '안 맡은 집회 설정은 못 고친다');
  delete from public.gatherings where id = '00000000-0000-0000-0000-000000000001';
  perform t.ok(not found, '집회 삭제는 전체 운영자만');
end $$;
select t.err($q$insert into public.gatherings (name, start_date, end_date) values ('새', '2026-01-01', '2026-01-02')$q$,
             'row-level security');
-- 계정 승인은 전체 운영자만
select t.ok((select count(*) from public.admin_requests()) = 0, '집회 운영자는 가입 신청을 못 본다');
select t.err($q$select public.approve_admin('dddddddd-dddd-dddd-dddd-dddddddddddd')$q$, 'FORBIDDEN');
-- 이미지도 맡은 집회 폴더만
select t.err($q$insert into storage.objects (bucket_id, name) values ('gathering-images', '00000000-0000-0000-0000-000000000004/p.jpg')$q$,
             'row-level security');
insert into storage.objects (bucket_id, name)
values ('gathering-images', '00000000-0000-0000-0000-000000000001/p.jpg');
select t.ok((select count(*) from storage.objects
              where name = '00000000-0000-0000-0000-000000000001/p.jpg') = 1,
  '맡은 집회 폴더에는 이미지를 올린다');

set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select public.remove_gathering_admin('00000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd');
select t.err($q$select public.remove_gathering_admin('00000000-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd')$q$,
             'NOT_FOUND');
set request.jwt.claim.sub = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
select t.ok(not public.can_manage(), '빼고 나면 관리자 앱에 못 들어온다');
select t.ok((select count(*) from public.registrations) = 0, '빼고 나면 신청도 안 보인다');
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 다시 신청자: 확정 후엔 못 고치고, 운영자가 PIN 을 바꾸면 잠금이 풀린다
-- ===========================================================================
set role anon;
set request.jwt.claim.sub = '';

select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234') ->> 'status' = 'confirmed',
  '확정된 상태가 조회된다');
select t.err($q$select public.update_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234', '[{"name":"x"}]', null, null, 0)$q$,
             'NOT_EDITABLE');
select t.err($q$select public.cancel_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234')$q$,
             'NOT_EDITABLE');
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000001', '01099998888', '4444') is not null,
  'PIN 재설정 후 새 PIN 으로 조회되고 잠금도 풀린다');
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000002', '01055554444', '5555') ->> 'status' = 'pending',
  '운영자가 넣은 신청도 휴대폰+PIN 으로 조회된다');
select t.err($q$insert into storage.objects (bucket_id, name) values ('gathering-images', 'y.jpg')$q$, 'row-level security');

-- 홈스테이 신청자: 우리 집에 배정된 사람만, 운영자 메모는 빼고 보인다
select t.ok((select schedule -> 0 ->> 'title' from public.gatherings
              where id = '00000000-0000-0000-0000-000000000004') = '개회예배',
  '일정표는 누구나 읽는다');
select t.ok(jsonb_array_length(
    public.lookup_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234') -> 'assigned') = 1,
  '다른 방(102)에 배정된 사람은 안 보인다');
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234')
              -> 'assigned' -> 0 ->> 'phone' = '010-1111-0001', '배정된 참석자의 연락처가 보인다');
select t.ok(not (public.lookup_registration('00000000-0000-0000-0000-000000000004', '01033332222', '1234')
              -> 'assigned' -> 0 ? 'note'), '운영자 메모는 신청자에게 안 준다');
select t.ok(public.lookup_registration('00000000-0000-0000-0000-000000000001', '01012345678', '1234')
              ->> 'assigned' = '[]', '일반 집회는 배정 목록이 비어 있다');
select t.err($q$select public._assigned('00000000-0000-0000-0000-000000000004', gen_random_uuid())$q$,
             'permission denied');

-- 마감되면 수정은 막히고 취소는 된다
reset role;
update public.gatherings set open = false where id = '00000000-0000-0000-0000-000000000001';
set role anon;
select t.err($q$select public.update_registration('00000000-0000-0000-0000-000000000001', '01099998888', '4444', '[{"name":"c"}]', null, null, 0)$q$,
             'CLOSED');
select t.ok(public.cancel_registration('00000000-0000-0000-0000-000000000001', '01099998888', '4444') ->> 'status' = 'cancelled',
  '마감 후에도 입금대기면 취소된다');

reset role;
\o
\echo ALL OK
