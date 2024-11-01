extends Node

@onready var chat_rect = $Chat
@onready var question_label = $Chat/VBoxContainer/HBoxContainer/QuestionLabel
@onready var chat_edit = $Chat/VBoxContainer/ChatEdit
@onready var message_container = $Chat/VBoxContainer/Scroll/MessageContainer
@onready var scroll = $Chat/VBoxContainer/Scroll
@onready var done_button = $Chat/VBoxContainer/HBoxContainer/DoneButton

@onready var voting_rect = $Voting
@onready var grid_container = $Voting/VBoxContainer/GridContainer
@onready var results_label = $Voting/VBoxContainer/ResultsLabel
@onready var confirm_button = $Voting/VBoxContainer/ConfirmButton

@onready var panel = $Panel
@onready var panel_label = $Panel/PanelContainer/VBoxContainer/PanelInfoLabel

@onready var time_label = $TimerLabel

const MAX_QUESTIONS = 729
const CHATTING_PERIOD_S = 60 * 7
const VOTING_PERIOD_S = 60 * 3

var timer = 0:
	set(value):
		if (value < 0):
			timer = 0
		else: 
			timer = value
		time_label.text = "Time Remaining: " + String.num_int64(int(timer) / 60) + ":" + ("0" if int(timer) % 60 < 10 else "") + String.num_int64(int(timer) % 60)

var timer_on = false
var tree_timer

var player_alive = true
var prev_state

func _ready():
	if multiplayer.is_server():
		print("Loaded the main game scene")
		
		# Server only initialization
		$"/root/Lobby".everyone_voted.connect(_on_everyone_voted)
		$"/root/Lobby".want_stop_chatting.connect(_on_want_stop_chatting)
		prev_state = $"/root/Lobby".game_state
		
		# Let the server generate the questions for the rounds
		generate_questions()
		
		$"/root/Lobby".set_questions.rpc($"/root/Lobby".questions)
		
		# Wait for ack from all players
		for i in range($"/root/Lobby".players.keys().size() - 1):
			await $"/root/Lobby".server_request_complete;
			print("Received ack")
		
		# Decide which players are swapped
		choose_swapped()
		
		$"/root/Lobby".set_swapped.rpc($"/root/Lobby".swapped)
		
		# Wait for ack from all players
		for i in range($"/root/Lobby".players.keys().size() - 1):
			await $"/root/Lobby".server_request_complete;
			print("Received ack")
		
		# Notify players they can start
		$"/root/Lobby".ack.rpc()
	else:
		# Wait to be notified the player can start
		await $"/root/Lobby".server_request_complete;
		print("Received ack")
		
		if multiplayer.get_unique_id() in $"/root/Lobby".swapped:
			show_panel_info("Your identity has been swapped with player " + $"/root/Lobby".player_info["name"] + "!")
	
	$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.CHATTING
	prev_state = $"/root/Lobby".game_state
	
	$"/root/Lobby".chat_messages = []
	
	$"/root/Lobby".curr_round = 1
	
	# Set up round information
	start_round()
	
	if not multiplayer.is_server():
		to_chatting_stage(1)

func show_panel_info(string : String):
	panel_label.text = string
	
	panel.visible = true

func generate_questions():
	var num_questions = $"/root/Lobby".players.keys().size() - 1 #- 2 #Debug for now
	
	# Get lines from file
	var lines = FileAccess.open("res://Assets/questions.txt", FileAccess.READ)
	var error = FileAccess.get_open_error()
	printerr(error_string(error))
	
	assert(lines)
	
	var questions = []
	
	print(num_questions)
	# Get random line numbers to select questions
	for i in range(num_questions):
		var random_number = randi_range(0, MAX_QUESTIONS - 1)
		while (random_number in questions):
			random_number = randi_range(0, MAX_QUESTIONS - 1)
		
		questions.append(random_number)
	
	print(questions)
	# Get lines according to selected lines
	var line_count = 0
	while lines.get_position() < lines.get_length():
		var line = lines.get_line()
		
		var i = questions.find(line_count)
		if i != -1:
			questions[i] = line
		
		line_count += 1
	
	$"/root/Lobby".questions = questions
	print(questions)

