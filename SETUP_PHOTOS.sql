-- ============================================================
--  뚜래블 · 사진 테이블 분리
--
--  실행: Supabase 대시보드 > SQL Editor 에 전체 붙여넣고 Run
--  대상: 서울 리전 프로젝트 (wyxpuhixeiuojetzkgls)
--
--  왜 필요한가
--  지금은 사진이 사용자 행의 data(JSON) 안에 base64로 들어 있어,
--  로그인할 때마다 전부 내려받고 저장할 때마다 전부 올린다.
--  사진 17장에 6.5MB이고 로그인이 최대 16초까지 걸린다.
--  사진을 별도 행으로 빼면 로그인은 46KB만 받으면 된다.
-- ============================================================


-- ============================================================
-- 1. 사진 테이블
-- ============================================================

create table if not exists public.baljauk_photos (
  id         bigint generated always as identity primary key,
  owner      text        not null,          -- baljauk_users.name
  trip_id    bigint      not null,          -- trips[].id
  idx        int         not null default 0,-- 여행 안에서의 순서
  data       text        not null,          -- data:image/webp;base64,...
  created_at timestamptz not null default now(),
  constraint baljauk_photos_owner_fk
    foreign key (owner) references public.baljauk_users(name)
    on delete cascade                       -- 계정을 지우면 사진도 함께 삭제
    on update cascade
);

create index if not exists baljauk_photos_owner_trip_idx
  on public.baljauk_photos (owner, trip_id, idx);


-- ============================================================
-- 2. 접근 차단 (사용자 테이블과 동일한 방식)
-- ============================================================

alter table public.baljauk_photos enable row level security;
revoke all on table public.baljauk_photos from anon, authenticated;


-- ============================================================
-- 3. 함수
--    사용자 테이블과 같이 비밀번호가 맞을 때만 동작한다.
-- ============================================================

-- 3-1. 내 사진 전부 (여행 상세를 열 때가 아니라, 앱 시작 후 필요할 때 한 번)
create or replace function public.app_photos_list(p_name text, p_cred text)
returns table (trip_id bigint, idx int, data text)
language sql stable security definer set search_path = public
as $$
  select p.trip_id, p.idx, p.data
  from baljauk_photos p
  join baljauk_users u on u.name = p.owner
  where u.name = p_name and u.password = p_cred
  order by p.trip_id, p.idx;
$$;

-- 3-2. 특정 여행의 사진만
create or replace function public.app_photos_of_trip(p_name text, p_cred text, p_trip_id bigint)
returns table (idx int, data text)
language sql stable security definer set search_path = public
as $$
  select p.idx, p.data
  from baljauk_photos p
  join baljauk_users u on u.name = p.owner
  where u.name = p_name and u.password = p_cred and p.trip_id = p_trip_id
  order by p.idx;
$$;

-- 3-3. 한 여행의 사진을 통째로 교체 (추가·삭제·순서변경을 한 번에)
create or replace function public.app_photos_set(
  p_name text, p_cred text, p_trip_id bigint, p_photos text[])
returns int
language plpgsql security definer set search_path = public
as $$
declare
  ok  boolean;
  i   int := 0;
  ph  text;
begin
  select exists(select 1 from baljauk_users where name = p_name and password = p_cred) into ok;
  if not ok then return -1; end if;

  delete from baljauk_photos where owner = p_name and trip_id = p_trip_id;
  if p_photos is null then return 0; end if;

  foreach ph in array p_photos loop
    insert into baljauk_photos(owner, trip_id, idx, data) values (p_name, p_trip_id, i, ph);
    i := i + 1;
  end loop;
  return i;
end;
$$;

-- 3-4. 여행을 지울 때 그 사진도 정리
create or replace function public.app_photos_delete_trip(p_name text, p_cred text, p_trip_id bigint)
returns int
language plpgsql security definer set search_path = public
as $$
declare ok boolean; n int;
begin
  select exists(select 1 from baljauk_users where name = p_name and password = p_cred) into ok;
  if not ok then return -1; end if;
  delete from baljauk_photos where owner = p_name and trip_id = p_trip_id;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- 3-5. 친구 사진 조회 (친구 코드를 아는 사람에게 공개)
--      ⚠️ 코드를 아는 사람은 그 사람의 여행 사진을 볼 수 있게 된다.
create or replace function public.app_friend_photos(p_code text, p_trip_id bigint)
returns table (idx int, data text)
language sql stable security definer set search_path = public
as $$
  select p.idx, p.data
  from baljauk_photos p
  join baljauk_users u on u.name = p.owner
  where u.my_code = p_code and p.trip_id = p_trip_id
  order by p.idx;
$$;


-- ============================================================
-- 4. 실행 권한
-- ============================================================

grant execute on function public.app_photos_list(text, text)                     to anon;
grant execute on function public.app_photos_of_trip(text, text, bigint)          to anon;
grant execute on function public.app_photos_set(text, text, bigint, text[])      to anon;
grant execute on function public.app_photos_delete_trip(text, text, bigint)      to anon;
grant execute on function public.app_friend_photos(text, bigint)                 to anon;


-- ============================================================
-- 5. 확인 — 이 쿼리 하나만 실행해서 결과를 알려주세요
-- ============================================================

select '1_함수' as 구분, routine_name as 값
  from information_schema.routines
 where routine_schema = 'public' and routine_name like 'app_photo%'
union all
select '1_함수', routine_name
  from information_schema.routines
 where routine_schema = 'public' and routine_name = 'app_friend_photos'
union all
select '2_RLS', relrowsecurity::text
  from pg_class where relname = 'baljauk_photos'
union all
select '3_anon권한(0이어야_정상)', count(*)::text
  from information_schema.role_table_grants
 where table_name = 'baljauk_photos' and grantee in ('anon','authenticated')
order by 1, 2;

-- 기대 결과: 1_함수 5줄 + 2_RLS true + 3_anon권한 0
