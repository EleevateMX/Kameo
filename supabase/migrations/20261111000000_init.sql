-- ALUX: esquema inicial.
-- Sólo la API (conexión directa / rol de servicio) lee y escribe estas tablas.
-- Se activa RLS sin políticas para que las claves públicas de Supabase
-- (anon / authenticated) no puedan tocar nada.

create table if not exists players (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('discord', 'dev')),
  provider_id text not null,
  display_name text not null,
  avatar_url text,
  created_at timestamptz not null default now(),
  last_login_at timestamptz not null default now(),
  unique (provider, provider_id)
);

create table if not exists characters (
  player_id uuid primary key references players (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 20),
  color text not null default '#2ec4a6' check (color ~ '^#[0-9a-fA-F]{6}$'),
  hat smallint not null default 0 check (hat between 0 and 3),
  updated_at timestamptz not null default now()
);

create table if not exists unlocks (
  player_id uuid not null references players (id) on delete cascade,
  form text not null,
  source text not null default 'inicial',
  unlocked_at timestamptz not null default now(),
  primary key (player_id, form)
);

create table if not exists inventory (
  player_id uuid not null references players (id) on delete cascade,
  item text not null,
  quantity integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (player_id, item)
);

-- Salas / grupos de hasta 4 aluxes
create table if not exists parties (
  code text primary key check (code ~ '^[A-Z0-9]{4,12}$'),
  visibility text not null check (visibility in ('private', 'public')),
  owner_id uuid not null references players (id) on delete cascade,
  server_id text not null,
  status text not null default 'open' check (status in ('open', 'closed')),
  gate_open boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists parties_open_idx on parties (status, visibility);

create table if not exists party_members (
  party_code text not null references parties (code) on delete cascade,
  player_id uuid not null references players (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (party_code, player_id)
);

-- Tickets de acceso emitidos (auditoría)
create table if not exists sessions (
  jti text primary key,
  player_id uuid not null references players (id) on delete cascade,
  party_code text not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists sessions_player_idx on sessions (player_id, issued_at desc);

create table if not exists quest_progress (
  player_id uuid not null references players (id) on delete cascade,
  quest text not null,
  status text not null check (status in ('in_progress', 'completed')),
  updated_at timestamptz not null default now(),
  primary key (player_id, quest)
);

-- Libro de recompensas: cada fila es una entrega. idempotency_key impide duplicados
-- aunque el servidor de juego reintente la misma petición.
create table if not exists rewards_ledger (
  id bigint generated always as identity primary key,
  player_id uuid not null references players (id) on delete cascade,
  reward text not null,
  source text not null,
  idempotency_key text not null unique,
  granted_at timestamptz not null default now()
);
create index if not exists rewards_player_idx on rewards_ledger (player_id);

create table if not exists save_checkpoints (
  player_id uuid not null references players (id) on delete cascade,
  chapter text not null,
  checkpoint text not null,
  data jsonb not null default '{}'::jsonb,
  saved_at timestamptz not null default now(),
  primary key (player_id, chapter)
);

alter table players enable row level security;
alter table characters enable row level security;
alter table unlocks enable row level security;
alter table inventory enable row level security;
alter table parties enable row level security;
alter table party_members enable row level security;
alter table sessions enable row level security;
alter table quest_progress enable row level security;
alter table rewards_ledger enable row level security;
alter table save_checkpoints enable row level security;
