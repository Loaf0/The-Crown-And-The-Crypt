extends Node3D

@onready var seeker_spawn = $SeekerSpawn
@onready var hider_spawn = $HiderSpawn

@onready var players_container: Node3D = $PlayersContainer
@onready var menu: Control = $UI
@export var player_scene: PackedScene

@onready var game_timer = $GameTime
@onready var game_timer_label = $UI/Timer
@onready var blind_timer = $BlindTimer
@export var game_length = 330.0
@export var blind_length = 20.0
@export var starting_seekers = 1

@onready var blind_length_input = $UI/HostCommands/VFlowContainer/HBoxContainer/BlindLength
@onready var game_length_input = $UI/HostCommands/VFlowContainer/HBoxContainer2/GameLength2
@onready var seekers_input = $UI/HostCommands/VFlowContainer/HBoxContainer3/Seekers

# UI elements
@onready var player_list = $"UI/Player List"
@onready var player_list_label = $"UI/Player List/List"

# Hiders Left
@onready var hiders_left: Label = $UI/HidersLeft

var current_hiders_left = 0

# multiplayer chat
@onready var message: LineEdit = $UI/Chat/HBoxContainer/Message
@onready var send: Button = $UI/Chat/HBoxContainer/Send
@onready var chat: TextEdit = $UI/Chat/Chat
@onready var multiplayer_chat = $UI/Chat
var chat_visible = false
var local_id

func _ready():
	multiplayer_chat.modulate.a = 0.5
	multiplayer_chat.set_process_input(true)
	local_id = multiplayer.get_unique_id()

	if not multiplayer.is_server():
		return
		
	Network.connect("player_connected", Callable(self, "_on_player_connected"))
	multiplayer.peer_disconnected.connect(_remove_player)
	
	if Settings.hosting:
		_on_host_pressed()
	else:
		_on_join_pressed()

func _process(_delta: float) -> void:
	if Input.is_action_pressed("show_player_list"):
		player_list.show()
	else:
		player_list.hide()

func _physics_process(_delta: float) -> void:
	update_timer()
	
	for player in players_container.get_children():
		if player.global_position.y < -50:
			if player.has_method("get_team"):
				var team = player.get_team()
				if team == "hider":
					rpc_id(1, "tag_hider", "server", player.name)
				else:
					_respawn_player(player)

func _respawn_player(player):
	Network.check_and_blind_if_needed(player)
	var team = player.get_team()
	player.velocity = Vector3.ZERO
	player.global_position = get_spawn_point(team)

func _on_player_connected(peer_id, player_info):
	for id in Network.players.keys():
		var player_data = Network.players[id]
		if id != peer_id:
			rpc_id(peer_id, "sync_player_skin", id, player_data["skin"])
			rpc_id(peer_id, "sync_player_name", id, player_data["nick"])
			rpc_id(peer_id, "sync_player_team", id, player_data["team"])
	_add_player(peer_id, player_info)

func _on_host_pressed():
	Network.start_host(Settings.port)
	$UI/HostCommands.show()
	$PlayersContainer/Camera.queue_free()

func _on_join_pressed():
	Network.join_game(Settings.nickname, Settings.color.to_lower(), Settings.ip, int(Settings.port))

func _add_player(id: int, player_info : Dictionary):
	if players_container.has_node(str(id)) or not multiplayer.is_server() or id == 1:
		return

	var player = player_scene.instantiate()
	player.name = str(id)

	var team = player_info["team"]
	player.set_team(team)
	player.position = get_spawn_point(team)
	players_container.add_child(player, true)

	rpc("sync_player_name", id, player_info["nick"])
	rpc("sync_player_skin", id, player_info["skin"])
	rpc("sync_player_position", id, player.position)
	rpc("sync_player_team", id, team)
	
	update_hiders_left()
	update_player_list_label()

func get_spawn_point(team: String) -> Vector3:
	var base_pos: Vector3
	if team == "seeker":
		base_pos = seeker_spawn.position
	else:
		base_pos = hider_spawn.position

	var radius = 5.0
	var angle = randf() * TAU
	var offset = Vector3(cos(angle), 0, sin(angle)) * randf_range(0, radius)

	return base_pos + offset

	
func _remove_player(id):
	if not multiplayer.is_server() or not players_container.has_node(str(id)):
		return
	var player_node = players_container.get_node(str(id))
	if player_node:
		player_node.queue_free()

