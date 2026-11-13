extends Node
## Puesto de Saberes: la tienda de la progresión RPG (docs/RPG.md). Compra de mejoras de
## habilidad y amuletos con Semillas de Jade, gachapón con probabilidades a la vista e
## inventario para equipar. Todo lo decide la API; esto sólo pide y pinta.
##
## Uso:
##     var _shop := ShopPanel.new(); add_child(_shop); _shop.changed.connect(repintar)
##     _shop.refresh()                         # al abrir el panel
##     _shop.fill(cuerpo, crear_boton)         # pinta dentro de un VBoxContainer
##     _shop.command("buy:skill:chispa" | "buy:amulet:<id>" | "gacha" | "equip:<n>" | "unequip")   # (pruebas)

signal changed

const Kit := preload("res://scripts/client/ui/ui_kit.gd")
const Rpg := preload("res://scripts/shared/rpg_def.gd")
const Audio := preload("res://scripts/client/audio.gd")

const RARITY_COLOR := {"common": Color(0.82, 0.86, 0.84), "rare": Color(0.35, 0.72, 1.0), "epic": Color(0.78, 0.5, 1.0), "legendary": Color(1.0, 0.78, 0.25)}

var rpg := {}          # último estado conocido (vista de la API)
var catalog := {}      # lo que vende el puesto (de la API)
var busy := false
var status := ""       # resultado de la última operación, en una frase
var status_ok := true
var last_item := {}    # lo último que se obtuvo (compra o gachapón)

var _pending := ""     # etiqueta de la petición en curso
var _poll := 0.0
var _web := OS.has_feature("web")


func refresh() -> void:
	if catalog.is_empty():
		_request("catalog", "GET", "/api/v1/rpg/catalog", "")
	else:
		_request("me", "GET", "/api/v1/me", "")


func buy(what: String) -> void:
	_request("buy", "POST", "/api/v1/rpg/buy", JSON.stringify({"what": what, "requestId": _uuid()}))


func gacha() -> void:
	_request("gacha", "POST", "/api/v1/rpg/gacha", JSON.stringify({"requestId": _uuid()}))


func equip(item_id: String) -> void:
	_request("equip", "POST", "/api/v1/rpg/equip", JSON.stringify({"itemId": item_id if not item_id.is_empty() else null}))


## Órdenes para las pruebas (el jugador usa los botones).
func command(cmd: String) -> void:
	if cmd.begins_with("buy:"):
		buy(cmd.trim_prefix("buy:"))
	elif cmd == "gacha":
		gacha()
	elif cmd == "unequip":
		equip("")
	elif cmd.begins_with("equip:"):
		var items: Array = rpg.get("items", [])
		var i := cmd.trim_prefix("equip:").to_int()
		if i >= 0 and i < items.size():
			equip(str(items[i].id))
	elif cmd == "refresh":
		refresh()


func info() -> Dictionary:
	return {"busy": busy, "status": status, "ok": status_ok, "rpg": rpg, "catalog": not catalog.is_empty(), "last": last_item}


static func _uuid() -> String:
	var hex := ""
	for i in 16:
		hex += "%02x" % (randi() % 256)
	return "%s-%s-4%s-a%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(13, 3), hex.substr(17, 3), hex.substr(20, 12)]


func _request(tag: String, method: String, url: String, body: String) -> void:
	if busy or not _web:
		return
	busy = true
	_pending = tag
	_poll = 0.15
	var opts := "{method:'%s',credentials:'same-origin',headers:{'content-type':'application/json','x-alux-csrf':'1'}%s}" % [
		method, (",body:" + JSON.stringify(body)) if method != "GET" else ""]
	JavaScriptBridge.eval("(function(){window.ALUX_SHOP='';fetch('%s',%s).then(function(r){return r.text().then(function(t){window.ALUX_SHOP=JSON.stringify({status:r.status,body:t})})})" % [url, opts] +
		".catch(function(e){window.ALUX_SHOP=JSON.stringify({status:0,body:''})})})()", true)
	changed.emit()


func _process(delta: float) -> void:
	if not busy:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.15
	var raw := str(JavaScriptBridge.eval("window.ALUX_SHOP || ''", true))
	if raw.is_empty():
		return
	busy = false
	var res: Variant = JSON.parse_string(raw)
	var code := int(res.get("status", 0)) if res is Dictionary else 0
	var data: Variant = JSON.parse_string(str(res.get("body", ""))) if res is Dictionary else null
	_done(_pending, code, data if data is Dictionary else {})
	changed.emit()


