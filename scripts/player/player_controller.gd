extends CharacterBody3D
class_name Character

enum State {
	IDLE, WALK, RUN, JUMP, FALL, GROUND_POUND, DIVE, 
	WALL_SLIDE, WALL_JUMP, LAND, GROUND_POUND_RECOVERY, 
	BONK, CROUCH, SLIDE, LONG_JUMP, EMOTE1
}

@onready var smoke_emit = $SmokeParticle
@onready var spark_emit = $SparkParticle
@export var target_position : Vector3
var max_desync_distance = 5.0

@export_category("General")
@export var gravity := -12.0

@export_category("Jumping")
@export var jump_force := 7.0
@export var jump_extra_force := 3.0
@export var jump_hold_time := 0.2
@export var apex_gravity = 0.8
@export var fall_multiplier := 1.8
@export var low_jump_multiplier := 2.8
@export var max_fall_speed := -20.0
@export var coyote_time_max := 0.15
@export var long_jump_forward_speed = 14.0
@export var long_jump_upward_speed = 10.0

@export_category("Movement")
@export var move_speed := 7.0
@export var run_speed = 9.0
@export var walk_speed = 7.0
@export var acceleration := 15.0
@export var momentum_acceleration := 3.0
@export var momentum_deceleration := 30.0
@export var ground_deceleration := 30.0 
@export var ground_acceleration := 15.0
@export var air_deceleration := 0.0
@export var air_acceleration := 8.0 
@export var standard_air_influence := 0.3
var air_influence := standard_air_influence
@export var max_snap_angle := 45.0
@export var turn_slowdown_threshold := 110.0
@export var turn_slowdown_multiplier := 0.9
var slide_speed = 10.0
var slide_accel = 20.0

@export_category("Ground Pound")
@export var ground_pound_speed := -16.0
@export var ground_pound_acceleration := 6.0 
@export var ground_pound_delay := 0.2 
var ground_pound_timer := 0.0
var ground_pound_started := false

@export_category("Dive")
@export var dive_horizontal_speed := 6.0
@export var dive_upward_boost := 7.0
@export var dive_air_modifier := 0.1
@export var max_dive_duration := 2.5
@export var dive_turn_speed := 2.0
var dive_timer := 0.0
var dive_air_influence = standard_air_influence * dive_air_modifier

@export var bonk_stun_time := 0.8
@export var dive_bonk_window := 0.5
var bonk_timer := 0.0
var stunned_timer := 0.0
var just_bonked = true
var just_long_jumped = true

@export_category("Ground Pound Recovery")
@export var ground_pound_recovery_time := 0.25
@export var ground_pound_jump_multiplier := 1.4
var recovery_timer := 0.0

@export_category("Wall Interactions")
@export var wall_slide_min_speed := -1.0
@export var wall_slide_max_speed := -6.0
@export var wall_jump_force := Vector3(-8.0, 10, 0)
@export var wall_slide_lerp_duration := 3.0
@export var wall_jump_input_lock_duration := 0.15
var wall_jump_lock_timer := 0.0
var wall_slide_timer := 0.0
var wall_jump_count := 0
@export var max_wall_jumps := 12
@export var free_wall_jumps := 6


var walk_time: float = 0.0
const TIME_TO_RUN: float = 1.5

@export_category("Buffers")
@export var jump_buffer_time := 0.15
@export var dive_buffer_time := 0.15
@export var wall_jump_buffer_time := 0.15
@export var wall_coyote_time := 0.05
var wall_coyote_timer := 0.0
var was_on_wall := false
var wall_jump_buffer_timer := 0.0
var dive_buffer_timer := 0.0
var jump_buffer_timer := 0.0
var coyote_timer := 0.0

@onready var camera

var direction: Vector3
var current_speed := 0.0
var jump_hold_timer := 0.0
var jump_held := false
var just_dived = false
@onready var bonk_cast = $BonkCast

var blind_deaf_dumb = false
@onready var blind = $Blind

@export var current_state: State = State.FALL

