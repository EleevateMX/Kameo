-- ALUX: apariencia del alux (personalizador 3D de la Alpha 0.4).
--  1) Más tocados: el límite del tocado deja de ser 0–3.
--  2) Vestimenta, accesorio, amuleto, color secundario y tono de piel, en una sola columna.
-- Sólo añade: no borra ni modifica datos existentes. Una versión anterior del juego sigue
-- funcionando con esta base (ignora la columna y recorta el tocado a los cuatro primeros).

alter table characters drop constraint if exists characters_hat_check;
alter table characters add constraint characters_hat_check check (hat between 0 and 31);

alter table characters add column if not exists look jsonb not null default '{}'::jsonb;
