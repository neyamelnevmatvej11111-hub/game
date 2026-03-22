extends CharacterBody3D

const PRODUCTS = [
	{"name":"Хлеб",    "price":45},  {"name":"Молоко",   "price":89},
	{"name":"Сыр",     "price":250}, {"name":"Колбаса",  "price":320},
	{"name":"Яблоки",  "price":120}, {"name":"Сок",      "price":95},
	{"name":"Вода",    "price":55},  {"name":"Шоколад",  "price":180},
	{"name":"Печенье", "price":75},  {"name":"Кефир",    "price":70},
]

enum S { ENTER, SHOP, SHELF_WAIT, TO_CASH, AT_CASH, LEAVE }

var state : S = S.ENTER
var speed := 2.5

var entrance_pos    : Vector3
var cashier_pos     : Vector3
var exit_pos        : Vector3
var shelf_positions : Array = []
var target          : Vector3

var cart           : Array = []
var visited        : int   = 0
var target_shelves : int   = 2
var is_processed   : bool  = false
var wait_t         : float = 0.0
var wait_dur       : float = 2.0
var is_init        : bool  = false

func _ready() -> void:
	add_to_group("bot")
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(randf_range(0.3,1.0), randf_range(0.3,1.0), randf_range(0.3,1.0))
	$Body.material_override = mat
	target_shelves = randi_range(1, 3)
	for i in randi_range(1, 4):
		cart.append(PRODUCTS[randi() % PRODUCTS.size()])
	# Позиции устанавливаются СНАРУЖИ до add_child, поэтому сразу готовы
	target  = entrance_pos
	is_init = true

func _physics_process(delta: float) -> void:
	if not is_init or GameManager.is_sleeping:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	match state:
		S.ENTER:
			_walk_to(entrance_pos)
			if global_position.distance_to(entrance_pos) < 1.5:
				state = S.SHOP
				_pick_shelf()

		S.SHOP:
			_walk_to(target)
			if global_position.distance_to(target) < 1.2:
				state    = S.SHELF_WAIT
				wait_dur = randf_range(2.0, 4.0)
				wait_t   = 0.0

		S.SHELF_WAIT:
			velocity.x = 0; velocity.z = 0
			wait_t += delta
			if wait_t >= wait_dur:
				visited += 1
				if visited >= target_shelves:
					state = S.TO_CASH
				else:
					_pick_shelf()
					state = S.SHOP

		S.TO_CASH:
			_walk_to(cashier_pos)
			if global_position.distance_to(cashier_pos) < 2.2:
				state = S.AT_CASH
				velocity.x = 0; velocity.z = 0

		S.AT_CASH:
			velocity.x = 0; velocity.z = 0

		S.LEAVE:
			_walk_to(exit_pos)
			if global_position.distance_to(exit_pos) < 2.5:
				queue_free()

	# Гравитация
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	else:
		velocity.y = -1.0

	move_and_slide()

func _walk_to(dest: Vector3) -> void:
	var diff = dest - global_position
	diff.y = 0.0
	if diff.length() > 0.2:
		var d = diff.normalized()
		velocity.x = d.x * speed
		velocity.z = d.z * speed
		var look = global_position + d
		look_at(Vector3(look.x, global_position.y, look.z), Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _pick_shelf() -> void:
	if shelf_positions.size() > 0:
		target = shelf_positions[randi() % shelf_positions.size()]

func serve() -> void:
	is_processed = true
	state  = S.LEAVE
	target = exit_pos