func _done(tag: String, code: int, data: Dictionary) -> void:
	match tag:
		"catalog":
			if code == 200:
				catalog = data
			_request("me", "GET", "/api/v1/me", "")
		"me":
			if code == 200 and data.get("rpg") is Dictionary:
				rpg = data.rpg
		_:
			if code == 200 and data.get("rpg") is Dictionary:
				rpg = data.rpg
				status_ok = true
				var item: Variant = data.get("item")
				match tag:
					"buy":
						last_item = item if item is Dictionary else {}
						status = ("Tuyo: %s" % str(item.name)) if item is Dictionary else "Saber aprendido"
						Audio.play("glifo_restaurado|ui_click", null, -4.0, 0.0)
					"gacha":
						last_item = item if item is Dictionary else {}
						status = "Salió: %s (%s)" % [str(last_item.get("name", "?")), _rarity_name(str(last_item.get("rarity", "common")))]
						Audio.play("corazon_libre|ui_click" if str(last_item.get("rarity", "")) in ["epic", "legendary"] else "glifo_restaurado|ui_click", null, -4.0, 0.0)
					"equip":
						status = "Amuleto equipado" if rpg.get("equipped") != null else "Sin amuleto"
						Audio.play("ui_click", null, 0.0, 0.0)
			else:
				status_ok = false
				status = {402: "No te alcanzan las semillas", 409: "Eso ya lo tienes", 401: "Tu sesión caducó: vuelve a entrar desde el portal"}.get(code, "No se pudo completar (inténtalo de nuevo)")
				Audio.play("ui_error|ui_click", null, 0.0, 0.0)


func _rarity_name(r: String) -> String:
	return {"common": "común", "rare": "raro", "epic": "épico", "legendary": "legendario"}.get(r, r)


func _effect(a: Dictionary) -> String:
	return "+%d %% de %s" % [roundi(float(a.get("bonus", 0.0)) * 100.0), "vida" if str(a.get("stat", "")) == "hp" else "daño"]


func _amulet(id: String) -> Dictionary:
	for a in catalog.get("amulets", []):
		if str(a.id) == id:
			return a
	return {}