func choose_swapped():
	var swapped = []
	var player_ids = $"/root/Lobby".players.keys()
	player_ids.erase(1) # Get rid of the server
	
	for i in range(2):
		var swap = player_ids[randi_range(0, player_ids.size() - 1)]
		while (swap in swapped):
			swap = player_ids[randi_range(0, player_ids.size() - 1)]
		
		swapped.append(swap)
	
	$"/root/Lobby".swapped = swapped
	
	# Swap names for the server
	var temp_name = $"/root/Lobby".players[$"/root/Lobby".swapped[0]]["name"]
	$"/root/Lobby".players[$"/root/Lobby".swapped[0]]["name"] = $"/root/Lobby".players[$"/root/Lobby".swapped[1]]["name"]
	$"/root/Lobby".players[$"/root/Lobby".swapped[1]]["name"] = temp_name

# Used by the server to start the next round or section
func start_round():
	if multiplayer.is_server():
		print("Starting another round or section")
		print($"/root/Lobby".curr_round)
		print("The state is")
		print($"/root/Lobby".GAME_STATE.keys()[$"/root/Lobby".game_state])
		if $"/root/Lobby".game_state == $"/root/Lobby".GAME_STATE.CHATTING:
			tree_timer = get_tree().create_timer(CHATTING_PERIOD_S)
			await tree_timer.timeout
			
			# Reset the voting variables on the server side
			$"/root/Lobby".players_voted = []
			$"/root/Lobby".round_votes = {}
			
			to_voting_stage.rpc()
			
			$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.VOTING
		elif $"/root/Lobby".game_state == $"/root/Lobby".GAME_STATE.VOTING:
			tree_timer = get_tree().create_timer(VOTING_PERIOD_S)
			await tree_timer.timeout
			
			# Calculate the result of voting
			var most_voted = find_voted_player()
			var results
			var voted_out = 0
			
			if most_voted.size() == 0:
				results = "No one was voted"
			elif most_voted.size() == 1:
				results = $"/root/Lobby".players[most_voted[0]]["name"] + " is voted out"
				voted_out = most_voted[0]
				$"/root/Lobby".players[most_voted[0]]["alive"] = false
			else:
				results = $"/root/Lobby".players[most_voted[0]]["name"]
				for i in range(1, most_voted.size()):
					results += ", " + $"/root/Lobby".players[most_voted[i]]["name"]
				
				results += " tied in votes"
			
			print("Found results to be")
			print(results)
			
			print("The voted out player is")
			print(most_voted)
			
			to_voting_results.rpc(results, voted_out)
			
			$"/root/Lobby".send_player_info.rpc($"/root/Lobby".players) # Update everyone's player information
			
			# Check both factions for winner
			var winner = check_factions()
			
			if winner == 1:
				# Swappers win and end game
				$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.END
				results = "The swappers "
				results += $"/root/Lobby".players[$"/root/Lobby".swapped[0]]["name"] + " and "
				results += $"/root/Lobby".players[$"/root/Lobby".swapped[1]]["name"] + " win!"
				
				to_game_end.rpc(1, results)
				return
			elif winner == -1:
				# Non swappers win and end game
				$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.END
				results = "The non swappers "
				
				var players = $"/root/Lobby".players.keys()
				players.erase(1)
				players.erase($"/root/Lobby".swapped[0])
				players.erase($"/root/Lobby".swapped[1])
				
				results += $"/root/Lobby".players[players[0]]["name"]
				
				for i in range(1, players.size() ):
					results += ", " + $"/root/Lobby".players[players[i]]["name"]
				
				results += " win!"
				
				to_game_end.rpc(0, results)
				return
			
			$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.VOTING_RESULTS
		elif $"/root/Lobby".game_state == $"/root/Lobby".GAME_STATE.VOTING_RESULTS:
			await $"/root/Lobby".done_voting_results
			
			$"/root/Lobby".curr_round += 1
			
			# There are still questions remaining to ask
			if $"/root/Lobby".curr_round <= $"/root/Lobby".questions.size():
				# Make sure to reset important variables for done_talking
				$"/root/Lobby".players_stop_talking = {}
				to_chatting_stage.rpc($"/root/Lobby".curr_round)
				$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.CHATTING
			else:
				# End the game with the swappers winning
				$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.END
				
				var results = "The non swappers "
				
				var players = $"/root/Lobby".players.keys()
				players.erase(1)
				players.erase($"/root/Lobby".swapped[0])
				players.erase($"/root/Lobby".swapped[1])
				
				results += $"/root/Lobby".players[players[0]]["name"]
				
				for i in range(1, players.size() ):
					results += ", " + $"/root/Lobby".players[players[i]]["name"]
				
				results += " win!"
				
				to_game_end.rpc(0, results)
				return

