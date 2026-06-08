extends Node
class_name CharacterAnimationController

@export var character_path: NodePath
@export var animation_tree_path: NodePath

@export_category("Animation")
@export var default_xfade := 0.15
@export var instant_xfade := 0.02

@export_category("Slide")
@export var slide_speed_threshold := 6.0

@onready var character: CharacterController = get_node(character_path)
@onready var animation_tree: AnimationTree = get_node(animation_tree_path)

@onready var root_playback: AnimationNodeStateMachinePlayback = (
	animation_tree["parameters/playback"]
)

@onready var grounded_playback: AnimationNodeStateMachinePlayback = (
	animation_tree["parameters/Grounded/playback"]
)

@onready var airborne_playback: AnimationNodeStateMachinePlayback = (
	animation_tree["parameters/Airborne/playback"]
)

var move_amount := 0.0

var was_on_floor := false
var was_crouching := false
var was_ground_pounding := false
var was_spinning := false
var was_diving := false

var current_grounded_state := ""
var current_airborne_state := ""

func _ready():
	animation_tree.active = true

func _process(_delta):

	update_base_state()

	if character.is_on_floor():
		update_grounded_state()
	else:
		update_airborne_state()

	was_on_floor = character.is_on_floor()
	was_crouching = is_crouching()
	was_ground_pounding = character.ground_pounding
	was_spinning = character.spinning
	was_diving = character.diving


# ROOT


func update_base_state():

	# Uncomment later when frozen is added
	# if character.movement_mode == CharacterController.MovementMode.FROZEN:
	# 	travel_root("Frozen")
	# 	return

	if character.is_on_floor():

		if root_playback.get_current_node() != "Grounded":
			current_airborne_state = ""
			current_grounded_state = ""
		travel_root("Grounded", .2)

	else:

		if root_playback.get_current_node() != "Airborne":
			current_grounded_state = ""
			current_airborne_state = ""
		travel_root("Airborne", .2)

# GROUNDED
func update_grounded_state():
	var speed := character.get_horizontal_velocity().length()
	var crouching := is_crouching()
	var has_input := character.input_direction.length() > 0.05
	
	# GROUND POUND LAND
	if character.in_ground_pound_recovery:
		travel_grounded("HipDropLand", 0.03)
		return
	
	# LANDING
	if !was_on_floor and crouching:
		travel_grounded("SquatLand", 0.05)
		return

	# ENTER CROUCH
	if crouching and !was_crouching:
		travel_grounded("SquatStart", 0.05)
		return
		
	# EXIT CROUCH
	if !crouching and was_crouching:
		travel_grounded("SquatEnd", 0.05)
		return

	# CROUCH STATES
	if crouching:
		# Momentum slide
		if speed > slide_speed_threshold and !has_input:
			travel_grounded("SquatLand", 0.08)
			return

		# Crouch moving
		if has_input:
			travel_grounded("SquatWalk", 0.05)
			return

		# Crouch idle
		travel_grounded("SquatWait", 0.05)
		return

	# NORMAL GROUND MOVEMENT
	move_amount = (character.get_horizontal_velocity().length() / character.max_ground_speed)
	animation_tree["parameters/Grounded/WalkBlendSpace1D/blend_position"] = move_amount
	travel_grounded("WalkBlendSpace1D")


# AIRBORNE
func update_airborne_state():
	# GROUND POUND START
	if character.ground_pounding and !was_ground_pounding:
		travel_airborne("HipDropStart", 0.1)
		return

	if character.did_ground_pound_jump:
		travel_airborne("JumpHipDrop", 0.02)
		character.did_ground_pound_jump = false
		return

	
	# SPIN JUMP
	if character.spinning:
		travel_airborne("SpinJump", 0.1)
		return

	
	# DIVE
	if character.diving and !was_diving:
		travel_airborne("HeadSlidingStart", 0.03)
		return

	# TRIPLE JUMP PLACEHOLDER
	# Add jump2 and jump3 later
	# if character.jump_chain == 2:
	# 	travel_airborne("Jump2")
	# elif character.jump_chain >= 3:
	# 	travel_airborne("Jump3")

	
	# DEFAULT JUMP
	if character.velocity.y > 1.0:
		travel_airborne("Jump", 0.08)
		return
	
	travel_airborne("Fall", 0.25)

# HELPERS
func travel_root(state: String, xfade := -1.0):
	if root_playback.get_current_node() == state:
		return
	if xfade < 0.0:
		xfade = default_xfade
	set_transition_xfade("Root", xfade)
	root_playback.travel(state)

func travel_grounded(state: String, xfade := -1.0):
	if current_grounded_state == state:
		return
	current_grounded_state = state
	if xfade < 0.0:
		xfade = default_xfade
	set_transition_xfade("Grounded", xfade)
	grounded_playback.travel(state)

func travel_airborne(state: String, xfade := -1.0):
	if current_airborne_state == state:
		return
	current_airborne_state = state
	if xfade < 0.0:
		xfade = default_xfade
	set_transition_xfade("Airborne", xfade)
	airborne_playback.travel(state)

func set_transition_xfade(_machine_name: String, _xfade: float):
	# Hook point for runtime transition editing later
	pass

func is_crouching() -> bool:
	return (
		character.movement_mode == CharacterController.MovementMode.CROUCHED
		or character.ground_pounding
		or character.in_ground_pound_recovery
	)
