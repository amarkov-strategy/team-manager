-- Team Manager — Supabase schema
--
-- The app stays offline-first: localStorage is the working copy on each
-- device so the dugout still works with no signal. These tables are the
-- durable record and the cross-device sync point — and, unlike the old
-- blob store, they keep every past team and season as queryable rows.
--
-- Ids mirror the ids the app already generates so a restore from a JSON
-- backup maps 1:1 onto these rows.

create table if not exists teams (
  id              bigint primary key,
  name            text not null,
  sport           text,
  league          text,
  season          text,                          -- e.g. '2026 Spring'
  color           text,
  background      text,
  logo            text,                          -- data URL
  innings         integer not null default 4,
  positions       jsonb  not null default '[]',
  sponsor         text,
  sponsor_url     text,
  sponsor_slogan  text,
  sponsor_emoji   text,
  roster          jsonb  not null default '[]',  -- ordered player names
  premium_caps    jsonb  not null default '{}',
  archived        boolean not null default false,
  updated_at      timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

create table if not exists games (
  id              bigint primary key,
  team_id         bigint not null references teams(id) on delete cascade,
  date            date not null,
  opponent        text,
  notes           text,
  innings         integer,                       -- null = fall back to the team default
  colors          jsonb,
  completed_at    timestamptz,
  forced_active   boolean not null default false,
  present         jsonb not null default '[]',
  manual_rotation jsonb not null default '{}',
  rotation_salt   integer not null default 0,
  updated_at      timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

-- One row per player per game: the season history the blob store could
-- never give us.
create table if not exists player_stats (
  game_id     bigint not null references games(id) on delete cascade,
  player      text   not null,
  outs        integer not null default 0,
  assists     integer not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (game_id, player)
);

create index if not exists games_team_date_idx   on games (team_id, date desc);
create index if not exists player_stats_name_idx on player_stats (player);

-- Which team each device opens to. Kept as its own row so switching the
-- current game on the phone follows to the tablet.
create table if not exists app_state (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Row level security
--
-- The anon key ships inside a public page, so it is not a secret. RLS is
-- what actually decides access. These policies are permissive (anyone
-- holding the anon key can read and write) — the same posture as the old
-- hardcoded Pantry id, and fine for a youth team's roster. Swap in
-- Supabase Auth later if this ever needs to be locked down.
-- ---------------------------------------------------------------------
alter table teams        enable row level security;
alter table games        enable row level security;
alter table player_stats enable row level security;
alter table app_state    enable row level security;

do $$
declare t text;
begin
  foreach t in array array['teams','games','player_stats','app_state'] loop
    execute format('drop policy if exists anon_all on %I', t);
    execute format(
      'create policy anon_all on %I for all to anon using (true) with check (true)', t);
  end loop;
end $$;

-- Useful once a few seasons are in:
--   select player, sum(outs) as outs, sum(assists) as assists
--     from player_stats ps
--     join games g on g.id = ps.game_id
--     join teams t on t.id = g.team_id
--    where t.season = '2026 Spring'
--    group by player order by outs desc;
