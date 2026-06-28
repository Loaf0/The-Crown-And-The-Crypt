extends CharacterBody3D
class_name PlayerCharacter

signal jumped(jump_type)
signal landed

signal spin_started
signal spin_finished

signal dive_started

signal bonk_started
signal bonk_recovery_started
signal bonk_recovery_finished

signal ground_pound_started
signal ground_pound_landed

signal crouch_started
signal crouch_ended

# Debug
@export var debug_print_jumps := true

enum JumpType {
	NORMAL,
	SECOND,
	THIRD,
	CROUCH,
	GROUND_POUND,
	WALL
}

var last_jump_type: JumpType = JumpType.NORMAL

enum MovementMode {
	GROUNDED,
	CROUCHED,
	AIRBORNE,
	STUNNED,
	LEDGE_GRAB,
	FROZEN
}

# MOVEMENT MODE
@export var movement_mode := MovementMode.AIRBORNE

# CORE MOVEMENT
@export_category("Movement")

@export var max_ground_speed := 10.0
@export var ground_acceleration := 40.0
@export var ground_friction := 30.0

@export var crouch_speed := 1.25
@export var crouch_acceleration := 18.0
@export var crouch_friction := 10.0

@export var air_acceleration := 24.0
@export var air_drag := 1.5
@export var max_air_speed := 12.0

@export var gravity := 32.0
@export var max_fall_speed := 35.0

@export var jump_velocity := 12.5
@export var jump_hold_time := 0.15
@export var jump_hold_force := 50.0
@export var rise_gravity := 60.0
@export var fall_gravity := 65.0
@export var apex_gravity := 20.0

var jump_hold_timer := 0.0
var jump_held := false

@export_category("Jump Variants")

@export var second_jump_multiplier := 1.05
@export var third_jump_multiplier := 1.35

@export var crouch_jump_multiplier := 1.2
@export var ground_pound_jump_multiplier := 1.25
var crouch_jump_air_control_lock := 0.0

@export var crouch_jump_air_control_reduction := 0.25
@export var crouch_jump_air_lock_time := 0.35

var jump_count := 0
var last_jump_was_ground_pound := false
var last_jump_was_crouch := false
var last_jump_was_air := false

@export var rotation_speed := 12.0
@export var hard_turn_angle := 130.0

@export var ground_pound_freeze_time := 0.15
@export var ground_pound_recovery_time := 0.2
@export var ground_pound_jump_boost := 1.25
var ground_pound_freeze_timer := 0.0
var ground_pound_recovery_timer := 0.0
var in_ground_pound_recovery := false

@export var roll_out_time := 0.5
var roll_out_timer := 0.0
var in_roll_out := false

@export var bonk_wall_bounce_factor := 0.6 
@export var bonk_ground_bounce_factor := 0.2
@export var bonk_min_bounce_speed := 2.0

@export var bonk_recovery_time := 0.5

var bonk_recovery_timer := 0.0
var bonk_bouncing := false

# MOMENTUM
@export_category("Momentum")

@export var slide_threshold := 8.0
@export var slide_friction := 8.0

@export var dive_force := 12.0
@export var dive_air_control := 0.15
var used_dive = false

# SPIN
var used_air_spin := false
@export var spin_upward_velocity := 12.0
@export var spin_horizontal_boost := 3.5
@export var spin_air_control := 0.85
@export var spin_duration := 0.15
@export var spin_start_damping := 0.18
@export var spin_rise_force := 22.0
@export var spin_max_upward_speed := 9.0

@export var dive_spin_lock_time := 0.15
var dive_spin_lock_timer := 0.0

var spinning := false
var spin_timer := 0.0

@export var ground_pound_force := 35.0
var did_ground_pound_jump := false
@export var wall_slide_speed := 3.0
@export var wall_jump_force := 12.0
@export var wall_jump_height := 12.0

# TIMERS

@export_category("Buffers")
@export var coyote_time := 0.15
@export var jump_buffer_time := 0.15

var ledge_grab_cooldown := 0.0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var ground_pound_jump_buffer := 0.0
@export var ground_pound_jump_buffer_time := 0.2



# ACTION FLAGS
var sliding := false
var diving := false
var ground_pounding := false
var wall_sliding := false
var was_on_floor := false
var was_crouching := false
var stunned := false

@onready var bonk_cast : RayCast3D = $BonkCast
@onready var raycast_head_forward: RayCast3D = $RayCastLedgeCheck/RaycastHead
@onready var raycast_ledge_down: RayCast3D = $RayCastLedgeCheck/RaycastHead/RaycastLedge
@onready var ledge_marker: MeshInstance3D = $RayCastLedgeCheck/RaycastHead/RaycastLedge/LedgeMarker


