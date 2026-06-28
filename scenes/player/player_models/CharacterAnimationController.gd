extends Node
class_name CharacterAnimationController

@export var character_path: NodePath
@export var animation_tree_path: NodePath

@export var debug_print_animation := true

@export_category("Animation")
@export var default_xfade := 0.15

@export_category("Slide")
@export var slide_speed_threshold := 6.0

@onready var character: PlayerCharacter = get_node(character_path)
@onready var animation_tree: AnimationTree = get_node(animation_tree_path)

@onready var root_playback: AnimationNodeStateMachinePlayback = (
	animation_tree["parameters/playback"]
)

@onready var gameplay_playback: AnimationNodeStateMachinePlayback = (
	animation_tree["parameters/Gameplay/playback"]
)

var current_gameplay_state := ""

var move_amount := 0.0

var wall_slide_animation := ""

@export var current_anim = ""

# short lock after any jump to prevent update loops from stomping the chosen jump animation
@export var jump_state_lock_time := 0.12
var jump_state_lock_timer := 0.0

func _ready():
	animation_tree.active = true

	character.jumped.connect(_on_jumped)
	character.landed.connect(_on_landed)

	character.spin_started.connect(_on_spin_started)
	character.dive_started.connect(_on_dive_started)

	character.ground_pound_started.connect(_on_ground_pound_started)
	character.ground_pound_landed.connect(_on_ground_pound_landed)

	character.crouch_started.connect(_on_crouch_started)
	character.crouch_ended.connect(_on_crouch_ended)

	character.bonk_started.connect(_on_bonk_started)
	character.bonk_recovery_started.connect(_on_bonk_recovery_started)
	#character.bonk_recovery_finished.connect(_on_bonk_recovery_finished)

	update_root_state()


func _process(delta):
	if !character.is_multiplayer_authority():
		sync_remote_animation()
		return

	update_root_state()

	if character.is_on_floor():
		wall_slide_animation = ""
		update_grounded_loop()
	else:
		update_airborne_loop()

	# decrement jump lock timer
	jump_state_lock_timer = max(jump_state_lock_timer - delta, 0.0)

	update_blendspaces()


func sync_remote_animation():
	update_root_state()

	if current_anim.is_empty():
		return

	travel_gameplay(current_anim)


func update_root_state():
	if root_playback.get_current_node() != "Gameplay":
		root_playback.travel("Gameplay")


func update_blendspaces():
	move_amount = (
		character.get_horizontal_velocity().length()
		/ max(character.max_ground_speed, 0.01)
	)

	animation_tree[
		"parameters/Gameplay/WalkBlendSpace1D/blend_position"
	] = move_amount

func update_grounded_loop():
	if jump_state_lock_timer > 0.0:
		return
	if character.stunned:
		return

	if character.bonk_bouncing:
		return

	if character.in_ground_pound_recovery:
		return

	var speed := character.get_horizontal_velocity().length()
	var has_input := character.input_direction.length() > 0.05

	if is_crouching():

		if speed > slide_speed_threshold and !has_input:
			travel_gameplay("SquatLand")
			return

		if has_input:
			travel_gameplay("SquatWalk")
			return

		travel_gameplay("SquatWait")
		return

	travel_gameplay("WalkBlendSpace1D")

func update_airborne_loop():
	if jump_state_lock_timer > 0.0:
		return
	if character.stunned:
		return

	if character.ground_pounding:
		return

	if character.wall_sliding:
		if wall_slide_animation.is_empty():
			wall_slide_animation = (
				"WallSlideR"
				if randi() % 2 == 0
				else "WallSlideL"
			)

		travel_gameplay(wall_slide_animation)
		return

	if character.diving:
		return

	if character.spinning:
		return

	

	if character.velocity.y < -1.0:
			travel_gameplay("Fall")

func _on_bonk_started():
	travel_gameplay("Damage")


func _on_bonk_recovery_started():
	travel_gameplay("DamageLand")

func _on_jumped(jump_type):
	# lock updates briefly so the chosen jump animation isn't overwritten
	jump_state_lock_timer = jump_state_lock_time
	match jump_type:
		PlayerCharacter.JumpType.GROUND_POUND:
			travel_gameplay("JumpHipDrop")

		PlayerCharacter.JumpType.CROUCH:
			travel_gameplay("JumpBack")

		PlayerCharacter.JumpType.SECOND:
			travel_gameplay("Jump2")

		PlayerCharacter.JumpType.THIRD:
			travel_gameplay("Jump3")
		
		PlayerCharacter.JumpType.WALL:
			travel_gameplay("WallJump")
			# clear wall slide choice so we don't immediately return to it
			wall_slide_animation = ""
		
		_:
			travel_gameplay("Jump")


func _on_landed():
	if character.in_ground_pound_recovery:
		return

	if is_crouching():
		travel_gameplay("SquatLand")
	else:
		travel_gameplay("WalkBlendSpace1D")


func _on_spin_started():
	travel_gameplay("SpinJump")


func _on_dive_started():
	travel_gameplay("HeadSlidingStart")


func _on_ground_pound_started():
	travel_gameplay("HipDropStart")


func _on_ground_pound_landed():
	travel_gameplay("HipDropLand")


func _on_crouch_started():
	if character.get_horizontal_velocity().length() > slide_speed_threshold:
		return

	travel_gameplay("SquatStart")


func _on_crouch_ended():
	if !character.is_on_floor():
		return
	travel_gameplay("SquatEnd")


func travel_gameplay(state: String):
	if current_gameplay_state == state:
		return

	if debug_print_animation:
		print(
			"[ANIM] ",
			current_gameplay_state,
			" -> ",
			state
		)

	current_gameplay_state = state
	gameplay_playback.travel(state)
	current_anim = state


func is_crouching() -> bool:
	return (
		character.movement_mode
		== PlayerCharacter.MovementMode.CROUCHED
		or character.ground_pounding
		or character.in_ground_pound_recovery
	)
