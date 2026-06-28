extends PanelContainer

var user_panel_stylebox = preload("res://scenes/lobby/theme/lobby_player_container_styleboxflat.tres")

var peer_id: String
var username: String
var color: String

func _ready() -> void:
	%ButtonKick.pressed.connect(func(): LobbySystem.lobby_kick(peer_id))
	%LabelPlayerUsername.text = username
	%ColorRect.color = Color.from_string(color, Color.WHITE)
	%ColorRect.custom_minimum_size = Vector2(25.0, 25.0)
	%ColorRect.color = Color.from_string(color, Color.WHITE)
	add_theme_stylebox_override("panel", user_panel_stylebox)