@export var team : String 
@onready var tag_box = $TagBox

@onready var nickname: Label3D = $PlayerNick/Nickname

@onready var raycast_facing_wall = $RayCastFacingWall

@export_category("Objects")
@export var _body: Node3D = null

@export_category("Skin Colors")
@export var blue_texture : CompressedTexture2D
@export var yellow_texture : CompressedTexture2D
@export var green_texture : CompressedTexture2D
@export var red_texture : CompressedTexture2D
@export var indigo_texture : CompressedTexture2D
@export var forest_texture : CompressedTexture2D
@export var midnight_texture : CompressedTexture2D
@export var noir_texture : CompressedTexture2D
@export var ourple_texture : CompressedTexture2D
@export var corn_texture : CompressedTexture2D
@export var rust_texture : CompressedTexture2D
@export var pink_texture : CompressedTexture2D
@export var orange_texture : CompressedTexture2D

var blind_timer := 0.0
var is_blind_timer_active := false

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())
	if is_multiplayer_authority():
		camera = $"../Camera"
		camera.camera.current = true
		camera.set_player(self)
	else:
		$Control.hide()

func _ready():
	floor_snap_length = 1.0
	
	if multiplayer.is_server():
		pass

func _physics_process(delta):
	$PlayerNick/Team.text = team if team != "hider" else ""
	
	if !is_multiplayer_authority():
		nickname.visible = (Global.local_player_team == team)
		_body.animate(current_state)
		var lerp_speed = 10.0
		position = position.lerp(target_position, clamp(delta * lerp_speed, 0.0, 1.0))
		if position.distance_to(target_position) > max_desync_distance:
			position = target_position
		return
	
	target_position = position
	$PlayerNick/Team.text = team if team != "hider" else ""
	Global.local_player_team = team
	nickname.hide()
	
	var current_scene = get_tree().get_current_scene()
	if current_scene and current_scene.has_method("is_chat_visible") and current_scene.is_chat_visible() and is_on_floor():
		freeze()
		_body.animate(current_state)
		return
	
	if blind_deaf_dumb:
		blind.visible = true
		return
	else:
		blind.visible = false
	
	update_debug_menu()
	handle_input()
	apply_gravity(delta)
	update_timers(delta)
	update_state(delta)
	move_character(delta)
	move_and_slide()
	
	_body.animate(current_state)
	_check_fall_and_respawn()

func update_timers(delta):
	# Wall jump coyote time
	var on_wall_now = is_touching_wall() and is_moving_into_wall()
	if !on_wall_now and was_on_wall:
		wall_coyote_timer = wall_coyote_time
	if wall_coyote_timer > 0.0:
		wall_coyote_timer -= delta
	was_on_wall = on_wall_now

	# jump coyote time
	if !is_on_floor():
		coyote_timer -= delta
	else:
		coyote_timer = coyote_time_max

	jump_buffer_timer -= delta
	dive_buffer_timer -= delta
	wall_jump_buffer_timer -= delta

	if is_on_floor():
		wall_jump_buffer_timer = 0.0

	if jump_held and jump_hold_timer > 0.0 and velocity.y > 0:
		velocity.y += jump_extra_force * delta
		jump_hold_timer -= delta
	else:
		jump_held = false

	if Input.is_action_just_released("jump"):
		jump_held = false
	
	#blinding
	if is_blind_timer_active:
		blind_timer -= delta
		if blind_timer <= 0.0:
			is_blind_timer_active = false
			set_blind_deaf_dumb(false)


