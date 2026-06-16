-- ============================================================
-- CASHCLUB — Supabase Schema
-- Execute no SQL Editor do Supabase na ordem abaixo
-- ============================================================

-- 1. EXTENSÕES
create extension if not exists "uuid-ossp";

-- ============================================================
-- 2. TABELAS
-- ============================================================

-- Perfis de usuário (espelha auth.users)
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null,
  full_name     text,
  plan          text not null default 'free' check (plan in ('free','starter','pro','vip')),
  plan_started_at timestamptz,
  plan_expires_at timestamptz,
  kiwify_order_id text,
  starter_leagues text[] default '{}',   -- Ligas escolhidas pelo Starter (max 2)
  is_admin      boolean not null default false,
  avatar_url    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Ligas disponíveis na plataforma
create table public.leagues (
  id          text primary key,           -- ex: 'premier-league'
  name        text not null,
  category    text not null check (category in ('football','basketball','baseball','tennis','esports')),
  logo_url    text,                        -- URL do logo oficial
  color       text default '#1AFF6B',
  plan_access text[] not null default '{pro,vip}',  -- planos com acesso
  sort_order  int default 0,
  active      boolean default true
);

-- Analistas
create table public of.analysts (
  id         uuid primary key default uuid_generate_v4(),
  name       text not null,
  handle     text unique not null,        -- @handle
  avatar_url text,
  bio        text,
  leagues    text[],                      -- ligas cobertas
  win_rate   numeric(5,2) default 0,
  active     boolean default true,
  created_at timestamptz default now()
);

-- Sinais / Tips
create table public.signals (
  id            uuid primary key default uuid_generate_v4(),
  league_id     text not null references public.leagues(id),
  analyst_id    uuid references public.analysts(id),
  match_name    text not null,             -- ex: "Arsenal vs Chelsea"
  market        text not null,             -- ex: "Ambas Marcam - Sim"
  odd           numeric(6,2) not null,
  stake         int not null check (stake between 1 and 10),  -- unidades
  analysis      text,
  status        text not null default 'pending' check (status in ('pending','green','red','void')),
  match_date    timestamptz not null,
  published_at  timestamptz not null default now(),
  result_at     timestamptz,
  profit_units  numeric(6,2),             -- calculado ao marcar resultado
  plan_required text not null default 'starter' check (plan_required in ('starter','pro','vip')),
  vip_early_access_until timestamptz,     -- VIP vê antes deste timestamp
  created_by    uuid references auth.users(id),
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- Histórico de ROI por membro
create table public.member_roi (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  signal_id   uuid not null references public.signals(id) on delete cascade,
  profit_units numeric(6,2) not null default 0,
  created_at  timestamptz default now(),
  unique(user_id, signal_id)
);

-- Notificações
create table public.notifications (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade,  -- null = todos
  title       text not null,
  body        text,
  type        text default 'signal' check (type in ('signal','result','system')),
  read        boolean default false,
  signal_id   uuid references public.signals(id),
  created_at  timestamptz default now()
);

-- ============================================================
-- 3. CORRIGIR TYPO (analysts estava com "of." por engano)
-- ============================================================
-- A tabela correta é public.analysts conforme criada abaixo:
drop table if exists public.analysts;  -- limpa o erro acima caso tenha rodado

create table public.analysts (
  id         uuid primary key default uuid_generate_v4(),
  name       text not null,
  handle     text unique not null,
  avatar_url text,
  bio        text,
  leagues    text[],
  win_rate   numeric(5,2) default 0,
  active     boolean default true,
  created_at timestamptz default now()
);

-- ============================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles      enable row level security;
alter table public.leagues        enable row level security;
alter table public.analysts       enable row level security;
alter table public.signals        enable row level security;
alter table public.member_roi     enable row level security;
alter table public.notifications  enable row level security;

-- PROFILES
create policy "Usuário lê próprio perfil"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Admin lê todos perfis"
  on public.profiles for select
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

create policy "Usuário atualiza próprio perfil"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Admin gerencia todos perfis"
  on public.profiles for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- LEAGUES (leitura pública)
create policy "Leagues são públicas"
  on public.leagues for select
  using (true);

create policy "Admin gerencia leagues"
  on public.leagues for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- ANALYSTS (leitura pública)
create policy "Analysts são públicos"
  on public.analysts for select
  using (true);

create policy "Admin gerencia analysts"
  on public.analysts for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- SIGNALS — lógica de acesso por plano
create policy "Sinais: membro acessa conforme plano"
  on public.signals for select
  using (
    auth.uid() is not null
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
      and (
        -- admin vê tudo
        p.is_admin = true
        or
        -- VIP: vê tudo, inclusive antecipado
        p.plan = 'vip'
        or
        -- Pro: vê futebol, NBA, MLB (não esports/tennis antecipado)
        (p.plan = 'pro' and (
          select category from public.leagues l where l.id = signals.league_id
        ) in ('football','basketball','baseball')
        and (signals.vip_early_access_until is null or signals.vip_early_access_until < now()))
        or
        -- Starter: vê apenas ligas escolhidas
        (p.plan = 'starter' and signals.league_id = any(p.starter_leagues)
        and (signals.vip_early_access_until is null or signals.vip_early_access_until < now()))
      )
    )
  );

create policy "Admin gerencia sinais"
  on public.signals for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- MEMBER ROI
create policy "Membro vê próprio ROI"
  on public.member_roi for select
  using (auth.uid() = user_id);

create policy "Sistema insere ROI"
  on public.member_roi for insert
  with check (auth.uid() = user_id);

-- NOTIFICATIONS
create policy "Membro vê próprias notificações e globais"
  on public.notifications for select
  using (user_id = auth.uid() or user_id is null);