@rpc("any_peer", "call_local")
func sync_player_team(id: int, team_name: String):
	if id == 1: return
	var player = players_container.get_node(str(id))
	if player:
		player.set_team(team_name)
		player.position = get_spawn_point(team_name)

		if id == multiplayer.get_unique_id():
			Global.local_player_team = team_name

	if Network.players.has(id):
		Network.players[id]["team"] = team_name

	update_hiders_left()
	update_player_list_label()

@rpc("any_peer", "call_local")
func sync_player_name(id: int, nickname: String):
	if id == 1: return # ignore host
	var player = players_container.get_node(str(id))
	if player:
		player.change_nick(nickname)

@rpc("any_peer", "call_local")
func sync_player_position(id: int, new_position: Vector3):
	var player = players_container.get_node(str(id))
	if player and !player.is_multiplayer_authority():
		player.target_position = new_position

@rpc("any_peer", "call_local")
func sync_player_skin(id: int, skin_name: String):
	if id == 1: return # ignore host
	var player = players_container.get_node(str(id))
	if player:
		player.set_player_skin(skin_name)
		
func _on_quit_pressed() -> void:
	get_tree().quit()
	
# ---------- MULTIPLAYER CHAT ----------
func toggle_chat():
	chat_visible = !chat_visible
	if chat_visible:
		multiplayer_chat.modulate.a = 1.0
		message.grab_focus()
	else:
		multiplayer_chat.modulate.a = 0.5
		message.release_focus()
		get_viewport().set_input_as_handled()

func is_chat_visible() -> bool:
	return chat_visible

func _input(event):
	if event.is_action_pressed("toggle_chat"):
		toggle_chat()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_ENTER:
		if chat_visible and message.has_focus():
			_on_send_pressed()

func _on_send_pressed() -> void:
	var trimmed_message = message.text.strip_edges()
	if trimmed_message == "":
		return # do not send empty messages

	var nick = Network.players[multiplayer.get_unique_id()]["nick"]

	rpc("msg_rpc", nick, trimmed_message)
	message.text = ""
	message.grab_focus()


func _get_random_peer() -> int:
	var peer_ids = []
	for id in Network.players.keys():
		if id != 1:
			peer_ids.append(id)
	
	if peer_ids.size() == 0:
		return -1
	
	return peer_ids[randi() % peer_ids.size()]

@rpc("any_peer", "call_local")
func msg_rpc(nick, msg):
	var new_line = str(nick, " : ", msg)

	var lines = chat.text.split("\n", false)
	lines.append(new_line)

	if lines.size() > 10:
		lines.remove_at(0)

	chat.text = "\n".join(lines)

func _get_random_peers(count: int) -> Array:
	var all_ids := Network.players.keys()
	all_ids = all_ids.filter(func(id): return id != 1)  # Exclude server
	all_ids.shuffle()

	return all_ids.slice(0, min(count, all_ids.size()))

func _on_reset_game():
	if not multiplayer.is_server():
		return

	# Get all player IDs excluding the server (ID 1)
	var all_ids := Network.players.keys()
	all_ids = all_ids.filter(func(id): return id != 1)
	all_ids.shuffle()

	var seeker_ids := all_ids.slice(0, min(starting_seekers, all_ids.size()))
	var hider_ids := all_ids.slice(seeker_ids.size(), all_ids.size())

	for id in seeker_ids:
		Network.players[id]["team"] = "seeker"
		rpc_id(id, "sync_player_team", id, "seeker")
		var nick = Network.players[id]["nick"]
		rpc("msg_rpc", "Server", "Player " + nick + " has been assigned to Seeker!")

	for id in hider_ids:
		Network.players[id]["team"] = "hider"
		rpc_id(id, "sync_player_team", id, "hider")

	# Unblind all players first (just in case from last round)
	for player in players_container.get_children():
		var pid = player.get_multiplayer_authority()
		print("Unblinding player ID:", pid)
		player.rpc_id(pid, "remote_set_blind_deaf_dumb", false)

	update_hiders_left()
	update_player_list_label()

	await get_tree().create_timer(0.5).timeout

	print("Blinding seekers for " + str(blind_length) + " seconds...")
	Network.apply_blind_to_seekers(blind_length)


