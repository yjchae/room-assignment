-- 한 번만 쓰는 이전 스크립트: public 스키마에 있던 이 앱 테이블을 room 스키마로 옮긴다.
-- 같은 Supabase 프로젝트를 다른 앱(토라포션)도 public 에서 쓰고 있어서 나눈다. 데이터는 그대로 따라간다.
--
-- 순서 (SQL Editor 에서 차례로. 하나라도 에러가 나면 멈추고 다음으로 가지 않는다)
--   0. sh tool/backup_db.sh 로 로컬 백업
--   1. 이 파일의 [1부] 만 붙여넣고 Run
--   2. supabase/schema.sql 전체를 붙여넣고 Run
--   3. 이 파일의 [2부] 만 붙여넣고 Run
--   4. 대시보드 → Project Settings → Data API → Exposed schemas 에 room 추가 (public 은 그대로 둔다)
--   5. 새 앱 배포 (main 에 push → 웹 / macOS·Windows 앱은 새로 빌드)
-- 1~5 사이에는 신청 웹과 운영자 앱이 안 된다. 신청이 적은 시간에 한 번에 한다.
--
-- [1부] 를 돌리기 전에 다른 앱이 같은 이름의 테이블을 쓰지 않는지 꼭 본다 —
-- 아래 이름 중 다른 앱 것이 있으면 그 앱 테이블까지 옮겨 버린다:
--   select tablename from pg_tables where schemaname = 'public'
--    and tablename in ('admins','gatherings','gathering_admins','registrations','lookup_failures','room_plans');

-- ===========================================================================
-- [1부] 백업 사본 + 테이블 옮기기
-- ===========================================================================

-- DB 안 백업 사본. API 로 노출되지 않는 스키마라 앱에서는 안 보인다.
-- 다 확인한 뒤 지운다: drop schema room_backup cascade;
create schema if not exists room_backup;
create table if not exists room_backup.admins as table public.admins;
create table if not exists room_backup.gatherings as table public.gatherings;
create table if not exists room_backup.gathering_admins as table public.gathering_admins;
create table if not exists room_backup.registrations as table public.registrations;
create table if not exists room_backup.room_plans as table public.room_plans;
revoke all on schema room_backup from anon, authenticated;

create schema if not exists room;
alter table if exists public.admins set schema room;
alter table if exists public.gatherings set schema room;
alter table if exists public.gathering_admins set schema room;
alter table if exists public.registrations set schema room;
alter table if exists public.lookup_failures set schema room;
alter table if exists public.room_plans set schema room;

-- 옮긴 행 수 = 백업 사본 행 수인지 본다 (전부 true 여야 한다).
select 'gatherings' t, (select count(*) from room.gatherings) = (select count(*) from room_backup.gatherings) same
union all select 'registrations', (select count(*) from room.registrations) = (select count(*) from room_backup.registrations)
union all select 'room_plans', (select count(*) from room.room_plans) = (select count(*) from room_backup.room_plans)
union all select 'gathering_admins', (select count(*) from room.gathering_admins) = (select count(*) from room_backup.gathering_admins);


-- ===========================================================================
-- [2부] schema.sql 을 돌린 뒤: 기존 운영자 옮기기 + public 에 남은 이 앱 함수 지우기
-- ===========================================================================

-- 이미 집회 운영자로 등록된 사람은 helper 로 (맡은 집회는 그대로).
-- 예전 가입 신청 대기자는 옮기지 않는다 — 다른 앱 가입자와 구별이 안 된다. 필요하면 다시 가입 신청.
insert into room.members (user_id, status)
select distinct user_id, 'helper' from room.gathering_admins
 where user_id not in (select user_id from room.admins)
on conflict do nothing;

-- cascade 없이 지운다: 다른 앱의 정책이 이 함수를 쓰고 있으면 여기서 에러가 나고 멈춘다
-- (그러면 그 줄만 빼고 다시 돌린다 — 그 함수는 다른 앱 것이다).
drop function if exists public.submit_registration(uuid, text, text, jsonb, text, text, int);
drop function if exists public.lookup_registration(uuid, text, text);
drop function if exists public.update_registration(uuid, text, text, jsonb, text, text, int);
drop function if exists public.cancel_registration(uuid, text, text);
drop function if exists public.lookup_duties(uuid, text, text);
drop function if exists public.save_duty_items(uuid, text, text, text, jsonb);
drop function if exists public.reset_pin(uuid, text);
drop function if exists public.admin_add_registration(uuid, text, text, jsonb, text, text, int);
drop function if exists public.save_room_plan(uuid, jsonb, int);
drop function if exists public.gathering_admin_list(uuid);
drop function if exists public.add_gathering_admin(uuid, text);
drop function if exists public.remove_gathering_admin(uuid, uuid);
drop function if exists public.admin_requests();
drop function if exists public.approve_admin(uuid);
drop function if exists public.reject_admin(uuid);
drop function if exists public._assert_open(uuid);
drop function if exists public._check_input(jsonb, text, text, int);
drop function if exists public._verify(uuid, text, text);
drop function if exists public._assigned(uuid, uuid);
drop function if exists public._my_duties(uuid, jsonb);
drop function if exists public.my_gatherings();
drop function if exists public.can_manage();
drop function if exists public.manages(uuid);
-- 흔한 이름이라 다른 앱도 쓸 수 있다. 다른 앱 코드에서 is_admin / _touch 를 부르면 이 두 줄은 빼고 돌린다.
drop function if exists public.is_admin();
drop function if exists public._touch();