create policy "Membro marca como lida"
  on public.notifications for update
  using (user_id = auth.uid());

create policy "Admin gerencia notificações"
  on public.notifications for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin = true));

-- ============================================================
-- 5. TRIGGER — criar perfil ao registrar usuário
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- 6. TRIGGER — updated_at automático
-- ============================================================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

create trigger trg_signals_updated_at
  before update on public.signals
  for each row execute procedure public.set_updated_at();

-- ============================================================
-- 7. FUNÇÃO — calcular lucro ao marcar resultado
-- ============================================================
create or replace function public.calculate_signal_profit(
  p_signal_id uuid,
  p_status text
) returns void language plpgsql security definer as $$
declare
  v_signal public.signals%rowtype;
  v_profit  numeric(6,2);
begin
  select * into v_signal from public.signals where id = p_signal_id;

  if p_status = 'green' then
    v_profit := (v_signal.odd - 1) * v_signal.stake;
  elsif p_status = 'red' then
    v_profit := -v_signal.stake;
  else
    v_profit := 0;
  end if;

  update public.signals
  set status = p_status, profit_units = v_profit, result_at = now()
  where id = p_signal_id;
end;
$$;

-- ============================================================
-- 8. SEED — Ligas
-- ============================================================
insert into public.leagues (id, name, category, logo_url, plan_access, sort_order) values
  ('premier-league',    'Premier League',       'football',   'https://upload.wikimedia.org/wikipedia/en/f/f2/Premier_League_Logo.svg',          '{starter,pro,vip}', 1),
  ('champions-league',  'Champions League',     'football',   'https://upload.wikimedia.org/wikipedia/en/b/bf/UEFA_Champions_League_logo_2.svg',   '{starter,pro,vip}', 2),
  ('la-liga',           'La Liga',              'football',   'https://upload.wikimedia.org/wikipedia/commons/1/13/LaLiga.svg',                   '{starter,pro,vip}', 3),
  ('bundesliga',        'Bundesliga',           'football',   'https://upload.wikimedia.org/wikipedia/en/d/df/Bundesliga_logo_%282017%29.svg',     '{starter,pro,vip}', 4),
  ('serie-a',           'Serie A',              'football',   'https://upload.wikimedia.org/wikipedia/en/e/e1/Serie_A_logo_%282019%29.svg',        '{pro,vip}',         5),
  ('ligue-1',           'Ligue 1',              'football',   'https://upload.wikimedia.org/wikipedia/commons/c/ca/Ligue1_logo_2020.svg',          '{pro,vip}',         6),
  ('brasileirao',       'Brasileirão Série A',  'football',   'https://upload.wikimedia.org/wikipedia/pt/4/42/Brasileir%C3%A3o_S%C3%A9rie_A.png',  '{starter,pro,vip}', 7),
  ('copa-do-brasil',    'Copa do Brasil',       'football',   'https://upload.wikimedia.org/wikipedia/pt/a/a6/Copa_do_Brasil.png',                 '{pro,vip}',         8),
  ('europa-league',     'UEFA Europa League',   'football',   'https://upload.wikimedia.org/wikipedia/en/9/93/UEFA_Europa_League_logo.svg',        '{pro,vip}',         9),
  ('nba',               'NBA',                  'basketball', 'https://upload.wikimedia.org/wikipedia/en/0/03/National_Basketball_Association_logo.svg', '{starter,pro,vip}', 10),
  ('nba-playoffs',      'NBA Playoffs',         'basketball', 'https://upload.wikimedia.org/wikipedia/en/0/03/National_Basketball_Association_logo.svg', '{pro,vip}',    11),
  ('mlb',               'MLB',                  'baseball',   'https://upload.wikimedia.org/wikipedia/en/a/a6/Major_League_Baseball_logo.svg',     '{pro,vip}',         12),
  ('mlb-world-series',  'World Series',         'baseball',   'https://upload.wikimedia.org/wikipedia/en/a/a6/Major_League_Baseball_logo.svg',     '{pro,vip}',         13),
  ('australian-open',   'Australian Open',      'tennis',     'https://upload.wikimedia.org/wikipedia/en/3/3f/Australian_Open_Logo.svg',           '{vip}',             14),
  ('roland-garros',     'Roland Garros',        'tennis',     'https://upload.wikimedia.org/wikipedia/en/a/a3/Roland-Garros_logo.svg',             '{vip}',             15),
  ('wimbledon',         'Wimbledon',            'tennis',     'https://upload.wikimedia.org/wikipedia/commons/6/6b/Wimbledon_Championships_logo.svg', '{vip}',          16),
  ('us-open-tennis',    'US Open',              'tennis',     'https://upload.wikimedia.org/wikipedia/en/e/e8/US_Open_Tennis_2019_Logo.svg',       '{vip}',             17),
  ('atp-masters',       'ATP Masters 1000',     'tennis',     'https://upload.wikimedia.org/wikipedia/en/3/3f/ATP_Tour_logo.svg',                  '{vip}',             18),
  ('cs2',               'CS2',                  'esports',    'https://upload.wikimedia.org/wikipedia/commons/a/ae/CS2_logo_icon.png',             '{vip}',             19),
  ('valorant',          'Valorant',             'esports',    'https://upload.wikimedia.org/wikipedia/en/f/fc/Valorant_logo_-_pink_color_version.svg', '{vip}',         20),
  ('league-of-legends', 'League of Legends',    'esports',    'https://upload.wikimedia.org/wikipedia/commons/d/d8/League_of_legends_LOL_icon.png','{vip}',             21),
  ('dota2',             'DOTA 2',               'esports',    'https://upload.wikimedia.org/wikipedia/commons/d/dc/Dota_2_logo_icon.png',          '{vip}',             22)
on conflict (id) do nothing;