func update_state(delta):
	if is_on_floor():
		wall_jump_count = 0

	match current_state:
		State.IDLE, State.WALK:
			if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
				jump()
			elif !is_on_floor():
				current_state = State.FALL
			elif direction.length() > 0.1:
				walk_time += delta
				if walk_time >= TIME_TO_RUN:
					current_state = State.RUN
				else:
					current_state = State.WALK
			else:
				current_state = State.IDLE
				walk_time = 0.0

			if Input.is_action_just_pressed("Emote1"):
				current_state = State.EMOTE1

			if Input.is_action_pressed("ground_pound"):
				current_state = State.CROUCH
		
		State.RUN:
			if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
				jump()
			elif !is_on_floor():
				current_state = State.FALL
			elif direction.length() > 0.1:
				current_state = State.RUN
			else:
				current_state = State.IDLE
				walk_time = 0.0

			if Input.is_action_just_pressed("Emote1"):
				current_state = State.EMOTE1

			if Input.is_action_pressed("ground_pound"):
				current_state = State.CROUCH
	
		State.JUMP:
			if velocity.y < 0:
				current_state = State.FALL
			elif Input.is_action_just_pressed("ground_pound"):
				current_state = State.GROUND_POUND
				ground_pound_started = false
				velocity.y = ground_pound_speed

		State.FALL:
			if is_on_floor():
				current_state = State.LAND if !Input.is_action_pressed("ground_pound") else State.CROUCH
			elif Input.is_action_just_pressed("ground_pound"):
				current_state = State.GROUND_POUND
				ground_pound_started = false
				velocity.y = ground_pound_speed
			elif jump_buffer_timer > 0.0 and coyote_timer > 0.0:
				jump()
			elif is_touching_wall() and is_moving_into_wall() and bonk_cast.is_colliding():
				current_state = State.WALL_SLIDE
				wall_slide_timer = 0.0
			


		State.GROUND_POUND:
			if !ground_pound_started:
				ground_pound_started = true
				ground_pound_timer = ground_pound_delay
				current_speed = 0
				velocity.y = 0 
			else:
				ground_pound_timer -= delta
				if ground_pound_timer <= 0.0:
					velocity.y = lerp(velocity.y, ground_pound_speed, ground_pound_acceleration * delta)
				else:
					velocity.y = 0
				if dive_buffer_timer > 0.0:
					current_state = State.DIVE
					just_dived = true
					dive_buffer_timer = 0.0
					ground_pound_started = false
				elif is_on_floor():
					current_state = State.GROUND_POUND_RECOVERY
					recovery_timer = ground_pound_recovery_time
					ground_pound_started = false

		State.DIVE:
			if just_dived:
				bonk_timer = dive_bonk_window
				dive_timer = 0.0
				perform_dive(delta)
			just_dived = false
			
			dive_timer += delta
			if dive_timer >= max_dive_duration:
				current_state = State.FALL
		
			if bonk_timer > 0.0:
				bonk_timer -= delta
				if bonk_detection():
					just_bonked = true
					current_state = State.BONK
					
			if is_on_floor():
				current_state = State.IDLE

		State.GROUND_POUND_RECOVERY:
			smoke_emit.emitting = true
			recovery_timer -= delta
			if jump_buffer_timer > 0.0:
				velocity.y = jump_force * ground_pound_jump_multiplier
				current_state = State.JUMP
				jump_hold_timer = jump_hold_time
				jump_held = true
			elif recovery_timer <= 0.0:
				current_state = State.LAND
		
		State.WALL_SLIDE:
			if is_on_floor():
				current_state = State.LAND
			elif !is_on_wall() or !is_moving_into_wall():
				current_state = State.FALL
			elif wall_jump_buffer_timer > 0.0:
				perform_wall_jump()
				current_state = State.WALL_JUMP
			else:
				wall_slide_timer += delta
				var t = clamp(wall_slide_timer / wall_slide_lerp_duration, 0, 1)
				slide_speed = lerp(wall_slide_min_speed, wall_slide_max_speed, t)
				if velocity.y < slide_speed:
					velocity.y = slide_speed
				velocity = Vector3(velocity.x * .9, velocity.y, velocity.z * .9)


		State.WALL_JUMP:
			if Input.is_action_just_pressed("ground_pound"):
				ground_pound_started = false
				current_state = State.GROUND_POUND
			if is_on_floor():
				current_state = State.LAND
			elif velocity.y < 0:
				current_state = State.FALL

		State.LAND:
			if direction.length() > 0.1:
				current_state = State.WALK
			else:
				current_state = State.IDLE
		
		State.BONK:
			if just_bonked:
				stunned_timer = bonk_stun_time
				bonk_timer = 0.0
				spark_emit.emitting = true

				var wall_normal = get_wall_normal()
				if wall_normal == Vector3.ZERO:
					var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
					if horizontal_vel.length() > 0:
						wall_normal = -horizontal_vel.normalized()
					else:
						wall_normal = -transform.basis.z
				velocity = wall_normal * 3.0
				velocity.y = 1.5
			just_bonked = false
			if is_on_floor():
				stunned_timer -= delta
				velocity.x = 0
				velocity.z = 0
				if stunned_timer <= 0.0:
					just_bonked = true
					current_state = State.LAND
		State.EMOTE1:
			if $"3DGodotRobot/AnimationPlayer".is_playing() and $"3DGodotRobot/AnimationPlayer".current_animation == "Emote1":
				return
			current_state = State.IDLE
		
		State.CROUCH:
			if !is_on_floor():
				current_state = State.FALL
				return

			if !Input.is_action_pressed("ground_pound"):
				current_state = State.IDLE
				return

			if Input.is_action_just_pressed("jump"): 
				if velocity.length() > 1.0:
					just_long_jumped = true
					current_state = State.LONG_JUMP
				else:
					velocity.y = jump_force * ground_pound_jump_multiplier
					current_state = State.JUMP
					jump_hold_timer = jump_hold_time
					jump_held = true
		
		State.LONG_JUMP:
			if just_long_jumped:
				var forward = -transform.basis.z.normalized()
				velocity = forward * long_jump_forward_speed
				velocity.y = long_jump_upward_speed
			just_long_jumped = false
			if(velocity.y < 0):
				current_state = State.FALL