@rpc("any_peer", "call_local")
func tag_hider(seeker_id: String, hider_id: String):
	if not multiplayer.is_server():
		return
	
	var hider = players_container.get_node_or_null(hider_id)
	if not hider:
		return

	if seeker_id != "server":
		var seeker = players_container.get_node_or_null(seeker_id)
		if not seeker or seeker.team != "seeker":
			return

	if hider.team == "seeker":
		return
	
	hider.team = "seeker"
	hider.position = get_spawn_point("seeker")
	rpc("sync_player_team", int(hider_id), "seeker")
	rpc("msg_rpc", "Server", "Player " + Network.players[int(hider_id)]["nick"] + " is now a Seeker!")
	
	if current_hiders_left == 0:
		_on_seekers_win()
	
	update_hiders_left()
	update_player_list_label()

func update_hiders_left():
	var hiders = 0
	var seekers = 0
	for player in players_container.get_children():
		if player.has_method("get_team"):
			if player.get_team() == "hider":
				hiders += 1
			else:
				seekers += 1

	hiders_left.text = "Hiders : " + str(hiders) + "\nSeekers : " + str(seekers)
	current_hiders_left = hiders

func update_player_list_label():
	var text = ""
	for id in Network.players:
		var player = Network.players[id]
		if id != 1:
			text += "  %s (%s) (%s)\n" % [player["nick"].strip_edges(), player["team"].capitalize(), player["skin"].capitalize()]
	player_list_label.text = text

func _on_recalculate_timeout() -> void:
	update_hiders_left()
	update_player_list_label()

@rpc("call_local")
func start_game_timer(server_start_time: float):
	game_timer.start()
	game_timer.wait_time = game_length
	game_timer.start(server_start_time)
	blind_timer.start(blind_length)


func _on_restart_pressed() -> void:
	if multiplayer.get_unique_id() != 1:
		return

	_on_reset_game()

	game_timer.wait_time = game_length
	game_timer.start()
	rpc("start_game_timer", 0.0)


func _on_game_timer_timeout():
	game_timer.stop()
	
	var winners := []
	for player in players_container.get_children():
		if player.has_method("get_team") and player.get_team() == "hider":
			var id = int(player.name)
			if Network.players.has(id):
				winners.append(Network.players[id]["nick"])
	
	if winners.size() > 0 and multiplayer.is_server():
		rpc("msg_rpc", "Server", "Time's up! Hiders win!")
		rpc("msg_rpc", "Server", "Winners: " + ", ".join(winners))

func _on_seekers_win():
	game_timer.stop()

	var winners := []
	for player in players_container.get_children():
		if player.has_method("get_team") and player.get_team() == "seeker":
			var id = int(player.name)
			if Network.players.has(id):
				winners.append(Network.players[id]["nick"])
		
	if winners.size() > 0 and multiplayer.is_server():
		rpc("msg_rpc", "Server", "All hiders found! Seekers win!")
		rpc("msg_rpc", "Server", "Winners: " + ", ".join(winners))


func update_timer():
	var remaining = int(ceil(game_timer.time_left))
	
	if game_timer.is_stopped():
		remaining = game_length

	var minutes = int(remaining / 60) 
	var seconds = int(remaining) % 60
	var timer_text = "Timer %02d:%02d" % [minutes, seconds]

	if !blind_timer.is_stopped():
		var blind_text = "Seekers released in %ds" % int(ceil(blind_timer.time_left))
		game_timer_label.text = "%s | %s" % [blind_text, timer_text]
	else:
		game_timer_label.text = timer_text

func blind_seekers_for_duration(duration: float):
	if not multiplayer.is_server():
		return

	print("Blinding seekers for ", duration, " seconds")
	
	for player in players_container.get_children():
		if player.has_method("get_team") and player.get_team() == "seeker":
			var pid = int(player.name)
			print("Blinding player ID:", pid)
			player.rpc_id(pid, "remote_set_blind_deaf_dumb", true)

	blind_timer.start(blind_length)

func _on_blind_timer_timeout() -> void:
	if !multiplayer.is_server():
		return
	
	for player in players_container.get_children():
		var pid = player.get_multiplayer_authority()
		print("Unblinding player ID:", pid)
		player.rpc_id(pid, "remote_set_blind_deaf_dumb", false)

func _on_game_length_value_changed(value: float) -> void:
	game_length = int(value)

func _on_blind_length_value_changed(value: float) -> void:
	blind_length = int(value)

func _on_seekers_value_changed(value: float) -> void:
		starting_seekers = int(value)
		print(value)
