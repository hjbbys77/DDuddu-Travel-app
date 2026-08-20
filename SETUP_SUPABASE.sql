-- ============================================================
--  뚜래블 · 신규 Supabase 프로젝트 초기 설정
--
--  대상: 서울 리전(ap-northeast-2)에 새로 만든 프로젝트
--  실행: 대시보드 > SQL Editor 에 전체를 붙여넣고 한 번에 Run
--
--  기존 프로젝트(ap-south-1)는 데이터 이전이 확인될 때까지 지우지 마세요.
-- ============================================================


-- ============================================================
-- 1. 테이블
-- ============================================================

create table if not exists public.baljauk_users (
  id         bigint generated always as identity primary key,
  name       text        not null unique,        -- 닉네임 = 로그인 ID
  password   text        not null,               -- SHA-256 해시 (평문 저장 안 함)
  my_code    text        unique,                 -- 친구 코드
  data       jsonb       not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists baljauk_users_my_code_idx on public.baljauk_users (my_code);


-- ============================================================
-- 2. 접근 차단
--
--    RLS를 켜고 정책을 하나도 만들지 않는다 = anon 키로는 테이블에
--    직접 접근할 수 없다. 아래 SECURITY DEFINER 함수만이 유일한 통로다.
--    (함수는 소유자 권한으로 실행되므로 RLS를 우회한다)
-- ============================================================

alter table public.baljauk_users enable row level security;

revoke all on table public.baljauk_users from anon, authenticated;


-- ============================================================
-- 3. 앱이 사용할 함수
--
--    어떤 함수도 password 컬럼을 반환하지 않는다.
--    data에 _pwd 키가 섞여 들어오더라도 저장 시점에 제거한다.
-- ============================================================

-- 3-1. 닉네임 사용 여부 (회원가입 화면 안내용)
create or replace function public.app_name_taken(p_name text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists(select 1 from baljauk_users where name = p_name);
$$;

-- 3-2. 로그인 — 닉네임과 자격증명이 모두 맞을 때만 데이터를 돌려준다
create or replace function public.app_login(p_name text, p_cred text)
returns table (name text, my_code text, data jsonb)
language sql stable security definer set search_path = public
as $$
  select u.name, u.my_code, u.data - '_pwd'
  from baljauk_users u
  where u.name = p_name and u.password = p_cred
  limit 1;
$$;

-- 3-3. 회원가입 — 닉네임이 이미 있으면 false
create or replace function public.app_signup(p_name text, p_cred text, p_code text, p_data jsonb)
returns boolean
language plpgsql security definer set search_path = public
as $$
begin
  if p_name is null or length(trim(p_name)) = 0 then return false; end if;
  if p_cred is null or length(p_cred) = 0      then return false; end if;
  insert into baljauk_users(name, password, my_code, data)
  values (p_name, p_cred, p_code, coalesce(p_data, '{}'::jsonb) - '_pwd');
  return true;
exception when unique_violation then
  return false;
end;
$$;

-- 3-4. 저장 — 본인 자격증명이 맞는 행만 갱신
--      p_new_cred가 비어있지 않으면 비밀번호를 그 값으로 교체한다(해시 승격용)
create or replace function public.app_save(
  p_name text, p_cred text, p_new_cred text, p_code text, p_data jsonb)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare n int;
begin
  update baljauk_users
     set password   = coalesce(nullif(p_new_cred, ''), password),
         my_code    = coalesce(nullif(p_code, ''), my_code),
         data       = coalesce(p_data, '{}'::jsonb) - '_pwd',
         updated_at = now()
   where name = p_name and password = p_cred;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- 3-5. 계정 삭제
create or replace function public.app_delete_account(p_name text, p_cred text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare n int;
begin
  delete from baljauk_users where name = p_name and password = p_cred;
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- 3-6. 친구 코드로 찾기
--      ⚠️ 친구 코드를 아는 사람은 그 사람의 여행 기록 전체를 볼 수 있다.
--         현재 앱의 친구 기능이 그렇게 설계돼 있어 그대로 두었다.
create or replace function public.app_find_friend(p_code text)
returns table (name text, my_code text, data jsonb)
language sql stable security definer set search_path = public
as $$
  select u.name, u.my_code, u.data - '_pwd'
  from baljauk_users u
  where u.my_code = p_code
  limit 1;
$$;


-- ============================================================
-- 4. 실행 권한
--    anon 키로 호출할 수 있는 것은 아래 6개 함수뿐이다.
-- ============================================================

revoke execute on all functions in schema public from anon;

grant execute on function public.app_name_taken(text)                    to anon;
grant execute on function public.app_login(text, text)                   to anon;
grant execute on function public.app_signup(text, text, text, jsonb)     to anon;
grant execute on function public.app_save(text, text, text, text, jsonb) to anon;
grant execute on function public.app_delete_account(text, text)          to anon;
grant execute on function public.app_find_friend(text)                   to anon;


-- ============================================================
-- 5. 확인 — 아래 3개를 실행해서 결과를 알려주세요
-- ============================================================

-- 아래 쿼리 하나만 실행하면 세 가지를 한 번에 확인할 수 있습니다.
-- (SQL Editor는 여러 쿼리를 돌리면 마지막 결과만 보여줍니다)

select '1_함수' as 구분, routine_name as 값
  from information_schema.routines
 where routine_schema = 'public' and routine_name like 'app_%'
union all
select '2_RLS', relrowsecurity::text
  from pg_class where relname = 'baljauk_users'
union all
select '3_anon권한(0이어야_정상)', count(*)::text
  from information_schema.role_table_grants
 where table_name = 'baljauk_users' and grantee in ('anon','authenticated')
order by 1, 2;

-- 기대 결과: 1_함수 6줄(app_delete_account, app_find_friend, app_login,
--            app_name_taken, app_save, app_signup) + 2_RLS true + 3_anon권한 0
