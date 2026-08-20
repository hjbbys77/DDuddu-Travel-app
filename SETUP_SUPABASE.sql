-- ============================================================
--  뚜래블 · Supabase 보안 설정
--  실행 위치: Supabase 대시보드 > SQL Editor
--  https://supabase.com/dashboard/project/ptcuejfmsopyafngreea/sql
--
--  ⚠️ STEP 1부터 순서대로. 각 단계마다 앱이 정상 동작하는지 확인하고 넘어가세요.
--  ⚠️ 실행 전 Database > Backups 에서 백업을 한 번 떠두세요.
-- ============================================================


-- ============================================================
-- STEP 0. 현재 상태 확인 (먼저 이것만 실행해서 결과를 확인하세요)
-- ============================================================

-- 0-1. RLS가 켜져 있는지
select relname as "테이블", relrowsecurity as "RLS 활성화"
from pg_class where relname = 'baljauk_users';

-- 0-2. 현재 정책 목록
select policyname as "정책명", cmd as "동작", roles as "대상"
from pg_policies where tablename = 'baljauk_users';

-- 0-3. 계정 수와 비밀번호 저장 형태
select
  count(*) as "전체 계정",
  count(*) filter (where password like 'sha256$%') as "해시 완료",
  count(*) filter (where password not like 'sha256$%') as "평문 남음"
from baljauk_users;

-- 0-4. data 컬럼에 비밀번호가 남아있는 계정 (구버전에서 저장된 것)
select count(*) as "data에 비번 남은 계정"
from baljauk_users where data ? '_pwd';


-- ============================================================
-- STEP 1. data 컬럼에 남아있는 평문 비밀번호 제거
--         (앱은 이미 저장하지 않지만, 과거 데이터가 남아있음)
-- ============================================================

update baljauk_users
set data = data - '_pwd'
where data ? '_pwd';

-- 확인: 0이 나와야 합니다
select count(*) as "남은 건수" from baljauk_users where data ? '_pwd';


-- ============================================================
-- STEP 2. 로그인을 서버 함수로 이동
--
--   왜 필요한가:
--   지금은 앱이 password 컬럼을 직접 조회 조건으로 씁니다. 그래서
--   password 컬럼에 대한 SELECT 권한을 막을 수 없고, anon 키를 가진
--   사람이 테이블을 통째로 읽을 수 있습니다.
--   아래 함수(SECURITY DEFINER)로 옮기면 비밀번호 대조가 서버에서만
--   일어나므로, 테이블 직접 접근을 전부 차단할 수 있습니다.
-- ============================================================

-- 2-1. 로그인 함수
create or replace function public.app_login(p_name text, p_cred text)
returns table (name text, my_code text, data jsonb)
language sql
security definer
set search_path = public
as $$
  select u.name, u.my_code, u.data
  from baljauk_users u
  where u.name = p_name and u.password = p_cred
  limit 1;
$$;

-- 2-2. 계정 존재 여부 확인 함수 (비밀번호 없이 닉네임만)
create or replace function public.app_name_taken(p_name text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(select 1 from baljauk_users where name = p_name);
$$;

-- 2-3. 회원가입 함수
create or replace function public.app_signup(p_name text, p_cred text, p_code text, p_data jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into baljauk_users(name, password, my_code, data)
  values (p_name, p_cred, p_code, p_data - '_pwd');
  return true;
exception when unique_violation then
  return false;   -- 이미 사용 중인 닉네임
end;
$$;

-- 2-4. 저장 함수 (본인 자격증명이 맞을 때만 갱신)
create or replace function public.app_save(p_name text, p_cred text, p_new_cred text, p_code text, p_data jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  update baljauk_users
  set password   = coalesce(nullif(p_new_cred, ''), password),
      my_code    = p_code,
      data       = p_data - '_pwd',
      updated_at = now()
  where name = p_name and password = p_cred;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- 2-5. 계정 삭제 함수
create or replace function public.app_delete_account(p_name text, p_cred text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  delete from baljauk_users where name = p_name and password = p_cred;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- 2-6. 친구 코드 조회 함수 (친구에게 필요한 정보만 내려줌)
create or replace function public.app_find_friend(p_code text)
returns table (name text, my_code text, data jsonb)
language sql
security definer
set search_path = public
as $$
  select u.name, u.my_code, u.data - '_pwd'
  from baljauk_users u
  where u.my_code = p_code
  limit 1;
$$;

-- 2-7. anon 역할에 함수 실행 권한 부여
grant execute on function public.app_login(text, text)                          to anon;
grant execute on function public.app_name_taken(text)                           to anon;
grant execute on function public.app_signup(text, text, text, jsonb)            to anon;
grant execute on function public.app_save(text, text, text, text, jsonb)        to anon;
grant execute on function public.app_delete_account(text, text)                 to anon;
grant execute on function public.app_find_friend(text)                          to anon;


-- ============================================================
-- STEP 3. 테이블 직접 접근 차단
--
--   ⚠️ 반드시 앱 코드가 위 함수를 쓰도록 수정된 다음에 실행하세요.
--      먼저 실행하면 현재 앱이 즉시 동작을 멈춥니다.
-- ============================================================

-- 3-1. RLS 활성화
alter table baljauk_users enable row level security;

-- 3-2. 기존 정책이 있다면 제거 (STEP 0-2에서 확인한 이름으로 바꿔서 실행)
-- drop policy if exists "정책이름을_여기에" on baljauk_users;

-- 3-3. anon에게 정책을 하나도 주지 않는다
--      = RLS가 켜진 상태에서 정책이 없으면 모든 직접 접근이 거부된다.
--        SECURITY DEFINER 함수는 RLS를 우회하므로 앱은 정상 동작한다.

-- 3-4. 테이블 권한도 회수
revoke all on table baljauk_users from anon;

-- 확인: 아래 쿼리가 "권한 없음" 또는 0건이면 성공
-- select * from baljauk_users limit 1;


-- ============================================================
-- STEP 4. 마무리 확인
-- ============================================================

-- 4-1. 함수가 잘 만들어졌는지
select routine_name as "함수명"
from information_schema.routines
where routine_schema = 'public' and routine_name like 'app_%'
order by routine_name;

-- 4-2. RLS 상태
select relname as "테이블", relrowsecurity as "RLS 활성화"
from pg_class where relname = 'baljauk_users';
