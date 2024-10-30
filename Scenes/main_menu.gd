extends Node

@onready var main_menu = $MainMenu

@onready var join_game_menu = $JoinGameMenu
@onready var join_game_elements_only = [$JoinGameMenu/VBoxContainer/AskCodeLabel, $JoinGameMenu/VBoxContainer/CodeEdit]

@onready var lobby = $Lobby
@onready var player_list_label = $Lobby/VBoxContainer2/HBoxContainer/VBoxContainer2/JoinedPlayersLabel

func _on_create_game_button_pressed():
	for elem in join_game_elements_only:
		elem.visible = false
	join_game_menu.visible = true
	main_menu.visible = false


func _on_join_game_button_pressed():
	for elem in join_game_elements_only:
		elem.visible = true
	join_game_menu.visible = true
	main_menu.visible = false


func _on_confirm_button_pressed():
	# Check that game was made successfully before showing
	
	# Update the player list
	
	# If successful move to the lobby
	lobby.visible = true
	join_game_menu.visible = false
