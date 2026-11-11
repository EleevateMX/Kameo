extends Node
## Punto de entrada. El mismo proyecto es cliente y servidor dedicado:
##   Cliente:  se abre normal (o exportado a Web).
##   Servidor: godot --headless --path game -- --server [--port=9080]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		var server: Node = load("res://scripts/server/game_server.gd").new()
		server.name = "GameServer"
		add_child(server)
	else:
		var client: Node = load("res://scripts/client/game_client.gd").new()
		client.name = "GameClient"
		add_child(client)
