extends RefCounted
## Datos narrativos compartidos por cliente y servidor: capítulo, personajes, diálogos,
## objetivos y guiones de las cinemáticas hechas dentro del motor.
##
## El servidor sólo usa de aquí lo que afecta al estado compartido (quién es cada personaje,
## dónde está y hasta dónde llega su voz). Los textos y las cámaras son presentación del cliente.
## Biblia narrativa: docs/STORY_BIBLE.md · Cinemáticas: docs/CINEMATICS.md

const CHAPTER := {"n": 1, "title": "El Claro de los Aluxes", "roman": "I"}

## Banderas del progreso narrativo de la sala (viajan en el estado del mundo).
const F_TALKED := 1          # alguien del grupo ya habló con Chiich Yaxché
const F_FREED := 2           # Nojoch Tuunich recordó quién es (lo decide el servidor)
const F_CLUE := 4            # el guardián ya señaló el camino del Cenote

## Personajes con los que se puede hablar. `pos` en el plano (x, z); `range` en metros.
const NPCS := {
	"yaxche": {
		"name": "Chiich Yaxché", "title": "La abuela del claro",
		"pos": Vector2(-5.2, 1.2), "yaw": 1.2, "range": 3.0, "color": "#bfeee0",
	},
	# Sólo se puede hablar con él una vez liberado: se queda de guardián en la explanada
	"nojoch": {
		"name": "Nojoch Tuunich", "title": "El guardián que recordó",
		"pos": Vector2(15.5, 0.0), "yaw": -1.5708, "range": 4.6, "color": "#9df0c8", "needs": F_FREED,
	},
}

## Diálogos por personaje y momento de la historia. Cada línea: [quién, texto].
## Momentos: "llamado" (aún no ha hablado nadie), "altares", "emboscada", "liberado", "derrota".
const DIALOGUES := {
	"yaxche": {
		"llamado": [
			["yaxche", "¡Por fin despiertas, muñeco de barro! Tres noches llamándote y tú, roncando."],
			["yaxche", "Escucha la selva. ¿Oyes algo? Exacto: nada. Ni un grillo. Eso no es paz, es el Silencio."],
			["yaxche", "El Silencio hace olvidar. A mis guardianes de piedra ya se les olvidó a quién cuidan… y cerraron el santuario por dentro."],
			["yaxche", "Dentro duerme la primera pluma de Kukulkán. Sin ella, el claro se apaga."],
			["yaxche", "El sello sólo cede si cada alux pisa un altar al mismo tiempo. Búscalos: brillan en tu brújula."],
			["yaxche", "Y no vayas solo de valiente. Balam, el jaguar, camina contigo: llámalo con el 2 cuando haga falta garra, y vuelve a ser alux con el 1."],
			["yaxche", "Si te lastiman, toca el brasero. Y a las criaturas débiles no las rompas: tócalas con F y recordarán quiénes eran."],
			["yaxche", "Anda. Y no me pises las raíces."],
		],
		"altares": [
			["yaxche", "¿Sigues aquí? Los altares no se van a pisar solos."],
			["yaxche", "Un alux en cada altar, todos a la vez. Y cuando el sello caiga, prepárense: lo que despierte no va a estar de buen humor."],
		],
		"emboscada": [
			["yaxche", "¡No es momento de platicar! ¡Los Olvidados despertaron!"],
			["yaxche", "Debilítalos y devuélveles la memoria con F. Si cae todo el grupo, el santuario se cierra otra vez."],
		],
		"derrota": [
			["yaxche", "Ya, ya. Hasta a los jaguares los revuelcan de vez en cuando."],
			["yaxche", "Caliéntense en el brasero y vuelvan a los altares. El Silencio no se cansa; ustedes tampoco."],
		],
		"liberado": [
			["yaxche", "¿Lo oyes? Un grillo. Uno solo, desafinado… pero ya es un comienzo."],
			["yaxche", "El santuario respira de nuevo. Lo que guardaba, sin embargo, pesa más de lo que parece."],
			["yaxche", "El agua del cenote sigue oscura. Ahí abajo hay alguien que también olvidó su nombre. Pronto tendrán que bajar."],
		],
		"guardian": [
			["yaxche", "¿Oyeron eso? Piedra arrastrándose. Nojoch Tuunich despertó… y no se acuerda ni de mí."],
			["yaxche", "No lo rompan: no se puede, y además es mi amigo. Devuélvanle la memoria. Glifo a glifo."],
		],
		"recordo": [
			["yaxche", "Miren nada más. El viejo Nojoch, de rodillas y con musgo nuevo. Ya era hora."],
			["yaxche", "Les dio la Pluma de Jade. No la pierdan: a esa pluma la llama el agua del cenote."],
		],
	},
	# Nojoch Tuunich, ya liberado. "pista": la primera vez (señala el Cenote); "despues": el resto.
	"nojoch": {
		"pista": [
			["nojoch", "…Recuerdo. Recuerdo el nombre de cada piedra de este claro."],
			["nojoch", "Recuerdo también por qué dormía: para no oír lo que sube del cenote."],
			["nojoch", "La pluma que les di no es mía. Es de Kukulkán, y tira hacia el agua. Síganla."],
			["nojoch", "Abajo hay otro guardián. Él no olvidó: a él lo hicieron callar."],
		],
		"despues": [
			["nojoch", "El cenote, pequeños. La pluma ya sabe el camino."],
			["nojoch", "Yo cuido el claro. Ustedes, cuiden de recordar."],
		],
	},
}

