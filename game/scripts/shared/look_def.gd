extends RefCounted
## Apariencia del alux: catálogos del personalizador.
##
## El índice de cada lista es lo que se guarda en el perfil y lo que viaja por la red; aquí está
## además el nodo o el material del modelo (res://assets/characters/alux.glb) que le corresponde.
## Las listas deben coincidir, en el mismo orden, con las de packages/shared-contracts/src/domain.ts
## (HATS, OUTFITS, ACCESSORIES, AMULETS, ALUX_COLORS, ACCENT_COLORS, SKIN_TONES): lo comprueba
## tests/look-catalog.test.ts.

## Tocados: [nombre, nodos del modelo que se ven]. El cabello va debajo de todos.
const HATS := [
	["Sombrero de palma", ["Hat_Palma", "Hair"]],
	["Penacho", ["Hat_Penacho", "Hair"]],
	["Flor de mayo", ["Hat_Flor", "Hair"]],
	["Sin tocado", ["Hair"]],
	["Diadema de plumas", ["Hat_Plumas", "Hair"]],
	["Pañuelo", ["Hat_Panuelo", "Hair"]],
	["Corona de hojas", ["Hat_Hojas", "Hair"]],
]
const HAT_NODES := ["Hat_Palma", "Hat_Penacho", "Hat_Flor", "Hat_Plumas", "Hat_Panuelo", "Hat_Hojas", "Hair"]

## Vestimenta, accesorios y amuletos: [nombre, prefijo del nodo ("" = nada añadido)].
const OUTFITS := [["Túnica", ""], ["Capa corta", "Outfit_Capa"], ["Faja con flecos", "Outfit_Faja"], ["Bordado", "Outfit_Bordado"]]
const ACCESSORIES := [["Ninguno", ""], ["Morral", "Acc_Morral"], ["Sonaja", "Acc_Sonaja"], ["Caracol", "Acc_Caracol"],
	["Farol de luciérnagas", "Acc_Farol"]]
const AMULETS := [["Ninguno", ""], ["Colgante de jade", "Amu_Jade"], ["Concha", "Amu_Concha"], ["Espejo de obsidiana", "Amu_Obsidiana"],
	["Collar de semillas", "Amu_Semillas"]]

## Color principal (túnica), secundario (ribetes y telas añadidas) y tonos de piel.
const COLORS := ["#2ec4a6", "#e4007c", "#ffd23f", "#ff7a1a", "#19b4d6", "#8f5bd6", "#7ccf4e", "#f25f5c",
	"#fff7ec", "#3f7d5c", "#b3372e", "#31466b"]
const ACCENTS := ["#fff7ec", "#ffd23f", "#e4007c", "#ff7a1a", "#2ec4a6", "#19b4d6", "#8f5bd6", "#7ccf4e", "#b3372e", "#3d2a20"]
const SKINS := ["#a9714b", "#c08a62", "#8c563a", "#6f4530", "#d6a57e"]

## Orden de los campos cuando la apariencia viaja como lista: [vestimenta, accesorio, amuleto, secundario, piel]
const OUTFIT := 0
const ACCESSORY := 1
const AMULET := 2
const ACCENT := 3
const SKIN := 4
const DEFAULT: Array = [0, 0, 0, 0, 0]
const LIMITS: Array = [4, 5, 5, 10, 5]


## Deja una lista válida: lo que falte o se salga del catálogo vuelve a su valor inicial.
static func clean(raw: Variant) -> Array:
	var out: Array = DEFAULT.duplicate()
	if typeof(raw) != TYPE_ARRAY:
		return out
	for i in mini((raw as Array).size(), out.size()):
		var v: Variant = raw[i]
		if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) == floorf(float(v)) and int(v) >= 0 and int(v) < int(LIMITS[i]):
			out[i] = int(v)
	return out
