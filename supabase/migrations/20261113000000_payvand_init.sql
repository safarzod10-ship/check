-- ============================================================================
-- PAYVAND — схема базы данных (PostgreSQL / Supabase)
-- Все права доступа проверяются НА СЕРВЕРЕ (Row Level Security + функции).
-- Клиент (APK) знает только публичный anon-ключ; service_role в APK не попадает.
-- ============================================================================

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------- профили ---
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  payvand_id   text not null unique,
  username     text unique check (username ~ '^[a-z][a-z0-9_]{3,23}$'),
  display_name text not null default '' check (char_length(display_name) <= 64),
  bio          text not null default '' check (char_length(bio) <= 200),
  avatar_path  text check (avatar_path is null or char_length(avatar_path) <= 300),
  last_seen    timestamptz not null default now(),
  created_at   timestamptz not null default now()
);
create index profiles_name_trgm on public.profiles using gin (display_name extensions.gin_trgm_ops);

-- Приватные данные (телефон виден только владельцу). Номер НЕ подтверждён SMS.
create table public.profile_private (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone   text check (phone is null or phone ~ '^\+[0-9]{7,15}$'),
  updated_at timestamptz not null default now()
);

create or replace function public.gen_payvand_id() returns text
language plpgsql volatile set search_path = public as $$
declare candidate text;
begin
  loop
    candidate := 'PV' || lpad((floor(random() * 100000000))::bigint::text, 8, '0');
    exit when not exists (select 1 from profiles where payvand_id = candidate);
  end loop;
  return candidate;
end $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, payvand_id) values (new.id, gen_payvand_id());
  insert into profile_private (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.profiles_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  new.id := old.id;
  new.payvand_id := old.payvand_id;      -- PAYVAND ID неизменяем
  new.created_at := old.created_at;
  if new.last_seen is distinct from old.last_seen then new.last_seen := now(); end if;
  return new;
end $$;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.profiles_guard();

-- ----------------------------------------------------------------- беседы ---
create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  type            text not null check (type in ('direct','group','channel')),
  title           text check (title is null or char_length(title) between 1 and 80),
  description     text not null default '' check (char_length(description) <= 300),
  avatar_path     text check (avatar_path is null or char_length(avatar_path) <= 300),
  is_public       boolean not null default false,
  direct_key      text unique,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  check ((type = 'direct') = (direct_key is not null)),
  check (type = 'direct' or title is not null)
);
create index conversations_public_title on public.conversations using gin (title extensions.gin_trgm_ops) where is_public;

create table public.members (
  conversation_id   uuid not null references public.conversations(id) on delete cascade,
  user_id           uuid not null references public.profiles(id) on delete cascade,
  role              text not null default 'member' check (role in ('owner','admin','member')),
  joined_at         timestamptz not null default now(),
  last_read_at      timestamptz not null default now(),
  last_delivered_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index members_user on public.members(user_id);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid references public.profiles(id) on delete set null,
  kind            text not null default 'text' check (kind in ('text','image','video','file','voice','system')),
  body            text not null default '' check (char_length(body) <= 4000),
  media_path      text check (media_path is null or char_length(media_path) <= 300),
  media_name      text check (media_name is null or char_length(media_name) <= 200),
  media_mime      text check (media_mime is null or char_length(media_mime) <= 100),
  media_size      bigint check (media_size is null or media_size between 0 and 52428800),
  duration_ms     integer check (duration_ms is null or duration_ms between 0 and 3600000),
  reply_to_id     uuid references public.messages(id) on delete set null,
  forwarded_from  uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  edited_at       timestamptz,
  deleted_at      timestamptz
);
create index messages_conv_time on public.messages(conversation_id, created_at desc);
create index messages_sender_time on public.messages(sender_id, created_at desc);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete cascade,
  conversation_id  uuid references public.conversations(id) on delete set null,
  message_id       uuid references public.messages(id) on delete set null,
  reason           text not null check (char_length(reason) between 1 and 500),
  created_at       timestamptz not null default now()
);

create table public.device_tokens (
  token      text primary key check (char_length(token) between 10 and 4096),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null default 'android',
  lang       text not null default 'ru',
  updated_at timestamptz not null default now()
);
create index device_tokens_user on public.device_tokens(user_id);

-- ------------------------------------------------- вспомогательные функции ---
create or replace function public.try_uuid(t text) returns uuid
language plpgsql immutable as $$
begin return t::uuid; exception when others then return null; end $$;