func freeze():
	pass

func handle_input():
	if camera == null:
		return
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_back", "move_forward")

	var cam_basis = camera.global_transform.basis

	var cam_forward = -cam_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()

	var cam_right = cam_basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized()

	direction = (cam_forward * input_dir.y + cam_right * input_dir.x).normalized()

	if Input.is_action_just_pressed("spin"):
		dive_buffer_timer = dive_buffer_time
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
		wall_jump_buffer_timer = wall_jump_buffer_time 

func apply_gravity(delta):
	var is_rising = velocity.y > 0
	var is_falling = velocity.y < 0
	var at_apex = abs(velocity.y) < 2.0

	if is_falling:
		velocity.y += gravity * fall_multiplier * delta
	elif !jump_held and is_rising:
		velocity.y += gravity * low_jump_multiplier * delta
	elif at_apex:
		velocity.y += gravity * apex_gravity * delta
	else:
		velocity.y += gravity * delta
	
	velocity.y = max(velocity.y, max_fall_speed)

func move_character(delta):
	var tilt_strength = 8.0
	var tilt_return_strength = 15.0
	var forward_dir = -transform.basis.z.normalized()
	var right_dir
	var up_dir

	if is_on_floor():
		var floor_normal = get_floor_normal().normalized()
		var halfway_normal = Vector3.UP.slerp(floor_normal, 0.5).normalized()
		right_dir = forward_dir.cross(halfway_normal).normalized()
		up_dir = halfway_normal
	else:
		up_dir = transform.basis.y.lerp(Vector3.UP, delta * tilt_return_strength).normalized()
		right_dir = forward_dir.cross(up_dir).normalized()
		forward_dir = up_dir.cross(right_dir).normalized()

	var target_basis = Basis(right_dir, up_dir, -forward_dir)
	transform.basis = transform.basis.slerp(target_basis.orthonormalized(), delta * tilt_strength)

	var target_speed = run_speed if current_state == State.RUN else walk_speed
	move_speed = lerp(move_speed, target_speed, delta * 5.0)
	
	if current_state in [State.GROUND_POUND, State.GROUND_POUND_RECOVERY]:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	if current_state == State.BONK or current_state == State.EMOTE1 or current_state == State.CROUCH:
		direction = Vector3.ZERO

	if current_state == State.DIVE:
		air_influence = dive_air_influence
	else:
		air_influence = standard_air_influence
		
	momentum_deceleration = ground_deceleration if is_on_floor() else air_deceleration
	momentum_acceleration = ground_acceleration if is_on_floor() else air_acceleration

	if current_state == State.CROUCH:
		momentum_deceleration *= 0.1

	var input_magnitude = direction.length()
	var move_direction = direction.normalized() if input_magnitude > 0.05 else Vector3.ZERO
	
	if input_magnitude > 0.05:
		var target_angle = atan2(-move_direction.x, -move_direction.z)
		var angle_diff = abs(rad_to_deg(wrapf(target_angle - rotation.y, -PI, PI)))
		var turning_hard = angle_diff > turn_slowdown_threshold
		var slowdown = turn_slowdown_multiplier if turning_hard else 1.0
		current_speed = lerp(current_speed, move_speed * slowdown, momentum_acceleration * delta)
		var turn_speed = dive_turn_speed if current_state == State.DIVE else 10.0
		rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)
	else:
		current_speed = lerp(current_speed, 0.0, momentum_deceleration * delta)
	
	var desired_velocity = move_direction * current_speed

	if is_on_floor():
		velocity.x = lerp(velocity.x, desired_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, desired_velocity.z, acceleration * delta)
	else:
		velocity.x = lerp(velocity.x, desired_velocity.x, air_acceleration * air_influence * delta)
		velocity.z = lerp(velocity.z, desired_velocity.z, air_acceleration * air_influence * delta)
	
		if input_magnitude < 0.05:
			velocity.x = lerp(velocity.x, 0.0, air_deceleration * delta)
			velocity.z = lerp(velocity.z, 0.0, air_deceleration * delta)
	
	move_and_slide()

