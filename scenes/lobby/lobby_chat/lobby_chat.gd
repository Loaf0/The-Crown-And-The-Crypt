extends Control

func _ready() -> void:
	%LobbyChatInput.keep_editing_on_text_submit = true
	%LobbyChatInput.text_submitted.connect(func(_text): _send_chat_to_lobby())
	%LobbyChatSend.pressed.connect(func(): _send_chat_to_lobby())

	LobbySystem.signal_lobby_changed.connect(_render_lobby_clear)
	LobbySystem.signal_lobby_chat.connect(_render_lobby_chat)
	LobbySystem.signal_lobby_event.connect(_render_new_event)

func _send_chat_to_lobby():
	LobbySystem.lobby_send_chat(%LobbyChatInput.text)
	%LobbyChatInput.clear()

func _render_lobby_clear(lobby):
	if not lobby:
		%LobbyChat.clear()

func _render_lobby_chat(chat_user: String, chat_text: String):
	%LobbyChat.append_text('[color=FFFFFF]' + chat_user + ": " + chat_text)
	%LobbyChat.newline()

func _render_new_event(event_text: String):
	%LobbyChat.append_text('[color=808080]' + event_text)
	%LobbyChat.newline()
	
	