## Guiones de cinemáticas dentro del motor. Cada plano:
##   dur       segundos
##   from/to   cámara al empezar y al terminar el plano: [posición, punto al que mira]
##   fov       campo de visión (opcional, 62 por defecto)
##   who/text  subtítulo (opcional)
##   sound     efecto al empezar el plano (opcional)
##   title     rótulo grande (opcional)
##   hold_gate el portal del santuario sigue sellado durante este plano (se abre en el siguiente)
##   boss      cómo se ve el guardián en este plano (sólo presentación; el servidor no se entera):
##             {anim, at (segundo de la animación en que empieza), speed, look (fase con la que se
##             pinta: ojos, vetas y glifos), glow [de, a] (brillo de las vetas a lo largo del plano)}
##   feather   la Pluma de Jade se ve en este plano (true) o todavía no (false)
##   motes     color de las motas que se desprenden del guardián (el Silencio que se va)
##   video     id de un vídeo que sustituye al plano si el navegador lo tiene listo (opcional).
##             El plano del motor corre igual por debajo: es lo que se ve si el vídeo falta o falla.
##             Los archivos y su manifiesto están en game/web/static/video (docs/CINEMATICS.md).
const CUTSCENES := {
	## «El sello cede»: compartida. La empieza el servidor cuando el grupo abre el santuario por
	## primera vez; mientras dura, la sala está en pausa. Se omite por mayoría. 10 s en tres planos.
	"sello": {
		"title": "El sello cede", "shared": true,
		"shots": [
			# 1. La barrera reacciona: del altar hacia el portal sellado
			{"dur": 3.0, "from": [Vector3(15.6, 0.9, -8.0), Vector3(22.5, 2.4, -0.4)], "to": [Vector3(16.4, 1.3, -4.2), Vector3(26.0, 2.8, 0.0)],
				"text": "Cada alux en su altar…", "sound": "objetivo", "video": "sello_1", "hold_gate": true},
			# 2. El sello se rompe: el portal se abre
			{"dur": 4.0, "from": [Vector3(15.5, 3.2, 4.0), Vector3(26, 3.2, 0)], "to": [Vector3(17.5, 2.6, 2.2), Vector3(27, 3.8, 0)],
				"text": "…y el sello cede.", "sound": "santuario_abre", "video": "sello_2"},
			# 3. Algo despierta: hacia el cristal del interior
			{"dur": 3.0, "from": [Vector3(20.4, 2.1, 0.0), Vector3(28.0, 1.5, 0.0)], "to": [Vector3(24.6, 1.8, 0.6), Vector3(28.0, 1.7, 0.0)],
				"text": "Pero quienes lo cuidaban ya no recuerdan a quién. ¡Los Olvidados despiertan!", "sound": "enemigo_aviso", "video": "sello_3"},
		],
	},
	## «El despertar de Nojoch Tuunich»: compartida. La empieza el servidor la primera vez que el
	## grupo entra al patio con la emboscada superada. 16 s en cuatro planos. Termina con el
	## guardián en pie frente al portal: exactamente donde empieza el combate.
	"despertar": {
		"title": "El despertar de Nojoch Tuunich", "shared": true,
		"shots": [
			# 1. El patio en silencio: desde el portal, el coloso sentado al fondo
			{"dur": 4.0, "from": [Vector3(22.4, 2.0, 0.9), Vector3(31.6, 2.3, 0.0)], "to": [Vector3(24.6, 2.1, 0.7), Vector3(31.6, 2.5, 0.0)],
				"text": "Al fondo del patio, algo duerme desde antes que la selva.", "sound": "cine_patio_silencio", "video": "despertar_1",
				"boss": {"anim": "Sleep", "at": 0.0, "speed": 1.0, "look": 0, "glow": [0.15, 0.3]}},
			# 2. Las grietas: el Silencio le recorre el pecho
			{"dur": 4.0, "from": [Vector3(29.0, 2.2, 1.2), Vector3(31.6, 2.3, 0.0)], "to": [Vector3(29.5, 2.5, 0.5), Vector3(31.6, 2.6, 0.0)],
				"text": "El Silencio se le metió en las grietas.", "sound": "cine_grietas", "video": "despertar_2",
				"boss": {"anim": "Sleep", "at": 4.0, "speed": 1.0, "look": 0, "glow": [0.3, 2.4]}},
			# 3. Los ojos: se encienden en magenta
			{"dur": 4.0, "from": [Vector3(29.6, 3.5, -1.1), Vector3(31.7, 3.25, 0.0)], "to": [Vector3(29.9, 3.5, -0.7), Vector3(31.6, 3.5, 0.0)],
				"text": "Nojoch Tuunich abre los ojos… y no reconoce a nadie.", "sound": "cine_ojos", "video": "despertar_3",
				"boss": {"anim": "Awaken", "at": 0.0, "speed": 0.3, "look": 1, "glow": [1.8, 1.8]}},
			# 4. En pie: contrapicado desde el portal; acaba erguido, de cara al grupo
			{"dur": 4.0, "from": [Vector3(23.4, 1.5, -2.6), Vector3(30.8, 2.6, 0.2)], "to": [Vector3(24.2, 1.7, -1.6), Vector3(31.4, 3.1, 0.0)],
				"title": "Nojoch Tuunich  ·  El Guardián Dormido", "text": "", "sound": "cine_en_pie", "video": "despertar_4",
				"boss": {"anim": "Awaken", "at": 1.2, "speed": 0.55, "look": 1, "glow": [1.8, 1.7]}},
		],
	},
	## «La liberación de Nojoch Tuunich»: compartida. La empieza el servidor cuando el contacto
	## del ritual se completa. 12 s en tres planos, en la explanada. No aparece ningún alux: la
	## pluma se entrega hacia la cámara, que es el grupo. Termina como queda el juego: el guardián
	## de rodillas, sereno, con la Pluma de Jade flotando ante él.
	"liberacion": {
		"title": "La liberación de Nojoch Tuunich", "shared": true,
		"shots": [
			# 1. El Silencio se va: las vetas se apagan y se desprenden motas
			{"dur": 4.0, "from": [Vector3(9.6, 1.8, 4.2), Vector3(15.3, 2.3, 0.0)], "to": [Vector3(10.6, 2.2, 3.0), Vector3(15.3, 2.5, 0.0)],
				"text": "El Silencio lo suelta. Grieta a grieta.", "sound": "cine_silencio_se_va", "video": "liberacion_1",
				"boss": {"anim": "Kneel", "at": 9.0, "speed": 0.0, "look": 3, "glow": [1.4, 0.0]}, "feather": false, "motes": "#ff339c"},
			# 2. La serenidad: el rostro, los ojos de jade
			{"dur": 4.0, "from": [Vector3(12.2, 3.2, -1.3), Vector3(15.0, 3.0, 0.0)], "to": [Vector3(12.7, 3.3, -0.7), Vector3(15.0, 3.1, 0.0)],
				"who": "nojoch", "text": "…Recuerdo. Yo cuidaba este claro.", "sound": "glifo_restaurado", "video": "liberacion_2",
				"boss": {"anim": "Remember", "at": 0.0, "speed": 0.6, "look": 4, "glow": [0.0, 0.0]}, "feather": false},
			# 3. La entrega: la pluma flota de sus manos hacia el grupo
			{"dur": 4.0, "from": [Vector3(9.4, 1.5, -0.9), Vector3(13.2, 2.2, 0.0)], "to": [Vector3(10.6, 1.8, -0.5), Vector3(13.0, 2.2, 0.0)],
				"title": "La Pluma de Jade", "text": "La primera pluma de Kukulkán. Ahora la guardan ustedes.", "sound": "cine_pluma", "video": "liberacion_3",
				"boss": {"anim": "Remember", "at": 2.4, "speed": 0.4, "look": 4, "glow": [0.0, 0.0]}, "feather": true},
		],
	},
	## «El llamado»: introducción del Capítulo I. Local (cada jugador la ve al entrar; no detiene a nadie).
	"llamado": {
		"title": "El llamado", "shared": false,
		"shots": [
			{"dur": 5.0, "from": [Vector3(-30, 26, 34), Vector3(0, 2, 0)], "to": [Vector3(-22, 22, 30), Vector3(0, 2, -4)],
				"title": "Capítulo I  ·  El Claro de los Aluxes", "text": "La selva del Mayab lleva tres noches sin cantar."},
			{"dur": 4.5, "from": [Vector3(-14, 3.5, 24), Vector3(-21, -0.5, 15)], "to": [Vector3(-12, 2.6, 21), Vector3(-21, -0.8, 15)],
				"text": "El agua del cenote amaneció oscura, y nadie se atreve a beberla."},
			{"dur": 5.0, "from": [Vector3(10, 3.0, 7), Vector3(24, 3.0, 0)], "to": [Vector3(14, 2.4, 4), Vector3(26, 3.4, 0)],
				"text": "El santuario de los guardianes se cerró por dentro. Un sello que no es de este claro lo cubre.", "sound": "enemigo_aviso"},
			{"dur": 4.5, "from": [Vector3(0.4, 2.4, 3.6), Vector3(-5.2, 1.25, 1.2)], "to": [Vector3(-2.4, 1.6, 2.5), Vector3(-5.2, 1.15, 1.2)],
				"who": "yaxche", "text": "¡Despierta, alux! La selva te necesita… y yo ya me cansé de gritar.", "sound": "objetivo"},
		],
	},
}


