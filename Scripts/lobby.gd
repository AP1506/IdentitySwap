extends Node

# Code taken from https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html

# Autoload named Lobby

# These signals can be connected to by a UI lobby scene or the game scene.
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected
signal game_connect(error)

signal server_request_complete()

signal everyone_voted
signal done_voting_results
signal want_stop_chatting

const PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1" # IPv4 localhost
const MAX_CONNECTIONS = 20

# This will contain player info for every player,
# with the keys being each player's unique IDs.
# The length is the number of players in the game
var players = {}

var players_voted = []

var players_stop_talking = {} # In the format { playerId : doneStatus, ... }

# This is the local player info. This should be modified locally
# before the connection is made. It will be passed to every other peer.
# For example, the value of "name" can be set to something the player
# entered in a UI scene.
var player_info = {"name": "Server", "gameCode": "GameCode", "creator": false, "alive": true}

# The two players that are swapped
var swapped = []

var players_loaded = 0

var NUM_ROUNDS = 3
var curr_round : int # 1-indexed
var questions = [""]

var chat_messages = [] # In the format {"message": String, "playerId": int}
var round_votes = {} # In the format {playerId : numVotes}

enum MAIN_MENU_STATE {MAIN_MENU, JOIN_GAME, CREATE_GAME, LOBBY}
enum GAME_STATE {CHATTING, VOTING, VOTING_RESULTS, END}

var main_menu_state : MAIN_MENU_STATE = MAIN_MENU_STATE.MAIN_MENU

var game_state : GAME_STATE = GAME_STATE.CHATTING

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func join_game(address = ""):
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	
	return 0

@rpc("any_peer")
func send_num_questions_server(num_q : int):
	NUM_ROUNDS = num_q
	
	ack.rpc_id(multiplayer.get_remote_sender_id())

# Any client can request player info from the server at any point
func request_player_info():
	send_player_info_server.rpc_id(1)

# Send your player info to the server
@rpc("any_peer")
func grab_player_info_server(player_info):
	players[multiplayer.get_remote_sender_id()] = player_info
	
	# Update everyone's player info
	send_player_info.rpc(players)

@rpc("any_peer")
func send_player_info_server():
	send_player_info.rpc_id(multiplayer.get_remote_sender_id(), players)
	print("Sending player info to requester " + String.num_int64(multiplayer.get_remote_sender_id()))

@rpc("authority")
func send_player_info(players_info):
	players = players_info
	
	if multiplayer.get_unique_id() in players.keys():
		player_info["alive"] = players_info[multiplayer.get_unique_id()]["alive"] # Update the alive status to match
	
	server_request_complete.emit()
	print("Sending player info")
	print(players_info)

@rpc("any_peer")
func set_game_code_server(code : String):
	player_info["gameCode"] = code
	print("Setting code")
	print(code)

@rpc("authority")
func set_questions(new_questions):
	questions = new_questions
	print("Setting questions")
	print(new_questions)
	
	ack.rpc_id(1)

@rpc("authority")
func set_swapped(new_swapped):
	print("Setting swapped")
	print(new_swapped)
	
	swapped = new_swapped
	
	# Swap the swapped players names
	var temp_name = players[swapped[0]]["name"]
	players[swapped[0]]["name"] = players[swapped[1]]["name"]
	players[swapped[1]]["name"] = temp_name
	
	# And set the player info for the affected players to be swapped
	if multiplayer.get_unique_id() in swapped:
		player_info["name"] = players[multiplayer.get_unique_id()]["name"]
	
	ack.rpc_id(1)

@rpc("any_peer")
func send_chat_server(chat : String):
	var new_chat = {"message": chat, "playerId": multiplayer.get_remote_sender_id()}
	chat_messages.append(new_chat)
	
	receive_chat.rpc(new_chat)

@rpc("authority", "reliable")
func receive_chat(chat : Dictionary):
	chat_messages.append(chat)

@rpc("any_peer")
func send_vote_server(playerId : int):
	print("send_vote_server with arg")
	print(playerId)
	
	# I'm counting on removing the button to avoid a revote
	players_voted.append(multiplayer.get_remote_sender_id())
	
	if playerId in round_votes.keys():
		round_votes[playerId] += 1
	elif playerId != 0:
		round_votes[playerId] = 1
	
	var votable_players = players.keys()
	votable_players.erase(1)
	votable_players = votable_players.filter(player_is_alive)
	
	# Check if all the players have voted yet
	if players_voted.size() == votable_players.size():
		print("Everyone has voted")
		everyone_voted.emit()

@rpc("any_peer")
func send_voting_results_done_server():
	print("send_voting_results_done_server")
	done_voting_results.emit()

@rpc("any_peer")
func send_done_talking_server(done : bool):
	print("send_done_talking_server")
	
	players_stop_talking[multiplayer.get_remote_sender_id()] = done
	
	var votable_players = players.keys()
	votable_players.erase(1)
	votable_players = votable_players.filter(player_is_alive)
	
	# Check if everyone is done
	if players_stop_talking.keys().size() == votable_players.size() and players_stop_talking.values().find(false) == -1:
		print("Everyone wants to stop chatting")
		want_stop_chatting.emit()

@rpc("any_peer")
func ack():
	print("Ack")
	server_request_complete.emit()

func player_is_alive(player_id):
	return players[player_id]["alive"]

func create_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CONNECTIONS)
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	
	players[1] = player_info
	
	print("Created game")


func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = null


# When the server decides to start the game from a UI scene,
# do Lobby.load_game.rpc(filepath)
@rpc("any_peer", "reliable", "call_local")
func load_game(game_scene_path):
	print("Attempt at loading the game scene")
	get_tree().change_scene_to_file(game_scene_path)


# Every peer will call this when they have loaded the game scene.
@rpc("any_peer", "reliable")
func player_loaded():
	if multiplayer.is_server():
		players_loaded += 1
		if players_loaded == players.size():
			$/root/Main.start_game()
			players_loaded = 0


# When a peer connects, send them my player info.
# This allows transfer of all desired data for each player, not only the unique ID.
func _on_player_connected(id):
	#_register_player.rpc_id(id, player_info)
	print("Player with id " + String.num_int64(id) + " has connected")
	pass


@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)

# This is called on everyone
func _on_player_disconnected(id):
	print("The player " + players[id]["name"] + " just disconnected")
	players.erase(id)
	
	# Go back to the menu if all players are gone
	if players.size() == 1 and multiplayer and multiplayer.is_server():
		remove_multiplayer_peer()
		main_menu_state = MAIN_MENU_STATE.MAIN_MENU
		get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")
		print("Returning to the menu")
	
	player_disconnected.emit(id)

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)
	print("Connected to server with id " + String.num_int64(peer_id))
	
	# Get the other players info to check if its valid
	request_player_info()
	await server_request_complete
	
	for player in players.values():
		# Check that name is not already used
		if player["name"] == player_info["name"]:
			game_connect.emit("Player name already taken")
			remove_multiplayer_peer()
			return
	
	grab_player_info_server.rpc_id(1, player_info)
	
	print("Joined game")
	
	game_connect.emit("")


func _on_connected_fail():
	multiplayer.multiplayer_peer = null


func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
