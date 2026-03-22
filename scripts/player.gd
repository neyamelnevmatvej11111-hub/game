extends CharacterBody3D

const GRAVITY    = 14.0
const JUMP_SPEED = 5.5

var move_speed   : float = 5.0
var sprint_speed : float = 8.5
var mouse_sens   : float = 0.002
var control_mode : String = "pc"   # "pc" или "mobile"

var head: Node3D
var joystick_vec : Vector2 = Vector2.ZERO  # заполняется мобильным UI

func _ready() -> void:
	add_to_group("player")
	head = get_node("Head")
	if control_mode == "pc":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if control_mode != "pc":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sens)
		head.rotate_x(-event.relative.y * mouse_sens)
		head.rotation.x = clamp(head.rotation.x, -PI/2.1, PI/2.1)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func rotate_camera(dx: float, dy: float) -> void:
	rotate_y(-dx * mouse_sens)
	head.rotate_x(-dy * mouse_sens)
	head.rotation.x = clamp(head.rotation.x, -PI/2.1, PI/2.1)

func _physics_process(delta: float) -> void:
	if GameManager.is_sleeping:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED

	var dir: Vector2
	if control_mode == "mobile":
		dir = joystick_vec
	else:
		dir = Input.get_vector("move_left","move_right","move_forward","move_back")

	var move = (transform.basis * Vector3(dir.x, 0, dir.y)).normalized()
	var spd  = sprint_speed if Input.is_action_pressed("sprint") else move_speed

	if move.length() > 0:
		velocity.x = move.x * spd
		velocity.z = move.z * spd
	else:
		velocity.x = move_toward(velocity.x, 0, spd * 2)
		velocity.z = move_toward(velocity.z, 0, spd * 2)

	move_and_slide()