# INPUT
var input_direction := Vector3.ZERO

# REFERENCES
const CAMERA_SCENE := preload("res://scenes/player/camera.tscn")
var camera : Node3D = null

func _enter_tree():
	set_multiplayer_authority(_get_authority_id())


func _get_authority_id() -> int:
	var authority_source: Node = self
	while authority_source != null:
		if str(authority_source.name).is_valid_int():
			return str(authority_source.name).to_int()
		authority_source = authority_source.get_parent()

	return 0

func _ready():
	add_to_group("players")

	if !is_multiplayer_authority():
		set_process(false)
		set_physics_process(false)
		$Control.queue_free()
		$Blind.queue_free()
	else:
		_spawn_camera()
	
func _spawn_camera():
	var temp_cam  = CAMERA_SCENE.instantiate()
	add_sibling(temp_cam )
	temp_cam .player = self
	camera = temp_cam.camera

# MAIN LOOP
func _physics_process(delta):
	if(!is_multiplayer_authority()):
		return
		
	$Control/Label.text = """
	Velocity : (%.2f, %.2f, %.2f)
	Position : (%.2f, %.2f, %.2f)
	State : %s
	""" % [
	velocity.x, velocity.y, velocity.z,
	global_position.x, global_position.y, global_position.z,
	MovementMode.keys()[movement_mode]
	]
	
	handle_input()
	update_timers(delta)
	update_mode()
	apply_gravity(delta)
	apply_jump_hold(delta)
	update_spin(delta)
	apply_actions(delta)
	update_ground_pound_recovery(delta)
	apply_movement(delta)
	rotate_character(delta)
	update_bonk_bounce(delta)
	update_bonk_recovery(delta)
	move_and_slide()
	
	detect_animation_events()

# INPUT
func handle_input():
	var input_2d := Input.get_vector(
		"move_left",
		"move_right",
		"move_back",
		"move_forward"
	)

	if camera:
		var cam_forward = -camera.global_transform.basis.z
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		var cam_right = camera.global_transform.basis.x
		cam_right.y = 0
		cam_right = cam_right.normalized()
		input_direction = (
			cam_forward * input_2d.y +
			cam_right * input_2d.x
		).normalized()
		
	if Input.is_action_pressed("jump"):
		if is_on_floor():
			jump_held = true
	else:
		jump_held = false
	
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
		if in_ground_pound_recovery:
			ground_pound_jump_buffer = ground_pound_jump_buffer_time


# TIMERS
func update_timers(delta):
	dive_spin_lock_timer = max(dive_spin_lock_timer - delta, 0.0)
	crouch_jump_air_control_lock = max(crouch_jump_air_control_lock - delta, 0.0)
	
	if is_on_floor():
		jump_count = 0
		last_jump_was_ground_pound = false
		last_jump_was_crouch = false
		last_jump_was_air = false
	
	ground_pound_jump_buffer -= delta
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	jump_buffer_timer -= delta
	
	ledge_grab_cooldown = max(ledge_grab_cooldown - delta, 0.0)


# MODE LOGIC
func update_mode():
	if movement_mode == MovementMode.FROZEN:
		return
	if stunned:
		movement_mode = MovementMode.STUNNED
		return
	if ground_pounding or in_ground_pound_recovery:
		movement_mode = MovementMode.AIRBORNE
		return
	if !is_on_floor():
		movement_mode = MovementMode.AIRBORNE
		return
	if Input.is_action_pressed("crouch"):
		movement_mode = MovementMode.CROUCHED
		return
	movement_mode = MovementMode.GROUNDED

# MOVEMENT
func apply_movement(delta):
	match movement_mode:
		MovementMode.GROUNDED:
			ground_move(delta)
		MovementMode.CROUCHED:
			crouch_move(delta)
		MovementMode.AIRBORNE:
			air_move(delta)
		MovementMode.STUNNED:
			stunned_move(delta)
		#MovementMode.LEDGE_GRAB:
			#ledge_move(delta)
		MovementMode.FROZEN:
			frozen_move(delta)

# GROUND
func ground_move(delta):
	if in_ground_pound_recovery:
		return
	var desired_velocity := input_direction * max_ground_speed
	var horizontal := get_horizontal_velocity()
	var turn_angle := get_turn_angle()
	var hard_turn := (input_direction.length() > 0.05 and turn_angle > hard_turn_angle)
	
	if hard_turn:
		# instant brake
		horizontal = horizontal.move_toward(Vector3.ZERO, ground_friction * 4.0 * delta)
		# slight forward re-engage (prevents full dead stop feel)
		horizontal += input_direction * ground_acceleration * 0.25 * delta
	else:
		if input_direction.length() > 0.01:
			horizontal = horizontal.move_toward(desired_velocity, ground_acceleration * delta)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, ground_friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		if movement_mode == MovementMode.CROUCHED:
			last_jump_was_crouch = true
		else:
			last_jump_was_crouch = false
		jump()

