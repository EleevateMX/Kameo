extends RefCounted
## Combate mínimo del mundo abierto: números compartidos por el servidor de zonas (que decide) y
## el cliente (que sólo los muestra). NO es el combate de la mazmorra (combat_def.gd / combat.gd):
## aquí hay un único ataque, criaturas sencillas y purificación. Para crecer: añadir tipos a
## CREATURES, habilidades a un diccionario como ATTACK y misiones a MISSIONS.
##
## Criaturas originales del monte bajo yucateco tocadas por el Silencio (nombres provisionales):
##   zarza      «Zarza errante»: una bola de monte espinoso que rueda tras el caminante
##   henequen   «Henequén bravo»: una mata de henequén que se desarraigó y barre con sus pencas

const MAX_HP := 100.0              # vida del alux si el ticket no trae `rpg.hp`
const HP_REGEN := 4.0              # por segundo, tras HP_REGEN_DELAY sin recibir daño
const HP_REGEN_DELAY := 5.0
const HP_REGEN_SAFE := 20.0        # por segundo dentro de una zona segura
const DOWN_TIME := 3.5             # segundos caído antes de reaparecer en la zona segura más cercana
const RESPAWN_INVULN := 2.5

## Ataque básico del alux: una chispa de jade instantánea al primer enemigo dentro del cono.
const ATTACK := {"name": "Chispa de jade", "dmg": 12.0, "range": 6.5, "arc": 1.2, "cd": 0.45}
const ATTACK_CD_TICKS := 9         # 0.45 s a 20 pasos por segundo
const PURIFY_RANGE := 3.0
const PURIFY_HEAL := 15.0
const WEAK_TIME := 6.0             # segundos que una criatura débil espera a ser purificada
const WEAK_RECOVER := 0.6          # si nadie la purifica, vuelve con esta fracción de su vida
const LEASH := 20.0                # no se aleja más que esto de su sitio
const RESPAWN := 45.0              # segundos hasta reaparecer (ALUX_WILD_RESPAWN lo cambia)
const RESPAWN_CLEAR_R := 10.0      # no reaparece con un alux encima…
const RESPAWN_WAIT_MAX := 30.0     # …salvo que lleve esperando esto
const CREDIT_TIME := 20.0          # quien la golpeó en los últimos segundos cobra la recompensa
const CREDIT_R := 30.0             # …si sigue cerca

## Estados, en el orden en que viajan por la red (índice en esta lista)
const STATES: Array[String] = ["idle", "chase", "windup", "recover", "weak", "return"]

const CREATURES := {
	"zarza": {
		"name": "Zarza errante", "hp": 40.0, "speed": 4.3, "radius": 0.6, "height": 1.1,
		"aggro": 9.0, "range": 1.7, "windup": 0.55, "recover": 0.9, "dmg": 9.0, "hit_radius": 1.5, "reach": 1.0,
		"purify_at": 0.4,
	},
	"henequen": {
		"name": "Henequén bravo", "hp": 70.0, "speed": 2.5, "radius": 0.8, "height": 1.7,
		"aggro": 8.0, "range": 2.1, "windup": 0.9, "recover": 1.2, "dmg": 16.0, "hit_radius": 2.6, "reach": 0.0,
		"purify_at": 0.4,
	},
}

## Misiones del mundo abierto. `id` es también la clave de la recompensa `mission` en la API.
const MISSIONS := {
	"camino_motul:recado": {
		"name": "El recado de la cordelera", "giver": "Rosario, la cordelera", "purify": 3,
		"goal": "camino_motul:cartel_motul",
		"offer": "«El Silencio se metió en el monte y ya nadie de Motul viene por mis sogas. Ábreme el camino: purifica a tres criaturas y lleva mi recado hasta el cartel de la entrada.»",
		"steps": ["Purifica criaturas del camino", "Llega al cartel de Motul"],
	},
}
const MISSION := "camino_motul:recado"