## Fases de una cinemática compartida (las dicta el servidor; viajan en el estado del mundo).
##   PREPARING  la sala ya está en pausa; cada cliente funde a negro y avisa de si tiene el vídeo
##   PLAYING    todos la ven; se puede votar para omitirla
##   RESUMING   terminó: unos instantes más de pausa mientras cada cliente vuelve al juego
const CINE_NONE := 0
const CINE_PREPARING := 1
const CINE_PLAYING := 2
const CINE_RESUMING := 3
const CINE_PREP_MAX := 5.0      # espera máxima a que los clientes estén listos
const CINE_RESUME := 1.0        # pausa de cortesía al terminar (nadie recibe daño)


## Ids de todos los vídeos que usan las cinemáticas (para precargarlos).
static func video_ids() -> Array:
	var ids := []
	for id in CUTSCENES:
		for shot in CUTSCENES[id].shots:
			if shot.has("video") and not ids.has(shot.video):
				ids.append(shot.video)
	return ids


## Ids de los vídeos de una cinemática.
static func cutscene_videos(id: String) -> Array:
	var ids := []
	for shot in CUTSCENES.get(id, {}).get("shots", []):
		if shot.has("video"):
			ids.append(shot.video)
	return ids


## Duración total de una cinemática, en segundos (0 si no existe).
static func cutscene_length(id: String) -> float:
	var total := 0.0
	for shot in CUTSCENES.get(id, {}).get("shots", []):
		total += float(shot.get("dur", 0.0))
	return total


