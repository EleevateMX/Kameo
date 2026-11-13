extends RefCounted
## Verificación de tickets de acceso (JWT HS256) emitidos por la API.
## El servidor de juego nunca confía en lo que diga el cliente sobre su
## identidad: sólo en un ticket firmado con el secreto compartido.

static func _b64url_decode(s: String) -> PackedByteArray:
	var t := s.replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	return Marshalls.base64_to_raw(t)


## Devuelve el contenido del ticket, o {} si no es válido. `audience` dice para qué servidor se
## emitió: un ticket de sala no sirve en el servidor de zonas, ni al revés.
static func verify(token: String, secret: String, audience := "alux-game") -> Dictionary:
	if token.length() > 4096 or secret.is_empty():
		return {}
	var parts := token.split(".")
	if parts.size() != 3:
		return {}
	var crypto := Crypto.new()
	var expected := crypto.hmac_digest(
		HashingContext.HASH_SHA256, secret.to_utf8_buffer(), (parts[0] + "." + parts[1]).to_utf8_buffer())
	var given := _b64url_decode(parts[2])
	if given.size() != expected.size() or not crypto.constant_time_compare(expected, given):
		return {}
	var json := JSON.new()
	if json.parse(_b64url_decode(parts[0]).get_string_from_utf8()) != OK:
		return {}
	var header: Variant = json.data
	if typeof(header) != TYPE_DICTIONARY or header.get("alg") != "HS256":
		return {}
	if json.parse(_b64url_decode(parts[1]).get_string_from_utf8()) != OK:
		return {}
	var payload: Variant = json.data
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	var exp: Variant = payload.get("exp")
	if typeof(exp) != TYPE_FLOAT and typeof(exp) != TYPE_INT:
		return {}
	if float(exp) < Time.get_unix_time_from_system():
		return {}
	if payload.get("aud") != audience:
		return {}
	return payload
