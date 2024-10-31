extends Node

@onready var main_menu = $MainMenu

@onready var join_game_menu = $JoinGameMenu
@onready var join_game_elements_only = [$JoinGameMenu/VBoxContainer/AskCodeLabel, $JoinGameMenu/VBoxContainer/CodeEdit]
@onready var name_edit = $JoinGameMenu/VBoxContainer/NameEdit
@onready var code_edit = $JoinGameMenu/VBoxContainer/CodeEdit
@onready var confirm_error_label = $JoinGameMenu/VBoxContainer/ErrorLabel

@onready var lobby = $Lobby
@onready var player_list_label = $Lobby/VBoxContainer2/HBoxContainer/VBoxContainer2/JoinedPlayersLabel
@onready var game_code_label = $Lobby/VBoxContainer2/GameCodeLabel
@onready var start_game_error_label = $Lobby/VBoxContainer2/ErrorLabel
@onready var start_game_button = $Lobby/VBoxContainer2/StartGameButton

var creating_game: bool

func _ready():
	if OS.has_feature("dedicated_server"):
		$"/root/Lobby".create_game()
		print("Created game server")
	
	$"/root/Lobby".game_connect.connect(_on_game_connected)

func _process(delta):
	if (lobby.visible == true):
		update_player_list()

func update_player_list():
	var temp_str = ""
	for player in $"/root/Lobby".players.values():
		# Don't consider the server
		if player["name"] == "Server":
			continue
		temp_str += player["name"]
		if (player["name"] == $"/root/Lobby".player_info["name"]):
			temp_str += " (you)"
		
		temp_str += "\n"
	
	player_list_label.text = temp_str

func _on_create_game_button_pressed():
	creating_game = true
	
	for elem in join_game_elements_only:
		elem.visible = false
	join_game_menu.visible = true
	main_menu.visible = false
	
	$"/root/Lobby".main_menu_state = $"/root/Lobby".MAIN_MENU_STATE.CREATE_GAME


func _on_join_game_button_pressed():
	creating_game = false
	
	for elem in join_game_elements_only:
		elem.visible = true
	join_game_menu.visible = true
	main_menu.visible = false
	
	$"/root/Lobby".main_menu_state = $"/root/Lobby".MAIN_MENU_STATE.JOIN_GAME


func _on_confirm_button_pressed():
	$"/root/Lobby".player_info["creator"] = creating_game
	$"/root/Lobby".player_info["name"] = name_edit.text
	
	if creating_game:
		
		$"/root/Lobby".player_info["gameCode"] = "hello"
		
		# Try joining the game
		
		var error = $"/root/Lobby".join_game()
		
		if error:
			confirm_error_label.text = "Error connecting to the server"
			confirm_error_label.visible = true
			return
		else:
			confirm_error_label.visible = false
	else: # Joining a game
		# Update player info
		$"/root/Lobby".player_info["gameCode"] = code_edit.text
		
		# Try joining the game
		var error = $"/root/Lobby".join_game()
		if error and error is String:
			confirm_error_label.text = error
			confirm_error_label.visible = true
			return
		elif error:
			confirm_error_label.text = "Error connecting to the server"
			confirm_error_label.visible = true
			return
		else:
			confirm_error_label.visible = false

# Come here after confirmation that the game is connected
func _on_game_connected(error):
	if creating_game:
		# Create a random game code and give it to the server
		$"/root/Lobby".set_game_code_server.rpc_id(1, $"/root/Lobby".player_info['gameCode'])
		
		start_game_button.visible = true
	else: # Joining a game
		if error and error is String:
			confirm_error_label.text = error
			confirm_error_label.visible = true
			return
		else:
			confirm_error_label.visible = false
			start_game_button.visible = false
	
	# If successful move to the lobby
	game_code_label.text = $"/root/Lobby".player_info["gameCode"]
	
	lobby.visible = true
	join_game_menu.visible = false
	
	$"/root/Lobby".main_menu_state = $"/root/Lobby".MAIN_MENU_STATE.LOBBY

func _on_back_button_pressed():
	if $"/root/Lobby".main_menu_state == $"/root/Lobby".MAIN_MENU_STATE.LOBBY:
		$"/root/Lobby".remove_multiplayer_peer()
	
	main_menu.visible = true
	join_game_menu.visible = false
	lobby.visible = false
	
	$"/root/Lobby".main_menu_state = $"/root/Lobby".MAIN_MENU_STATE.MAIN_MENU


func _on_start_game_button_pressed():
	# Errors
	if $"/root/Lobby".players.keys().size() - 1 < 4: # Check that there are more than 3 players to start
		start_game_error_label.text = "Need 4+ players to start"
		start_game_error_label.visible = true
		return
	else:
		start_game_error_label.visible = false
	
	$"/root/Lobby".load_game.rpc("res://Scenes/main.tscn")

func _on_name_edit_text_submitted(new_text):
	_on_confirm_button_pressed()