## Votos necesarios para omitir una cinemática compartida: la mayoría de los conectados
## (1 de 1, 2 de 2, 2 de 3, 3 de 4).
static func skip_votes_needed(connected: int) -> int:
	return maxi(1, connected / 2 + 1)


## Momento de la historia según el estado de la sala (para elegir diálogo y objetivo).
static func moment(flags: int, encounter: int) -> String:
	match encounter:
		1:
			return "emboscada"
		2:
			return "liberado"
		3:
			return "derrota"
	return "altares" if (flags & F_TALKED) != 0 else "llamado"


## `boss_phase`: fase del guardián (BossDef), para que la abuela comente lo que está pasando.
static func dialogue(npc: String, flags: int, encounter: int, boss_phase := 0) -> Array:
	var by_moment: Dictionary = DIALOGUES.get(npc, {})
	if npc == "nojoch":
		return by_moment.get("despues" if (flags & F_CLUE) != 0 else "pista", [])
	if (flags & F_FREED) != 0:
		return by_moment.get("recordo", [])
	if encounter == 2 and boss_phase >= 1 and boss_phase <= 3:
		return by_moment.get("guardian", [])
	return by_moment.get(moment(flags, encounter), [])


static func npc_pos(npc: String) -> Vector2:
	return NPCS[npc].pos