# CROUCH
func crouch_move(delta):
	var horizontal := get_horizontal_velocity()
	var desired_velocity := input_direction * crouch_speed
	if horizontal.length() > slide_threshold:
		sliding = true
		horizontal = horizontal.move_toward(Vector3.ZERO, slide_friction * delta)
	else:
		sliding = false
		horizontal = horizontal.move_toward(desired_velocity, crouch_acceleration * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		last_jump_was_crouch = true
		jump()

# AIR
func air_move(delta):
	var horizontal := get_horizontal_velocity()
	var control := air_acceleration

	if crouch_jump_air_control_lock > 0.0:
		control *= crouch_jump_air_control_reduction

	if diving:
		control *= dive_air_control
		if bonk_cast.is_colliding():
			enter_bonked_stun(bonk_cast.get_collision_normal())

	if spinning:
		control *= spin_air_control

	horizontal += input_direction * control * delta

	if horizontal.length() > max_air_speed:
		horizontal = horizontal.normalized() * max_air_speed

	horizontal = horizontal.move_toward(Vector3.ZERO, air_drag * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


# STUN
func stunned_move(delta):
	var horizontal := get_horizontal_velocity()
	horizontal = horizontal.move_toward(Vector3.ZERO, 3.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

func update_bonk_bounce(_delta):
	if !stunned or !bonk_bouncing:
		return

	if is_on_wall() and velocity.length() > bonk_min_bounce_speed:
		var n := get_wall_normal()
		velocity = velocity.bounce(n)
		velocity.x *= bonk_wall_bounce_factor
		velocity.z *= bonk_wall_bounce_factor

	if is_on_floor():
		velocity.y = abs(velocity.y) * bonk_ground_bounce_factor
		if bonk_bouncing and abs(velocity.y) < bonk_min_bounce_speed:
			if bonk_bouncing:
				bonk_recovery_started.emit()
			bonk_bouncing = false
			velocity.y = 0.0

func update_bonk_recovery(delta):
	if !stunned:
		return
	if bonk_bouncing:
		return
	bonk_recovery_timer -= delta

	velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)

	if bonk_recovery_timer <= 0.0 and is_on_floor():
		end_bonk_recovery()

func end_bonk_recovery():
	bonk_recovery_finished.emit()
	stunned = false
	bonk_bouncing = false
	movement_mode = MovementMode.GROUNDED

	velocity = Vector3.ZERO


# LEDGE
func ledge_move(_delta):
	velocity = Vector3.ZERO

	if Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		movement_mode = MovementMode.AIRBORNE
		return

	if Input.is_action_just_pressed("crouch"):
		movement_mode = MovementMode.AIRBORNE
		return

# FROZEN
func frozen_move(_delta):
	velocity = Vector3.ZERO


# GRAVITY
func apply_gravity(delta):
	if movement_mode == MovementMode.LEDGE_GRAB: return
	if is_on_floor() or spinning: return

	var g := rise_gravity

	if velocity.y < 0.0:
		g = fall_gravity
	elif abs(velocity.y) < 2.0:
		g = 10 + apex_gravity * (1 - velocity.y / 2.0)

	velocity.y -= g * delta
	velocity.y = max(velocity.y, -max_fall_speed)


# ACTIONS
func apply_actions(delta):
	if stunned:
		return
	
	# SPIN / DIVE
	if Input.is_action_just_pressed("dive"):
		#dive
		if ground_pounding and !used_dive:
			dive_spin_lock_timer = dive_spin_lock_time
			ground_pounding = false
			diving = true
			used_dive = true
			dive_started.emit()
			var dive_direction := input_direction
			if dive_direction.length() <= 0.01:
				dive_direction = get_horizontal_velocity().normalized()
			if dive_direction.length() <= 0.01:
				dive_direction = -camera.global_transform.basis.z.normalized()
			dive_direction.y = 0.0
			dive_direction = dive_direction.normalized()
			velocity.x = dive_direction.x * dive_force
			velocity.z = dive_direction.z * dive_force
			velocity.y = 2.0
		#spin
		elif movement_mode == MovementMode.AIRBORNE and !spinning and !wall_sliding and !used_air_spin and dive_spin_lock_timer <= 0.0:
			spinning = true
			spin_started.emit()
			used_air_spin = true
			used_dive = false
			spin_timer = spin_duration

			velocity.x *= spin_start_damping
			velocity.z *= spin_start_damping

			if velocity.y > 0.0:
				velocity.y *= 0.25
			else:
				velocity.y = 0

			if input_direction.length() > 0.0:
				velocity += input_direction * spin_horizontal_boost
	
	if is_on_floor():
		used_dive = false
		used_air_spin = false
		spinning = false
		diving = false
	
	# GROUND POUND
	if Input.is_action_just_pressed("crouch") and !spinning and !diving:
		if movement_mode == MovementMode.AIRBORNE and !ground_pounding:
			ground_pounding = true
			ground_pound_started.emit()
			ground_pound_freeze_timer = ground_pound_freeze_time
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y = 0.0
	if ground_pounding:
		if ground_pound_freeze_timer > 0.0:
			ground_pound_freeze_timer -= delta
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y = 0.0
		else:
			velocity.y = -ground_pound_force

	if ground_pounding and is_on_floor():
		ground_pounding = false
		in_ground_pound_recovery = true
		ground_pound_recovery_timer = ground_pound_recovery_time
		ground_pound_landed.emit()

	# WALL SLIDE
	var wall_normal := get_wall_normal()

	var pushing_into_wall := (
		input_direction.length() > 0.05 and
		input_direction.dot(-wall_normal) > 0.6
	)

	wall_sliding = (
		!is_on_floor() and
		is_on_wall() and
		velocity.y < 0.0 and
		pushing_into_wall and 
		!spinning and !ground_pounding and !diving
	)

	if wall_sliding:
		# slow vertical fall
		velocity.y = max(velocity.y, -wall_slide_speed)

		# fast horizontal damping
		var horizontal := get_horizontal_velocity()

		# remove velocity INTO the wall first
		horizontal = horizontal.slide(wall_normal)

		# then aggressively damp remaining tangential motion
		horizontal = horizontal.move_toward(Vector3.ZERO, 40.0 * delta)

		velocity.x = horizontal.x
		velocity.z = horizontal.z

	# WALL JUMP

	if wall_sliding:
		if Input.is_action_just_pressed("jump"):
			wall_normal = get_wall_normal()
			velocity = wall_normal * wall_jump_force
			velocity.y = wall_jump_height
			jumped.emit(JumpType.WALL)

	#if movement_mode == MovementMode.AIRBORNE:
		#if can_grab_ledge():
			#enter_ledge_hang()
			#return

func detect_animation_events():
	if !was_on_floor and is_on_floor():
		landed.emit()

		jump_count = 0
		last_jump_was_ground_pound = false
		last_jump_was_crouch = false
		last_jump_was_air = false

	var crouching := (
		movement_mode == MovementMode.CROUCHED
	)

	if crouching and !was_crouching:
		crouch_started.emit()

	if !crouching and was_crouching:
		crouch_ended.emit()

	was_on_floor = is_on_floor()
	was_crouching = crouching


func enter_bonked_stun(hit_normal: Vector3):
	bonk_started.emit()
	stunned = true
	movement_mode = MovementMode.STUNNED

	bonk_bouncing = true
	bonk_recovery_timer = bonk_recovery_time

	var v := velocity
	var reflected := v.bounce(hit_normal)

	reflected.x *= bonk_wall_bounce_factor
	reflected.z *= bonk_wall_bounce_factor

	velocity = reflected

	if velocity.y < 2.0:
		velocity.y = 4.0

func update_spin(delta):
	if !spinning:
		return

	spin_timer -= delta

	var spin_progress := 1.0 - (spin_timer / spin_duration)
	var upward_strength = lerp(0.15, 1.0, spin_progress)

	velocity.y += spin_rise_force * upward_strength * delta
	velocity.y = min(velocity.y, spin_max_upward_speed)

	if spin_timer <= 0.0:
		spinning = false
		spin_finished.emit()

func update_ground_pound_recovery(delta):
	if !in_ground_pound_recovery:
		return

	ground_pound_recovery_timer -= delta

	ground_pound_jump_buffer -= delta

	velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)

	if ground_pound_jump_buffer > 0.0 and is_on_floor():
		consume_ground_pound_jump()
		return

	if ground_pound_recovery_timer <= 0.0:
		in_ground_pound_recovery = false

func consume_ground_pound_jump():
	ground_pound_jump_buffer = 0.0
	did_ground_pound_jump = true
	in_ground_pound_recovery = false
	ground_pound_recovery_timer = 0.0

	ground_pounding = false
	diving = false
	spinning = false

	last_jump_was_ground_pound = true
	jump_count = 1

	velocity.x *= 0.35
	velocity.z *= 0.35

	velocity.y = jump_velocity * ground_pound_jump_boost

	jump_hold_timer = jump_hold_time
	jump_held = true
	last_jump_type = JumpType.GROUND_POUND
	if debug_print_jumps:
		print("[Player] consume_ground_pound_jump: emitting jumped with type:", last_jump_type)
	jumped.emit(last_jump_type)
	
# JUMP
func jump():
	var multiplier := 1.0
	last_jump_type = JumpType.NORMAL
	if last_jump_was_ground_pound:
		multiplier = ground_pound_jump_multiplier
		last_jump_type = JumpType.GROUND_POUND
	elif last_jump_was_crouch:
		multiplier = crouch_jump_multiplier
		last_jump_type = JumpType.CROUCH

		crouch_jump_air_control_lock = crouch_jump_air_lock_time

		var h := get_horizontal_velocity()

		if h.length() > 0.1:
			h = h.normalized() * crouch_speed

		velocity.x = h.x
		velocity.z = h.z
	else:
		jump_count += 1
		if jump_count == 2:
			multiplier = second_jump_multiplier
			last_jump_type = JumpType.SECOND
		elif jump_count >= 3:
			multiplier = third_jump_multiplier
			last_jump_type = JumpType.THIRD
		else:
			last_jump_type = JumpType.NORMAL
	velocity.y = jump_velocity * multiplier
	jump_hold_timer = jump_hold_time
	jump_held = true
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	last_jump_was_crouch = false
	last_jump_was_ground_pound = false

	# Emit specific jump signals for subsystems that listen for them,
	# then emit the generic `jumped` event used by the animation controller.
	match last_jump_type:
		JumpType.SECOND:
			if debug_print_jumps: print("[Player] jump: type SECOND, last_jump_type:", last_jump_type, "jump_count:", jump_count)
		JumpType.THIRD:
			if debug_print_jumps: print("[Player] jump: type THIRD, last_jump_type:", last_jump_type, "jump_count:", jump_count)
		JumpType.CROUCH:
			if debug_print_jumps: print("[Player] jump: type CROUCH, last_jump_type:", last_jump_type)
		JumpType.GROUND_POUND:
			if debug_print_jumps: print("[Player] jump: type GROUND_POUND, last_jump_type:", last_jump_type)

	if debug_print_jumps: print("[Player] emitting jumped with type:", last_jump_type)
	jumped.emit(last_jump_type)

func apply_jump_hold(delta):
	if jump_held and jump_hold_timer > 0.0 and velocity.y > 0.0:
		velocity.y += jump_hold_force * delta
		jump_hold_timer -= delta
	else:
		jump_held = false

	if Input.is_action_just_released("jump"):
		jump_held = false

# ROTATION
func get_turn_angle() -> float:
	var v := get_horizontal_velocity()
	if v.length() < 0.1 or input_direction.length() < 0.1:
		return 0.0

	return rad_to_deg(
		acos(clamp(v.normalized().dot(input_direction.normalized()), -1.0, 1.0))
	)

func rotate_character(delta):
	if stunned:
		return
	
	var target_angle: float
	if diving:
		var v := get_horizontal_velocity()
		if v.length() > 0.05:
			target_angle = atan2(-v.x, -v.z)
		else:
			target_angle = rotation.y
	else:
		if input_direction.length() < 0.05:
			return
		target_angle = atan2(-input_direction.x, -input_direction.z)

	var turn_speed := rotation_speed

	if diving:
		turn_speed *= 4.0
	elif !is_on_floor():
		turn_speed *= 0.35

	rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)

func enter_ledge_hang():
	movement_mode = MovementMode.LEDGE_GRAB

	velocity = Vector3.ZERO

	var ledge_pos = get_ledge_position()

	global_position = ledge_pos + Vector3.DOWN * 1.2 + global_transform.basis.z * 0.4

# HELPERS

func get_ledge_position() -> Vector3:
	return raycast_ledge_down.get_collision_point()

func can_grab_ledge() -> bool:
	if is_on_floor():
		return false

	if velocity.y > 0.0:
		return false

	if !raycast_head_forward:
		return false

	if !raycast_ledge_down:
		return false

	if raycast_head_forward.is_colliding():
		return false

	if !raycast_ledge_down.is_colliding():
		return false

	return true

func get_horizontal_velocity() -> Vector3:
	return Vector3(
		velocity.x,
		0.0,
		velocity.z
	)
