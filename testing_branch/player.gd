extends CharacterBody3D
class_name CharacterController

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

@export var crouch_speed := 5.0
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

@export var rotation_speed := 12.0
@export var hard_turn_angle := 130.0

@export var ground_pound_freeze_time := 0.15
@export var ground_pound_recovery_time := 0.2
@export var ground_pound_jump_boost := 1.25
var ground_pound_freeze_timer := 0.0
var ground_pound_recovery_timer := 0.0
var in_ground_pound_recovery := false

# MOMENTUM
@export_category("Momentum")

@export var slide_threshold := 8.0
@export var slide_friction := 4.0

@export var dive_force := 12.0
@export var dive_air_control := 0.15
var used_dive = false

# SPIN
var used_air_spin := false
@export var spin_upward_velocity := 10.0
@export var spin_horizontal_boost := 2.5
@export var spin_air_control := 0.65
@export var spin_duration := 0.125
@export var spin_start_damping := 0.25
@export var spin_rise_force := 22.0
@export var spin_max_upward_speed := 9.0

var spinning := false
var spin_timer := 0.0

@export var ground_pound_force := 35.0

@export var wall_slide_speed := 3.0
@export var wall_jump_force := 12.0
@export var wall_jump_height := 12.0

# TIMERS

@export_category("Buffers")
@export var coyote_time := 0.15
@export var jump_buffer_time := 0.15

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var ground_pound_jump_buffer := 0.0
@export var ground_pound_jump_buffer_time := 0.2

# ACTION FLAGS
var sliding := false
var diving := false
var ground_pounding := false
var wall_sliding := false

var stunned := false

# INPUT
var input_direction := Vector3.ZERO

# REFERENCES
@onready var camera := $"../Camera"

# MAIN LOOP
func _physics_process(delta):
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
	move_and_slide()

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
	ground_pound_jump_buffer -= delta
	
			
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	jump_buffer_timer -= delta


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

		MovementMode.LEDGE_GRAB:
			ledge_move(delta)

		MovementMode.FROZEN:
			frozen_move(delta)

# GROUND
func ground_move(delta):
	if in_ground_pound_recovery:
		return
	var desired_velocity := input_direction * max_ground_speed
	var horizontal := get_horizontal_velocity()
	var turn_angle := get_turn_angle()
	var hard_turn := (
		input_direction.length() > 0.05 and
		turn_angle > hard_turn_angle
	)
	
	if hard_turn:
		# instant brake
		horizontal = horizontal.move_toward(Vector3.ZERO, ground_friction * 4.0 * delta)
		# slight forward re-engage (prevents full dead stop feel)
		horizontal += input_direction * ground_acceleration * 0.25 * delta
	else:
		if input_direction.length() > 0.01:

			horizontal = horizontal.move_toward(
				desired_velocity,
				ground_acceleration * delta
			)
		else:
			horizontal = horizontal.move_toward(
				Vector3.ZERO,
				ground_friction * delta
			)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		jump()

# CROUCH
func crouch_move(delta):
	var horizontal := get_horizontal_velocity()
	var desired_velocity := input_direction * crouch_speed
	if horizontal.length() > slide_threshold:
		sliding = true
		horizontal = horizontal.move_toward(
			Vector3.ZERO,
			slide_friction * delta
		)
	else:
		sliding = false
		horizontal = horizontal.move_toward(
			desired_velocity,
			crouch_acceleration * delta
		)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

# AIR
func air_move(delta):
	var horizontal := get_horizontal_velocity()
	var control := air_acceleration

	if diving:
		control *= dive_air_control

	if spinning:
		control *= spin_air_control

	horizontal += input_direction * control * delta

	if horizontal.length() > max_air_speed:
		horizontal = horizontal.normalized() * max_air_speed

	horizontal = horizontal.move_toward(
		Vector3.ZERO,
		air_drag * delta
	)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


# STUN
func stunned_move(delta):
	var horizontal := get_horizontal_velocity()
	horizontal = horizontal.move_toward(
		Vector3.ZERO,
		10.0 * delta
	)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

# LEDGE
func ledge_move(_delta):
	velocity = Vector3.ZERO

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
	# SPIN / DIVE
	if Input.is_action_just_pressed("dive") :
		#dive
		if ground_pounding and !used_dive:
			ground_pounding = false
			diving = true
			used_dive = true
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
		elif movement_mode == MovementMode.AIRBORNE and !spinning and !wall_sliding and !used_air_spin:
			spinning = true
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
	if Input.is_action_just_pressed("crouch") and !spinning:
		if movement_mode == MovementMode.AIRBORNE and !ground_pounding:
			ground_pounding = true
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
		!spinning and !ground_pounding
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
	in_ground_pound_recovery = false
	ground_pound_recovery_timer = 0.0

	ground_pounding = false
	diving = false
	spinning = false

	velocity.x *= 0.35
	velocity.z *= 0.35

	velocity.y = jump_velocity * ground_pound_jump_boost

	jump_hold_timer = jump_hold_time
	jump_held = true

# JUMP
func jump():
	velocity.y = jump_velocity
	jump_hold_timer = jump_hold_time
	jump_held = true

	jump_buffer_timer = 0.0
	coyote_timer = 0.0

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
	if input_direction.length() < 0.05:
		return

	var target_angle := atan2(
		-input_direction.x,
		-input_direction.z
	)

	var turn_speed := rotation_speed
	if diving:
		turn_speed *= 3.0
	elif !is_on_floor():
		turn_speed *= 0.35

	rotation.y = lerp_angle(
		rotation.y,
		target_angle,
		turn_speed * delta
	)

# HELPERS
func get_horizontal_velocity() -> Vector3:
	return Vector3(
		velocity.x,
		0.0,
		velocity.z
	)