## Pinta la tienda dentro de `body`. `make_button(texto, al_pulsar)` crea un botón con el estilo de quien llama.
func fill(body: VBoxContainer, make_button: Callable) -> void:
	var title := Kit.label("PUESTO DE SABERES", 24, Kit.GOLD, Kit.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	if rpg.is_empty() or catalog.is_empty():
		var wait := Kit.label("Abriendo el puesto…" if busy or _web else "El puesto sólo abre dentro del juego en el navegador.", 14, Color(1, 1, 1, 0.7))
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(wait)
		return
	var seeds := int(rpg.get("seeds", 0))
	var stats: Dictionary = rpg.get("stats", {})
	var dmg: Dictionary = stats.get("dmg", {})
	# Cabecera: nivel, experiencia, semillas y lo que valen ahora mismo sus estadísticas
	var head := HBoxContainer.new()
	body.add_child(head)
	var lv := Kit.label("NIVEL %d" % int(rpg.get("level", 1)), 16, Kit.GOLD, Kit.bold_font())
	head.add_child(lv)
	var xp_next := int(rpg.get("xpToNext", 0))
	var xp := Kit.label(("   %d / %d de experiencia" % [int(rpg.get("xpInLevel", 0)), xp_next]) if xp_next > 0 else "   nivel máximo", 13, Color(1, 1, 1, 0.7))
	xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(xp)
	head.add_child(Kit.label("%d semilla%s de jade" % [seeds, "" if seeds == 1 else "s"], 16, Kit.JADE, Kit.bold_font()))
	body.add_child(Kit.label("Vida %d  ·  daño ×%.2f  ·  Chispa ×%.2f  ·  Garras ×%.2f" % [
		int(stats.get("hp", 100)), float(dmg.get("all", 1.0)), float(dmg.get("chispa", 1.0)), float(dmg.get("garras", 1.0))], 12, Color(1, 1, 1, 0.62)))
	if not status.is_empty():
		body.add_child(Kit.label(status, 14, Kit.GOLD if status_ok else Kit.BLOOD.lightened(0.3), Kit.bold_font()))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	_head(list, "Saberes")
	var skills: Dictionary = rpg.get("skills", {})
	for s in catalog.get("skills", []):
		var rank := int(skills.get(str(s.id), 0))
		var costs: Array = s.cost
		var note := "+%d %% de daño de %s (forma %s)" % [roundi(float(s.bonus) * 100.0), str(s.name), str(s.form)]
		if rank >= costs.size():
			_row(list, "%s %s" % [str(s.name), _roman(rank)], note, "APRENDIDO", Kit.JADE, Callable(), make_button)
		else:
			var price := int(costs[rank])
			var what := "skill:%s" % str(s.id)
			_row(list, "%s %s" % [str(s.name), _roman(rank + 1)], note, "Aprender · %d" % price, Kit.GOLD,
				(func() -> void: buy(what)) if seeds >= price else Callable(), make_button)

	_head(list, "Amuletos en venta (se lleva uno puesto)")
	var owned := {}
	for it in rpg.get("items", []):
		owned[str(it.item)] = true
	for a in catalog.get("amulets", []):
		if a.get("price") == null:
			continue
		var price := int(a.price)
		var what := "amulet:%s" % str(a.id)
		var name := "%s  ·  %s" % [str(a.name), _rarity_name(str(a.rarity))]
		if owned.has(str(a.id)):
			_row(list, name, _effect(a), "YA LO TIENES", Color(1, 1, 1, 0.5), Callable(), make_button, RARITY_COLOR.get(str(a.rarity), Color.WHITE))
		else:
			_row(list, name, _effect(a), "Comprar · %d" % price, Kit.GOLD,
				(func() -> void: buy(what)) if seeds >= price else Callable(), make_button, RARITY_COLOR.get(str(a.rarity), Color.WHITE))

	_head(list, "Gachapón de amuletos")
	var g: Dictionary = catalog.get("gacha", {})
	var odds: Dictionary = g.get("odds", {})
	var pity_left := maxi(1, int(g.get("pity", 20)) - int(rpg.get("pity", 0)))
	_row(list, "Una tirada: siempre sale un amuleto",
		"Común %s %%  ·  raro %s %%  ·  épico %s %%  ·  legendario %s %%\nÉpico o mejor garantizado en %d tirada%s como mucho" % [
			_pct(odds.get("common", 0)), _pct(odds.get("rare", 0)), _pct(odds.get("epic", 0)), _pct(odds.get("legendary", 0)),
			pity_left, "" if pity_left == 1 else "s"],
		"Tirar · %d" % int(g.get("cost", 100)), Kit.GOLD, (func() -> void: gacha()) if seeds >= int(g.get("cost", 100)) else Callable(), make_button)

	_head(list, "Tu inventario")
	var items: Array = rpg.get("items", [])
	if items.is_empty():
		list.add_child(Kit.label("Todavía no tienes amuletos. Se consiguen aquí y, más adelante, explorando.", 13, Color(1, 1, 1, 0.6)))
	var equipped: Variant = rpg.get("equipped")
	for it in items:
		var def := _amulet(str(it.item))
		var id := str(it.id)
		var name := "%s  ·  %s" % [str(def.get("name", it.item)), _rarity_name(str(it.rarity))]
		var tint: Color = RARITY_COLOR.get(str(it.rarity), Color.WHITE)
		if equipped != null and str(equipped) == id:
			_row(list, name, _effect(def) + "  ·  PUESTO", "Quitar", Kit.JADE, func() -> void: equip(""), make_button, tint)
		else:
			_row(list, name, _effect(def), "Equipar", Kit.GOLD, func() -> void: equip(id), make_button, tint)
	list.add_child(Kit.label("Las semillas sólo se ganan jugando: purificando, explorando, con misiones y liberando guardianes.", 12, Color(1, 1, 1, 0.55)))


static func _pct(per_mille: Variant) -> String:
	var v := float(per_mille) / 10.0
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


func _head(list: VBoxContainer, text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	list.add_child(gap)
	list.add_child(Kit.label(text.to_upper(), 12, Kit.JADE, Kit.bold_font()))


## Fila: nombre y nota a la izquierda; a la derecha un botón (si se puede) o una etiqueta.
func _row(list: VBoxContainer, left: String, note: String, action: String, color: Color, on_press: Callable, make_button: Callable, name_color := Color.WHITE) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Kit.label(left, 15, name_color, Kit.bold_font()))
	if not note.is_empty():
		col.add_child(Kit.label(note, 12, Color(1, 1, 1, 0.62)))
	row.add_child(col)
	if on_press.is_valid() and not busy:
		var b: Button = make_button.call(action, on_press)
		b.custom_minimum_size = Vector2(150, 34)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
	else:
		var t := Kit.label(action.to_upper(), 12, color if not on_press.is_valid() and action == action.to_upper() else Color(1, 1, 1, 0.45), Kit.bold_font())
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
	list.add_child(row)