func _check_fall_and_respawn():
	if global_transform.origin.y < -50.0 or Input.is_action_just_pressed("respawn"):
		_respawn()


func _respawn():
	if team == "hider":
		var level = get_tree().get_root().get_node("Level")
		if level and multiplayer.get_unique_id() != 1:
			level.rpc_id(1, "tag_hider", "server", self.name)

@rpc("any_peer", "reliable")
func change_nick(new_nick: String):
	if nickname:
		nickname.text = new_nick

func get_texture_from_name(skin_name: String) -> CompressedTexture2D:
	match skin_name:
		"blue": return blue_texture
		"green": return green_texture
		"red": return red_texture
		"yellow": return yellow_texture
		"corn": return corn_texture
		"noir": return noir_texture
		"forest": return forest_texture
		"ourple": return ourple_texture
		"indigo": return indigo_texture
		"midnight": return midnight_texture
		"rust": return rust_texture
		"pink": return pink_texture
		"orange": return orange_texture
		_: return blue_texture
		
@rpc("any_peer", "reliable")
func set_player_skin(skin_name: String) -> void:
	var texture = get_texture_from_name(skin_name)
	var bottom: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Bottom")
	var chest: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Chest")
	var face: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Face")
	var limbs_head: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Llimbs and head")
	
	set_mesh_texture(bottom, texture)
	set_mesh_texture(chest, texture)
	set_mesh_texture(face, texture)
	set_mesh_texture(limbs_head, texture)
	
func set_mesh_texture(mesh_instance: MeshInstance3D, texture: CompressedTexture2D) -> void:
	if mesh_instance:
		var material := mesh_instance.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			var new_material := material
			new_material.albedo_texture = texture
			mesh_instance.set_surface_override_material(0, new_material)

func perform_spin(_delta):
	pass

