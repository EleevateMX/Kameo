extends RefCounted
## Progresión RPG: las mismas fórmulas que la API (packages/shared-contracts/src/rpg.ts), sólo
## para DIBUJAR nivel y barra de experiencia. Las reglas las aplica la API; ver docs/RPG.md.

const MAX_LEVEL := 10
const BASE_HP := 100.0

## Experiencia para pasar del nivel `n` al `n + 1`.
static func xp_to_next(n: int) -> int:
	return 100 + 20 * (n - 1) * (n - 1)


## {level, in_level, to_next} a partir de la experiencia total (to_next = 0 en el nivel máximo).
static func level_info(xp: int) -> Dictionary:
	var level := 1
	var rest := maxi(0, xp)
	while level < MAX_LEVEL and rest >= xp_to_next(level):
		rest -= xp_to_next(level)
		level += 1
	return {"level": level, "in_level": rest, "to_next": xp_to_next(level) if level < MAX_LEVEL else 0}
