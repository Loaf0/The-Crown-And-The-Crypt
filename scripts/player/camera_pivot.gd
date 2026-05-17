extends Node3D

@export var player: Node3D

@onready var camera: Camera3D = $RayCast3D/Camera
@onready var raycast: RayCast3D = $RayCast3D

# Camera positioning
@export var camera_dist := -2.0
@export var camera_height := 3.25
@export var max_camera_dist := -4.5
@export var min_camera_dist := -2.0
@export var speed_zoom_mod := 20.0

# Camera movement
@export var rotation_speed := 3.5 
@export var move_smooth := 4.0
@export var vertical_limit := 70.0
@export var right_stick_influence := 45.0
@export var follow_behind_strength := 30.0

# Wall collision prevention
@export var collision_offset := 0.001
@export var collision_smooth_speed := 100.0
@export var wall_hit_reaction_distance := 1.0
@export var wall_release_distance := 3.0

# Internal variables
var using_mkb := false
var yaw := 0.0
var pitch := 0.0
var actual_camera_dist := camera_dist
@export var min_safe_distance := 0.1
var last_safe_distance := camera_dist  # Track last valid distance

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	yaw = rotation_degrees.y
	pitch = rotation_degrees.x
	
	raycast.target_position = Vector3(0, 0, -max_camera_dist)

func _input(event):
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * Settings.MOUSE_SENSITIVITY
		pitch -= event.relative.y * Settings.MOUSE_SENSITIVITY
		pitch = clamp(pitch, -vertical_limit, vertical_limit)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	
	handle_controller_input(delta)
	update_camera_position(delta)

func handle_controller_input(delta: float) -> void:
	var look_x := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var look_y := Input.get_action_strength("look_down") - Input.get_action_strength("look_up")

	if abs(look_x) > 0.05 or abs(look_y) > 0.05:
		yaw -= look_x * rotation_speed
		pitch -= look_y * rotation_speed
		pitch = clamp(pitch, -vertical_limit, vertical_limit)
	else:
		var move_x := Input.get_action_strength("left_stick_right") - Input.get_action_strength("left_stick_left")
		if abs(move_x) > 0.1:
			yaw -= move_x * right_stick_influence * delta

	rotation_degrees = Vector3(pitch, yaw, 0)

func update_camera_position(delta: float) -> void:
	var player_speed = player.get_speed() if player.has_method("get_speed") else 50.0
	var target_camera_dist = clamp(
		lerp(min_camera_dist, max_camera_dist, player_speed / speed_zoom_mod),
		min_camera_dist,
		max_camera_dist
	)

	# Update raycast with proper length
	raycast.target_position = Vector3(0, 0, -target_camera_dist)
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var local_hit = to_local(hit_point)
		
		# Calculate new distance with bounds checking
		var new_distance = -local_hit.z - collision_offset
		new_distance = clamp(new_distance, min_safe_distance, abs(target_camera_dist))
		
		# Only update if we're getting closer to the wall
		if abs(new_distance) < abs(last_safe_distance):
			actual_camera_dist = new_distance
			last_safe_distance = actual_camera_dist
		
		camera.position.z = -actual_camera_dist
		
		# Height adjustment
		if actual_camera_dist < min_camera_dist * 0.7:
			var height_adjust = lerp(0.0, camera_height * 0.5, 
				inverse_lerp(min_camera_dist * 0.7, min_camera_dist * 0.3, actual_camera_dist))
			camera.position.y = height_adjust
	else:
		# Only update distance if we're moving away from last collision
		if actual_camera_dist < abs(target_camera_dist):
			actual_camera_dist = lerp(actual_camera_dist, target_camera_dist, delta * wall_release_distance)
			last_safe_distance = actual_camera_dist
		
		camera.position.z = -actual_camera_dist
		camera.position.y = lerp(camera.position.y, 0.0, delta * 5.0)
	
	# Smooth camera follow
	var target_pos = player.global_position
	target_pos.y += camera_height
	global_position = global_position.lerp(target_pos, delta * follow_behind_strength)

func set_player(p: Node3D):
	player = p