create or replace function public.is_member(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where conversation_id = c and user_id = auth.uid());
$$;

create or replace function public.my_role(c uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from members where conversation_id = c and user_id = auth.uid();
$$;

create or replace function public.is_blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocks
                 where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

-- Может ли текущий пользователь писать в беседу.
create or replace function public.can_post(c uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare t text; r text; peer uuid;
begin
  select role into r from members where conversation_id = c and user_id = auth.uid();
  if r is null then return false; end if;
  select type into t from conversations where id = c;
  if t = 'channel' then return r in ('owner','admin'); end if;
  if t = 'direct' then
    select user_id into peer from members where conversation_id = c and user_id <> auth.uid() limit 1;
    if peer is null then return false; end if;
    return not is_blocked_between(auth.uid(), peer);
  end if;
  return true;
end $$;

-- --------------------------------------------------- триггеры сообщений ---
create or replace function public.messages_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare recent int; is_sys boolean := coalesce(current_setting('payvand.sys', true), '') = '1';
begin
  new.created_at := now();
  new.edited_at := null;
  new.deleted_at := null;
  if new.kind = 'system' and not is_sys then
    raise exception 'system messages are server-only' using errcode = '42501';
  end if;
  if not is_sys then
    -- ограничение частоты: не более 60 сообщений в минуту и 20 за 10 секунд на пользователя
    select count(*) into recent from messages
      where sender_id = auth.uid() and created_at > now() - interval '60 seconds';
    if recent >= 60 then raise exception 'rate_limit' using errcode = 'P0001'; end if;
    select count(*) into recent from messages
      where sender_id = auth.uid() and created_at > now() - interval '10 seconds';
    if recent >= 20 then raise exception 'rate_limit' using errcode = 'P0001'; end if;
    if new.kind = 'text' and btrim(new.body) = '' then
      raise exception 'empty message' using errcode = '23514';
    end if;
    if new.kind <> 'text' and new.media_path is null then
      raise exception 'media required' using errcode = '23514';
    end if;
    if new.kind = 'text' then
      new.media_path := null; new.media_name := null; new.media_mime := null;
      new.media_size := null; new.duration_ms := null;
    end if;
    -- файл обязан лежать в папке этой беседы и этого отправителя
    if new.media_path is not null and
       new.media_path not like (new.conversation_id::text || '/' || new.sender_id::text || '/%') then
      raise exception 'bad media path' using errcode = '42501';
    end if;
    if new.reply_to_id is not null and not exists
       (select 1 from messages where id = new.reply_to_id and conversation_id = new.conversation_id) then
      new.reply_to_id := null;
    end if;
  end if;
  return new;
end $$;
create trigger messages_before_insert before insert on public.messages
  for each row execute function public.messages_before_insert();

create or replace function public.messages_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update conversations set last_message_at = new.created_at where id = new.conversation_id;
  if new.sender_id is not null then
    update members set last_read_at = new.created_at, last_delivered_at = new.created_at
      where conversation_id = new.conversation_id and user_id = new.sender_id;
  end if;
  return null;
end $$;
create trigger messages_after_insert after insert on public.messages
  for each row execute function public.messages_after_insert();

create or replace function public.sys_message(c uuid, actor uuid, txt text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('payvand.sys', '1', true);
  insert into messages (conversation_id, sender_id, kind, body) values (c, actor, 'system', txt);
  perform set_config('payvand.sys', '', true);
end $$;

-- ------------------------------------------------------------------- RLS ---
alter table public.profiles        enable row level security;
alter table public.profile_private enable row level security;
alter table public.conversations   enable row level security;
alter table public.members         enable row level security;
alter table public.messages        enable row level security;
alter table public.blocks          enable row level security;
alter table public.reports         enable row level security;
alter table public.device_tokens   enable row level security;

create policy profiles_select on public.profiles for select to authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy private_select on public.profile_private for select to authenticated using (user_id = auth.uid());
create policy private_update on public.profile_private for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy conversations_select on public.conversations for select to authenticated
  using (public.is_member(id) or (is_public and type <> 'direct'));

create policy members_select on public.members for select to authenticated
  using (user_id = auth.uid() or public.is_member(conversation_id));

create policy messages_select on public.messages for select to authenticated
  using (public.is_member(conversation_id));
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.can_post(conversation_id));
-- UPDATE/DELETE сообщений напрямую запрещены: только через edit_message / delete_message.

create policy blocks_all on public.blocks for all to authenticated
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

create policy reports_insert on public.reports for insert to authenticated with check (reporter_id = auth.uid());
create policy reports_select on public.reports for select to authenticated using (reporter_id = auth.uid());

create policy tokens_all on public.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Убираем лишние права по умолчанию; anon не имеет доступа к данным вообще.
revoke all on all tables in schema public from anon;
revoke insert, update, delete, truncate on public.conversations, public.members from authenticated;
revoke update, delete, truncate on public.messages, public.reports from authenticated;
revoke insert, delete, truncate on public.profiles, public.profile_private from authenticated;

-- ------------------------------------------------------------ RPC: API ---
create or replace function public.require_user() returns uuid
language plpgsql stable set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '42501'; end if;
  return auth.uid();
end $$;

create or replace function public.heartbeat() returns void
language sql security definer set search_path = public as $$
  update profiles set last_seen = now() where id = auth.uid();
$$;

create or replace function public.search_users(q text)
returns setof public.profiles
language sql stable security definer set search_path = public, extensions as $$
  select p.* from profiles p
  where auth.uid() is not null
    and p.id <> auth.uid()
    and p.username is not null
    and char_length(btrim(q)) >= 2
    and not exists (select 1 from blocks b where b.blocker_id = p.id and b.blocked_id = auth.uid())
    and (p.username like lower(ltrim(btrim(q), '@')) || '%'
         or upper(p.payvand_id) = upper(btrim(q))
         or p.display_name ilike '%' || replace(replace(btrim(q), '%', ''), '_', '') || '%')
  order by (p.username = lower(ltrim(btrim(q), '@'))) desc, p.display_name
  limit 30;
$$;

create or replace function public.create_direct(other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); k text; c uuid;
begin
  if other = me then raise exception 'cannot chat with yourself' using errcode = '22023'; end if;
  if not exists (select 1 from profiles where id = other) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  k := least(me::text, other::text) || ':' || greatest(me::text, other::text);
  select id into c from conversations where direct_key = k;
  if c is not null then return c; end if;
  if is_blocked_between(me, other) then raise exception 'blocked' using errcode = '42501'; end if;
  insert into conversations (type, direct_key, created_by) values ('direct', k, me)
    on conflict (direct_key) do nothing returning id into c;
  if c is null then select id into c from conversations where direct_key = k; return c; end if;
  insert into members (conversation_id, user_id, role) values (c, me, 'member'), (c, other, 'member');
  return c;
end $$;

create or replace function public.create_conversation(
  p_type text, p_title text, p_description text default '', p_is_public boolean default false,
  p_member_ids uuid[] default '{}', p_avatar_path text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); c uuid; n int;
begin
  if p_type not in ('group','channel') then raise exception 'bad type' using errcode = '22023'; end if;
  if coalesce(array_length(p_member_ids, 1), 0) > 200 then
    raise exception 'too many members' using errcode = '22023';
  end if;
  select count(*) into n from conversations where created_by = me and created_at > now() - interval '1 hour';
  if n >= 20 then raise exception 'rate_limit' using errcode = 'P0001'; end if;
  insert into conversations (type, title, description, is_public, created_by, avatar_path)
    values (p_type, btrim(p_title), coalesce(p_description, ''), coalesce(p_is_public, false), me, p_avatar_path)
    returning id into c;
  insert into members (conversation_id, user_id, role) values (c, me, 'owner');
  insert into members (conversation_id, user_id, role)
    select c, p.id, 'member' from profiles p
    where p.id = any(p_member_ids) and p.id <> me
      and not is_blocked_between(me, p.id)
    on conflict do nothing;
  perform sys_message(c, me, 'created');
  return c;
end $$;

create or replace function public.update_conversation(
  c uuid, p_title text, p_description text, p_is_public boolean, p_avatar_path text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_user();
  if coalesce(my_role(c), '') not in ('owner','admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update conversations set title = btrim(p_title), description = coalesce(p_description, ''),
         is_public = coalesce(p_is_public, false), avatar_path = p_avatar_path
   where id = c and type <> 'direct';
end $$;

create or replace function public.add_members(c uuid, ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); r record; added int := 0; total int;
begin
  if coalesce(my_role(c), '') not in ('owner','admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if (select type from conversations where id = c) = 'direct' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select count(*) into total from members where conversation_id = c;
  for r in select p.id, p.display_name from profiles p
           where p.id = any(ids) and not is_blocked_between(me, p.id)
             and not exists (select 1 from members m where m.conversation_id = c and m.user_id = p.id)
  loop
    exit when total + added >= 1000;
    insert into members (conversation_id, user_id, role) values (c, r.id, 'member');
    perform sys_message(c, me, 'added|' || r.display_name);
    added := added + 1;
  end loop;
  return added;
end $$;

create or replace function public.remove_member(c uuid, target uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); mine text; theirs text; t text; nm text; heir uuid;
begin
  select type into t from conversations where id = c;
  if t is null or t = 'direct' then raise exception 'forbidden' using errcode = '42501'; end if;
  mine := my_role(c);
  select role into theirs from members where conversation_id = c and user_id = target;
  if mine is null or theirs is null then raise exception 'forbidden' using errcode = '42501'; end if;
  if target = me then
    delete from members where conversation_id = c and user_id = me;
    if not exists (select 1 from members where conversation_id = c) then
      delete from conversations where id = c;
      return;
    end if;
    if mine = 'owner' then
      select user_id into heir from members where conversation_id = c
        order by (role = 'admin') desc, joined_at asc limit 1;
      update members set role = 'owner' where conversation_id = c and user_id = heir;
    end if;
    perform sys_message(c, me, 'left');
    return;
  end if;
  if not (mine = 'owner' or (mine = 'admin' and theirs = 'member')) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select display_name into nm from profiles where id = target;
  delete from members where conversation_id = c and user_id = target;
  perform sys_message(c, me, 'removed|' || coalesce(nm, ''));
end $$;

create or replace function public.set_member_role(c uuid, target uuid, new_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_user();
  if new_role not in ('admin','member') then raise exception 'bad role' using errcode = '22023'; end if;
  if coalesce(my_role(c), '') <> 'owner' or target = auth.uid() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update members set role = new_role where conversation_id = c and user_id = target and role <> 'owner';
end $$;

create or replace function public.join_public(c uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if not exists (select 1 from conversations where id = c and is_public and type <> 'direct') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if is_member(c) then return; end if;
  if (select count(*) from members where conversation_id = c) >= 1000 then
    raise exception 'conversation is full' using errcode = '22023';
  end if;
  insert into members (conversation_id, user_id, role) values (c, me, 'member');
  perform sys_message(c, me, 'joined');
end $$;

create or replace function public.mark_read(c uuid) returns void
language sql security definer set search_path = public as $$
  update members set last_read_at = now(), last_delivered_at = now()
   where conversation_id = c and user_id = auth.uid();
$$;

create or replace function public.mark_delivered() returns void
language sql security definer set search_path = public as $$
  update members m set last_delivered_at = now()
   from conversations c
   where m.user_id = auth.uid() and c.id = m.conversation_id and c.last_message_at > m.last_delivered_at;
$$;

create or replace function public.edit_message(m uuid, new_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform require_user();
  if btrim(coalesce(new_body, '')) = '' or char_length(new_body) > 4000 then
    raise exception 'bad body' using errcode = '23514';
  end if;
  update messages set body = new_body, edited_at = now()
   where id = m and sender_id = auth.uid() and deleted_at is null and kind = 'text'
     and can_post(conversation_id);
  if not found then raise exception 'forbidden' using errcode = '42501'; end if;
end $$;

-- Удаление: автор сообщения либо админ/владелец группы. Возвращает путь файла для очистки хранилища.
create or replace function public.delete_message(m uuid) returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); msg messages; path text;
begin
  select * into msg from messages where id = m;
  if msg.id is null or msg.deleted_at is not null or msg.kind = 'system' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not (msg.sender_id = me or
          ((select type from conversations where id = msg.conversation_id) <> 'direct'
           and coalesce(my_role(msg.conversation_id), '') in ('owner','admin'))) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  path := msg.media_path;
  update messages set deleted_at = now(), body = '', media_path = null, media_name = null,
         media_mime = null, media_size = null, duration_ms = null where id = m;
  return path;
end $$;

create or replace function public.my_conversations()
returns table (
  id uuid, type text, title text, description text, avatar_path text, is_public boolean,
  my_role text, last_message_at timestamptz, unread_count int, member_count int,
  last_id uuid, last_kind text, last_body text, last_sender_id uuid, last_sender_name text,
  last_created_at timestamptz, last_deleted boolean,
  peer_id uuid, peer_name text, peer_username text, peer_avatar text, peer_last_seen timestamptz,
  peer_last_read_at timestamptz, peer_last_delivered_at timestamptz, blocked boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.type, c.title, c.description, c.avatar_path, c.is_public,
         me.role, c.last_message_at,
         (select count(*)::int from messages x
           where x.conversation_id = c.id and x.created_at > me.last_read_at
             and x.sender_id is distinct from auth.uid() and x.deleted_at is null and x.kind <> 'system'),
         (select count(*)::int from members mm where mm.conversation_id = c.id),
         lm.id, lm.kind, lm.body, lm.sender_id, sp.display_name, lm.created_at, lm.deleted_at is not null,
         pp.id, pp.display_name, pp.username, pp.avatar_path, pp.last_seen,
         pm.last_read_at, pm.last_delivered_at,
         case when pp.id is null then false else is_blocked_between(auth.uid(), pp.id) end
  from members me
  join conversations c on c.id = me.conversation_id
  left join lateral (select * from messages x where x.conversation_id = c.id
                     order by x.created_at desc limit 1) lm on true
  left join profiles sp on sp.id = lm.sender_id
  left join members pm on c.type = 'direct' and pm.conversation_id = c.id and pm.user_id <> auth.uid()
  left join profiles pp on pp.id = pm.user_id
  where me.user_id = auth.uid()
    and (c.type <> 'direct' or lm.id is not null or c.created_by = auth.uid())
  order by c.last_message_at desc
  limit 500;
$$;

create or replace function public.search_public(q text)
returns table (id uuid, type text, title text, description text, avatar_path text,
               member_count int, joined boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.type, c.title, c.description, c.avatar_path,
         (select count(*)::int from members m where m.conversation_id = c.id),
         exists (select 1 from members m where m.conversation_id = c.id and m.user_id = auth.uid())
  from conversations c
  where auth.uid() is not null and c.is_public and c.type <> 'direct'
    and (btrim(coalesce(q, '')) = '' or c.title ilike '%' || replace(replace(btrim(q), '%', ''), '_', '') || '%')
  order by 6 desc, c.created_at desc
  limit 50;
$$;

create or replace function public.set_phone(p text) returns void
language sql security definer set search_path = public as $$
  update profile_private set phone = nullif(btrim(p), ''), updated_at = now() where user_id = auth.uid();
$$;

-- Удаление собственного аккаунта (сообщения остаются обезличенными).
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  delete from auth.users where id = me;
end $$;

-- Получатели push-уведомления для сообщения (вызывается только Edge Function с service_role).
create or replace function public.push_targets(m uuid)
returns table (token text, lang text, title text, sender text, body text, kind text, direct boolean, conversation_id uuid)
language sql stable security definer set search_path = public as $$
  select t.token, t.lang,
         case when c.type = 'direct' then coalesce(sp.display_name, '') else coalesce(c.title, '') end,
         coalesce(sp.display_name, ''), msg.body, msg.kind, c.type = 'direct', c.id
  from messages msg
  join conversations c on c.id = msg.conversation_id
  join members mb on mb.conversation_id = c.id and mb.user_id is distinct from msg.sender_id
  join device_tokens t on t.user_id = mb.user_id
  left join profiles sp on sp.id = msg.sender_id
  where msg.id = m and msg.deleted_at is null and msg.kind <> 'system'
    and not exists (select 1 from blocks b where b.blocker_id = mb.user_id and b.blocked_id = msg.sender_id);
$$;

-- Функции доступны только вошедшим пользователям.
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
revoke execute on function public.sys_message(uuid, uuid, text) from authenticated;
revoke execute on function public.push_targets(uuid) from authenticated;
revoke execute on function public.handle_new_user() from authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;

-- ------------------------------------------------------------- realtime ---
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.members;

-- -------------------------------------------------------------- storage ---
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/webp']),
       ('media', 'media', false, 20971520, null)
on conflict (id) do nothing;

-- avatars: путь {user_id}/{file}; читать могут все (публичный бакет), писать — только владелец папки
create policy avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- media: путь {conversation_id}/{sender_id}/{file}; доступ только участникам беседы
create policy media_select on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_member(public.try_uuid((storage.foldername(name))[1])));
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media'
              and (storage.foldername(name))[2] = auth.uid()::text
              and public.can_post(public.try_uuid((storage.foldername(name))[1])));
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[2] = auth.uid()::text);
