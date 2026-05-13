extends Node

const SERVER_ADDRESS: String = "127.0.0.1"
var SERVER_PORT: int = 8080
const MAX_PLAYERS : int = 12

var players = {}
var player_info = {
	"nick" : "host",
	"skin" : "blue",
	"team" : "hider"
}

signal player_connected(peer_id, player_info)
signal server_disconnected

var blind_phase_active: bool = false
var blind_phase_end_time: float = 0.0

func _process(_delta):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit(0)
		
func _ready() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.connected_to_server.connect(_on_connected_ok)

func start_host(input_port: int = SERVER_PORT):
	var peer = ENetMultiplayerPeer.new()
	var port = int(input_port)
	if port == 0:
		port = SERVER_PORT
	var error = peer.create_server(port, MAX_PLAYERS)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	
	players[1] = player_info
	player_connected.emit(1, player_info)
	
func join_game(nickname: String, skin_color: String, address: String = SERVER_ADDRESS, input_port: int = SERVER_PORT):
	var peer = ENetMultiplayerPeer.new()
	var port = int(input_port)
	if port == 0:
		port = SERVER_PORT
	var error = peer.create_client(address, port)
	if error:
		return error

	multiplayer.multiplayer_peer = peer
	if !nickname:
		nickname = "Player_" + str(multiplayer.get_unique_id())
	if !skin_color or skin_color.is_empty():
		skin_color = "blue"
	player_info["nick"] = nickname
	player_info["skin"] = skin_color
	player_info["team"] = "hider"
	
func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)
	
func _on_player_connected(id):
	_register_player.rpc_id(id, player_info)
	
@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)
	
func _on_player_disconnected(id):
	players.erase(id)
	
func _on_connection_failed():
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()

@rpc("authority", "reliable")
func apply_blind_to_seekers(duration: float):
	blind_phase_active = true
	blind_phase_end_time = Time.get_ticks_msec() / 1000.0 + duration
	print("Blinding seekers for", duration, "seconds...")

	for id in multiplayer.get_peers():
		var player = get_player_from_peer(id)
		if player and player.team == "seeker":
			player.rpc_id(id, "remote_set_blind_deaf_dumb", true, duration)

	# host local
	var host_player = get_player_from_peer(1)
	if host_player and host_player.team == "seeker":
		host_player.remote_set_blind_deaf_dumb(true, duration)

	await get_tree().create_timer(duration).timeout
	blind_phase_active = false
	print("Blind phase ended")


func get_player_from_peer(peer_id: int) -> Node:
	var level = get_tree().get_current_scene()
	if level == null:
		return null
	var players_container = level.get_node_or_null("PlayersContainer")
	if players_container == null:
		return null
	for child in players_container.get_children():
		if child.get_multiplayer_authority() == peer_id:
			return child
	return null

@rpc("any_peer", "reliable")
func _set_player_blind(state: bool, duration: float):
	var player = get_tree().get_current_scene().get_node_or_null("PlayersContainer")
	if player and player.has_method("remote_set_blind_deaf_dumb"):
		player.remote_set_blind_deaf_dumb(state, duration)

func check_and_blind_if_needed(player_node: Node):
	if not blind_phase_active:
		return
	var remaining = blind_phase_end_time - Time.get_ticks_msec() / 1000.0
	if remaining > 0:
		print("New seeker joined during blind window, blinding for", remaining, "s")
		player_node.rpc_id(player_node.get_multiplayer_authority(), "remote_set_blind_deaf_dumb", true, remaining)