@rpc("authority")
func to_voting_stage():
	print("to_voting_stage")
	print("The state before is")
	print($"/root/Lobby".GAME_STATE.keys()[$"/root/Lobby".game_state])
	
	$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.VOTING
	
	# Configure the results label
	results_label.visible = false
	
	# Make the confirm button visible if still alive
	if player_alive:
		confirm_button.visible = true
	else:
		confirm_button.visible = false
	
	# Configure the buttons
	var num_buttons = get_tree().get_node_count_in_group("vote_button")
	var buttons = get_tree().get_nodes_in_group("vote_button")
	var players = $"/root/Lobby".players.keys()
	players.erase(1)  # exclude server
	players = players.filter($"/root/Lobby".player_is_alive) # Exclude dead players
	var num_players = players.size()
	
	var diff = num_buttons - num_players
	if diff > 0:
		print("More buttons than players")
		for i in range(diff):
			buttons[-1 * (i + 1)].free()
	elif diff < 0: # exclude server and yourself
		print("Less buttons than players")
		for i in range(abs(diff)):
			var button = preload("res://Scenes/vote_button.tscn")
			button = button.instantiate()
			
			grid_container.add_child(button)
	
	# Rename all the buttons just in case
	buttons = grid_container.get_children()
	for i in range(buttons.size()):
		if players[i] == multiplayer.get_unique_id():
			buttons[i].text = "Yourself"
		else: 
			buttons[i].text = $"/root/Lobby".players[players[i]]["name"]
		buttons[i].player_id = players[i]
		buttons[i].button_pressed = false # Unpress all buttons
	
	# Set the timer
	timer = VOTING_PERIOD_S
	
	voting_rect.visible = true
	chat_rect.visible = false
	
	timer_on = true

@rpc("authority")
func to_voting_results(results : String, playerId):
	print("to_voting_results with args")
	print(results)
	print(playerId)
	
	print("The state before is")
	print($"/root/Lobby".GAME_STATE.keys()[$"/root/Lobby".game_state])
	
	$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.VOTING_RESULTS
	
	# Stop the timer
	timer_on = false
	
	# Configure the results label
	results_label.text = results
	results_label.visible = true
	
	# Only make the confirm button visible for the game creator
	if $"/root/Lobby".player_info["creator"]:
		confirm_button.visible = true
	else:
		confirm_button.visible = false

@rpc("authority")
func to_chatting_stage(round):
	print("Switching to chatting stage")
	
	print("The state before is")
	print($"/root/Lobby".GAME_STATE.keys()[$"/root/Lobby".game_state])
	
	$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.CHATTING
	
	# Set the question based on the round
	$"/root/Lobby".curr_round = round
	question_label.text = $"/root/Lobby".questions[$"/root/Lobby".curr_round - 1]
	
	# Reset the timer
	timer = CHATTING_PERIOD_S
	
	# Reset the done talking button
	done_button.set_pressed_no_signal(false)
	
	# Disable the done talking button if dead
	if player_alive:
		done_button.disabled = false
	else:
		done_button.disabled = true
	
	chat_rect.visible = true
	voting_rect.visible = false
	
	timer_on = true

# result should be 0 if non_swappers and 1 if swappers
@rpc("authority")
func to_game_end(result : int, result_str : String):
	print(to_game_end)
	print("The state before is")
	print($"/root/Lobby".GAME_STATE.keys()[$"/root/Lobby".game_state])
	
	$"/root/Lobby".game_state = $"/root/Lobby".GAME_STATE.END
	
	panel_label.text = result_str
	
	panel.visible = true

# Return an array of the most voted players
# To be called by the server
func find_voted_player():
	var voted_players = $"/root/Lobby".round_votes.keys()
	
	print("The voted players while finding voted players is")
	print(voted_players)
	
	if voted_players.size() == 0:
		return []
	
	# Try to find the players with the most votes
	var most_votes = [voted_players[0]]
	for i in range(1, voted_players.size()):
		if $"/root/Lobby".round_votes[voted_players[i]] > $"/root/Lobby".round_votes[most_votes[0]]:
			most_votes = [voted_players[i]]
		elif $"/root/Lobby".round_votes[voted_players[i]] == $"/root/Lobby".round_votes[most_votes[0]]: # Ties are possible
			most_votes.append(voted_players[i])
	
	return most_votes

