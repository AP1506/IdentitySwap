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

@onready var config_menu = $ConfigMenu
@onready var server_ip_edit = $ConfigMenu/VBoxContainer/ServerIPEdit
@onready var questions_edit = $Lobby/VBoxContainer2/HBoxContainer/Customizer/QuestionsEdit

const DEFAULT_NUM_QUESTIONS = 3
const MAX_NUM_QUESTIONS = 50

var creating_game: bool
var address_to_join : String

func _ready():
	if OS.has_feature("dedicated_server"):
		$"/root/Lobby".create_game()
		print("Created game server")
		print("The machine's IP address is " + IP.resolve_hostname(str(OS.get_environment("COMPUTERNAME")),1))
	else:
		# Reset player info
		$"/root/Lobby".player_info = {"name": "Server", "gameCode": "GameCode", "creator": false, "alive": true}
	
	# Connect signals for everyone
	$"/root/Lobby".game_connect.connect(_on_game_connected)
	
	# Default address to join
	address_to_join = IP.resolve_hostname(str(OS.get_environment("COMPUTERNAME")),1)
	
	# Set default number of questions
	questions_edit.text = String.num_int64(DEFAULT_NUM_QUESTIONS)
	questions_edit.placeholder_text = String.num_int64(DEFAULT_NUM_QUESTIONS) + "-" + String.num_int64(MAX_NUM_QUESTIONS)

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
		
		var error = $"/root/Lobby".join_game(address_to_join)
		
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
		var error = $"/root/Lobby".join_game(address_to_join)
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
	# Handle errors
	if error and error is String:
			confirm_error_label.text = error
			confirm_error_label.visible = true
			return
	else:
		confirm_error_label.visible = false
		start_game_button.visible = false
	
	if creating_game:
		# Create a random game code and give it to the server
		$"/root/Lobby".set_game_code_server.rpc_id(1, $"/root/Lobby".player_info['gameCode'])
		
		start_game_button.visible = true
	else: # Joining a game
		pass
	
	# If successful move to the lobby
	game_code_label.text = "Game Code: " + $"/root/Lobby".player_info["gameCode"]
	
	lobby.visible = true
	join_game_menu.visible = false
	
	$"/root/Lobby".main_menu_state = $"/root/Lobby".MAIN_MENU_STATE.LOBBY

func _on_back_button_pressed():
	if $"/root/Lobby".main_menu_state == $"/root/Lobby".MAIN_MENU_STATE.LOBBY:
		$"/root/Lobby".remove_multiplayer_peer()
	
	main_menu.visible = true
	join_game_menu.visible = false
	lobby.visible = false
	if config_menu.visible:
		# Set the ip address to join
		if server_ip_edit.text:
			address_to_join = server_ip_edit.text
		else: # Use the default value, this machine's IP address
			address_to_join = IP.resolve_hostname(str(OS.get_environment("COMPUTERNAME")),1)
		
		config_menu.visible = false
		$"/root/Lobby"
	
	$"/root/Lobby".main_menu_state = $"/root/Lobby".MAIN_MENU_STATE.MAIN_MENU

# If you're in here you should have a good connection to the server
func _on_start_game_button_pressed():
	
	# Errors
	if $"/root/Lobby".players.keys().size() - 1 < 4: # Check that there are more than 3 players to start
		start_game_error_label.text = "Need 4+ players to start"
		start_game_error_label.visible = true
		return
	elif !questions_edit.text.is_valid_int() or !questions_edit.text:
		start_game_error_label.text = "Please enter an integer for number of questions"
		start_game_error_label.visible = true
		return
	elif questions_edit.text.to_int() > MAX_NUM_QUESTIONS:
		start_game_error_label.text = "Please enter a number below " + String.num_int64(MAX_NUM_QUESTIONS) + " for number of questions"
		start_game_error_label.visible = true
		return
	elif questions_edit.text.to_int() < DEFAULT_NUM_QUESTIONS:
		start_game_error_label.text = "Please enter a number above " + String.num_int64(DEFAULT_NUM_QUESTIONS) + " for number of questions"
		start_game_error_label.visible = true
		return
	else:
		start_game_error_label.visible = false
	
	# Send the server the number of questions, aka number of rounds
	$"/root/Lobby".send_num_questions_server.rpc_id(1, questions_edit.text.to_int())
	
	await $"/root/Lobby".server_request_complete
	
	$"/root/Lobby".load_game.rpc("res://Scenes/main.tscn")

func _on_name_edit_text_submitted(new_text):
	_on_confirm_button_pressed()


func _on_config_button_pressed():
	config_menu.visible = true
