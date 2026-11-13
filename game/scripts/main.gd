extends Node
## Punto de entrada. El mismo proyecto es cliente y servidor dedicado:
##   Cliente:  se abre normal (o exportado a Web).
##   Servidor: godot --headless --path game -- --server [--port=9080]
##   Servidor de zonas sociales (otro proceso): godot --headless --path game -- --zone [--port=9081]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--zone" in args:
		var zone: Node = load("res://scripts/server/zone_server.gd").new()
		zone.name = "ZoneServer"
		add_child(zone)
	elif "--server" in args or OS.has_feature("dedicated_server"):
		var server: Node = load("res://scripts/server/game_server.gd").new()
		server.name = "GameServer"
		add_child(server)
	elif OS.has_feature("web") and str(JavaScriptBridge.eval("(window.ALUX && window.ALUX.mode) || ''")) == "plaza":
		# La plaza social: otro cliente, más pequeño, contra el servidor de zonas
		var plaza: Node = load("res://scripts/client/zone_client.gd").new()
		plaza.name = "ZoneClient"
		add_child(plaza)
	else:
		var client: Node = load("res://scripts/client/game_client.gd").new()
		client.name = "GameClient"
		add_child(client)
