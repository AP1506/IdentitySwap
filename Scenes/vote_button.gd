class_name VoteButton extends Button

var player_id: int

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _toggled(toggled_on):
	var other_buttons = get_tree().get_nodes_in_group("vote_button")
	
	# Only one button can be toggled in the group at once
	if toggled_on:
		for button in other_buttons:
			if button != self:
				button.button_pressed = false