func perform_dive(_delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var flat_forward = Vector3.FORWARD.rotated(Vector3.UP, camera.global_transform.basis.get_euler().y)
	var flat_right = Vector3.RIGHT.rotated(Vector3.UP, camera.global_transform.basis.get_euler().y)
	var dive_direction = (flat_forward * input_dir.y + flat_right * input_dir.x).normalized()
	
	if dive_direction.length() < 0.1:
		dive_direction = -global_transform.basis.z.normalized()
		dive_direction.y = 0  
	
	var horizontal_velocity = dive_direction * dive_horizontal_speed
	velocity.y = dive_upward_boost
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
	if dive_direction.length() > 0.1:
		var target_angle = atan2(-dive_direction.x, -dive_direction.z)
		rotation.y = target_angle

func update_debug_menu():
	$Control/Label.text = " Position : " + str(round_vector3(position)) + "\n Velocity : " + str(round_vector3(velocity)) + "\n State : " + str(State.keys()[current_state])
	$Control/Label.text += "\n Team : " + team

func round_vector3(vec: Vector3) -> Vector3:
	return Vector3(round(vec.x * 10.0) / 10.0, round(vec.y * 10.0) / 10.0, round(vec.z * 10.0) / 10.0)

func get_speed():
	return Vector3(velocity.x, 0, velocity.z)

func is_moving_into_wall() -> bool:
	var wall_normal = get_wall_normal()
	if direction.length() < 0.05:
		return false
	return direction.dot(-wall_normal) > 0.5

func bonk_detection() -> bool:
	return bonk_cast.is_colliding()

func is_touching_wall() -> bool:
	return get_slide_collision_count() > 0 and !is_on_floor()

func perform_wall_jump():
	var wall_normal = get_wall_normal()
	wall_jump_count += 1
	velocity = -wall_normal * wall_jump_force.x
	velocity.y = wall_jump_force.y * clamp((max_wall_jumps - wall_jump_count + free_wall_jumps) / float(max_wall_jumps), 0, 1)
	wall_jump_buffer_timer = 0.0
	wall_jump_lock_timer = wall_jump_input_lock_duration
	current_state = State.WALL_JUMP
	print("Max" + str(max_wall_jumps) + " current" + str(wall_jump_count))

func jump():
	velocity.y = jump_force
	current_state = State.JUMP
	jump_hold_timer = jump_hold_time
	jump_held = true
	jump_buffer_timer = 0.0

func _on_tag_box_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or team == "hider":
		return

	if body.team == "hider":
		var level = get_tree().get_root().get_node("Level")
		if level and multiplayer.get_unique_id() != 1:
			level.rpc_id(1, "tag_hider", self.name, body.name)

func set_team(team_name: String):
	if blind_timer > 0.0:
		set_blind_deaf_dumb(true)
		is_blind_timer_active = true
	else:
		set_blind_deaf_dumb(false)
	team = team_name

func get_team():
	return team

func set_blind_deaf_dumb(truthy : bool):
	blind_deaf_dumb = truthy
	print("blind " + str(blind_deaf_dumb))

@rpc("any_peer", "reliable")
func remote_set_blind_deaf_dumb(state: bool, duration: float = 0.0):
	var sender = multiplayer.get_remote_sender_id()
	if sender != 1:
		print("Unauthorized RPC call from peer %s" % sender)
		return
	set_blind_deaf_dumb(state)
	if state and duration > 0:
		blind_timer = duration
		is_blind_timer_active = true
	else:
		is_blind_timer_active = false
		blind_timer = 0.0
	confirm_blind_state.rpc_id(1, name, state)

@rpc("any_peer", "reliable")
func _set_player_blind(state: bool, duration: float):
	var player = get_tree().get_current_scene().get_node_or_null("Level/Player") # or your path
	if player and player.has_method("remote_set_blind_deaf_dumb"):
		player.remote_set_blind_deaf_dumb(state, duration)

@rpc("any_peer", "reliable")
func confirm_blind_state(player_name: String, state: bool):
	if multiplayer.get_remote_sender_id() != 1:
		print("Unauthorized confirm_blind_state from peer %s" % multiplayer.get_remote_sender_id())
		return
	print("Server received confirmation: %s is now %s" % [player_name, str(state)])
