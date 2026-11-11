-- ALUX: beta privada.
--  1) Jugadores que entran con invitación de tester (provider = 'beta').
--  2) Métricas de cada sesión de juego (rendimiento y calidad gráfica elegida).
-- Sólo añade: no borra ni modifica datos existentes.

alter table players drop constraint if exists players_provider_check;
alter table players add constraint players_provider_check check (provider in ('discord', 'dev', 'beta'));

create table if not exists session_metrics (
  session_id uuid primary key,
  player_id uuid not null references players (id) on delete cascade,
  room text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  quality text not null default '',
  fps_avg real,
  fps_min real,
  ping_avg real,
  ping_max real,
  load_ms integer,
  seconds integer not null default 0,
  data jsonb not null default '{}'::jsonb
);

create index if not exists session_metrics_player_idx on session_metrics (player_id, created_at desc);
create index if not exists session_metrics_created_idx on session_metrics (created_at desc);

alter table session_metrics enable row level security;
