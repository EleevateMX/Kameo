-- ALUX: progresión RPG (Alpha 0.5). Nivel, Semillas de Jade, inventario, amuleto equipado,
-- mejoras de habilidad y gachapón. Diseño y contrato: docs/RPG.md.
-- Sólo añade tablas: no borra ni modifica datos existentes. Una versión anterior del juego sigue
-- funcionando con esta base (ignora las tablas nuevas). Los perfiles que ya existen empiezan en
-- nivel 1 sin perder sellos, formas ni progreso.

-- Estado de cada jugador. El nivel no se guarda: sale de la experiencia.
create table if not exists rpg_state (
  player_id uuid primary key references players (id) on delete cascade,
  xp integer not null default 0 check (xp >= 0),
  seeds integer not null default 0 check (seeds >= 0),
  skills jsonb not null default '{}'::jsonb,
  equipped uuid,
  pity integer not null default 0 check (pity >= 0),
  updated_at timestamptz not null default now()
);

-- Inventario: un renglón por objeto (puede haber repetidos).
create table if not exists rpg_items (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references players (id) on delete cascade,
  item text not null,
  rarity text not null check (rarity in ('common', 'rare', 'epic', 'legendary')),
  source text not null,
  created_at timestamptz not null default now()
);
create index if not exists rpg_items_player_idx on rpg_items (player_id);

-- Libro de apuntes: un renglón por movimiento. La clave única por jugador hace que repetir una
-- petición (un reintento, un doble clic, un servidor que vuelve a avisar) no pague dos veces.
create table if not exists rpg_ledger (
  id bigint generated always as identity primary key,
  player_id uuid not null references players (id) on delete cascade,
  kind text not null,
  key text not null,
  xp integer not null default 0,
  seeds integer not null default 0,
  result jsonb,
  item_id uuid,
  created_at timestamptz not null default now(),
  unique (player_id, key)
);
create index if not exists rpg_ledger_daily_idx on rpg_ledger (player_id, kind, created_at);

alter table rpg_state enable row level security;
alter table rpg_items enable row level security;
alter table rpg_ledger enable row level security;