# Returns 0 if neutral, 1 if swappers win, -1 if non-swappers win
func check_factions():
	var player_ids_left = $"/root/Lobby".players.keys()
	player_ids_left.erase(1) # Get rid of server
	player_ids_left = player_ids_left.filter($"/root/Lobby".player_is_alive) # Get rid of dead players
	
	var swappers_alive = $"/root/Lobby".swapped.duplicate()
	swappers_alive = swappers_alive.filter($"/root/Lobby".player_is_alive)
	
	# Swappers win if there is only one non swapper left
	if player_ids_left.size() == 3 and swappers_alive.size() == 2:
		return 1
	elif swappers_alive.size() == 0: # All swappers are dead, so non-swappers win
		return -1
	
	return 0

func _process(delta):
	if multiplayer.is_server():
		if prev_state != $"/root/Lobby".game_state:
			start_round()
		
		prev_state = $"/root/Lobby".game_state
		return
		
	# If new chat messages arrive for a player
	var num_chat_bubbles = get_tree().get_node_count_in_group("chat_bubbles")
	if  num_chat_bubbles < $"/root/Lobby".chat_messages.size():
		var new_bubble = preload("res://Scenes/chat_bubbles.tscn")
		new_bubble = new_bubble.instantiate()
		
		# If the player is you, show a visual difference in the bubble
		if $"/root/Lobby".chat_messages[num_chat_bubbles]["playerId"] == multiplayer.get_unique_id():
			new_bubble.text = ""
			new_bubble.size_flags_horizontal = Control.SIZE_SHRINK_END
		else:
			new_bubble.text = $"/root/Lobby".players[$"/root/Lobby".chat_messages[num_chat_bubbles]["playerId"]]["name"] + "\n"
			new_bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		
		new_bubble.text += $"/root/Lobby".chat_messages[num_chat_bubbles]["message"]
		
		message_container.add_child(new_bubble)
		
		await get_tree().process_frame
		
		scroll.ensure_control_visible(new_bubble)
	
	player_alive = $"/root/Lobby".player_info["alive"]

func _physics_process(delta):
	# Timer updates
	if timer_on:
		timer -= delta

func _on_chat_edit_gui_input(event):
	if event is InputEventKey:
		if event.is_action_pressed("chat_enter"):
			# Handle whatever is in the chat edit
			var chat_text = chat_edit.text
			chat_text.rstrip("\n")
			
			if chat_text and player_alive:
				$"/root/Lobby".send_chat_server.rpc_id(1, chat_text)
				chat_edit.clear.call_deferred()


func _on_confirm_button_pressed():
	print("_on_confirm_button_pressed")
	if $"/root/Lobby".game_state == $"/root/Lobby".GAME_STATE.VOTING:
		# Look through the list of vote buttons and find which is pressed
		var buttons = get_tree().get_nodes_in_group("vote_button")
		var pressed = 0
		for button in buttons:
			if button.button_pressed:
				pressed = button.player_id
				break
		
		print("Send vote")
		$"/root/Lobby".send_vote_server.rpc_id(1, pressed)
		
		confirm_button.visible = false # Prevent players from voting again
		
	elif $"/root/Lobby".game_state == $"/root/Lobby".GAME_STATE.VOTING_RESULTS:
		print("Send voting results done")
		$"/root/Lobby".send_voting_results_done_server.rpc_id(1)

func _on_everyone_voted():
	print("_on_everyone_voted")
	tree_timer.time_left = 0
	print("Timer is now")
	print(tree_timer.time_left)

func _on_want_stop_chatting():
	print("_on_want_stop_chatting")
	tree_timer.time_left = 0

func _on_panel_confirm_button_pressed():
	# If the game has ended, pressing confirm brings you back to the main menu
	if $"/root/Lobby".game_state == $"/root/Lobby".GAME_STATE.END:
		# Disconnect from the game
		$"/root/Lobby".remove_multiplayer_peer()
		
		# Go back to the main menu
		$"/root/Lobby".main_menu_state = $"/root/Lobby".MAIN_MENU_STATE.MAIN_MENU
		get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")
	else:
		# Just hide the panel since it is just used for information
		panel.visible = false

# Done talking button
func _on_done_button_pressed(toggled):
	if $"/root/Lobby".game_state == $"/root/Lobby".GAME_STATE.CHATTING:
		$"/root/Lobby".send_done_talking_server.rpc_id(1, toggled)
