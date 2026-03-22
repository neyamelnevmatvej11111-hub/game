extends Node3D

# ── константы позиций ────────────────────────────────────────────────────────
const ENTRANCE  := Vector3(0.0,  0.15, 13.0)   # снаружи у входа
const CASHIER_P := Vector3(-3.5, 0.15,  5.5)   # у кассы внутри
const EXIT_P    := Vector3(0.0,  0.15, 15.0)   # выход на улицу
const BED_POS   := Vector3(7.5,  0.5,  -9.5)   # кровать
const SHELVES   := [
	Vector3(-6.0, 0.15, -5.0),
	Vector3(-3.5, 0.15, -5.0),
	Vector3(-0.5, 0.15, -5.0),
	Vector3( 3.5, 0.15, -5.0),
	Vector3( 6.5, 0.15, -5.0),
]

# ── состояние ────────────────────────────────────────────────────────────────
enum Screen { MAIN_MENU, SETTINGS, GAME }
var cur_screen : Screen = Screen.MAIN_MENU

var player      : CharacterBody3D
var sun         : DirectionalLight3D
var world_env   : WorldEnvironment
var bot_scene   : PackedScene

# HUD
var time_lbl    : Label
var money_lbl   : Label
var day_lbl     : Label
var hint_lbl    : Label
var msg_lbl     : Label
var msg_timer   : float = 0.0
var sleep_rect  : ColorRect
var hud_root    : CanvasLayer

# Касса
var cashier_panel : PanelContainer
var items_lbl     : Label
var total_lbl     : Label
var scan_btn      : Button
var finish_btn    : Button
var cashier_open  : bool  = false
var current_bot           = null
var scanned       : Array = []
var scan_total    : int   = 0

# Спаун
var spawn_timer   : float = 8.0
const SPAWN_INT   := 25.0
const MAX_BOTS    := 5

# Настройки
var show_fps      : bool  = false
var cam_sens      : float = 0.002
var control_mode  : String = "pc"
var fps_lbl       : Label = null

# Мобильное управление
var joystick_root : CanvasLayer
var js_active     : bool  = false
var js_touch_idx  : int   = -1
var js_center     : Vector2 = Vector2.ZERO
var js_knob       : Control
var js_bg         : Control
const JS_RADIUS   := 60.0

var cam_touch_idx : int   = -1
var cam_last_pos  : Vector2 = Vector2.ZERO

# Меню
var menu_layer  : CanvasLayer
var sett_layer  : CanvasLayer

# ── READY ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	bot_scene = load("res://scenes/bot.tscn")
	_build_main_menu()

# ── PROCESS ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if cur_screen != Screen.GAME:
		return

	if msg_timer > 0:
		msg_timer -= delta
		if msg_timer <= 0:
			msg_lbl.visible = false

	if show_fps and fps_lbl:
		fps_lbl.text = "FPS: %d" % Engine.get_frames_per_second()

	_update_hint()
	_update_sun()

	if cashier_open:
		_find_bot()

	if GameManager.is_store_open() and not GameManager.is_sleeping:
		spawn_timer -= delta
		if spawn_timer <= 0:
			spawn_timer = SPAWN_INT
			if get_tree().get_nodes_in_group("bot").size() < MAX_BOTS:
				_spawn_bot()

# ── INPUT ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if cur_screen != Screen.GAME:
		return

	# Мобильный тач-ввод
	if control_mode == "mobile":
		_handle_touch(event)
		return

	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("ui_cancel") and cashier_open:
		_close_cashier()

# ── МОБИЛЬНЫЙ ТАЧ ────────────────────────────────────────────────────────────
func _handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var vp = get_viewport().get_visible_rect().size
		var left_half = event.position.x < vp.x * 0.45

		if event.pressed:
			if left_half:
				# Джойстик
				if js_touch_idx == -1:
					js_touch_idx = event.index
					js_center    = event.position
					js_bg.position   = js_center - Vector2(JS_RADIUS, JS_RADIUS)
					js_knob.position = js_center - Vector2(20, 20)
					js_bg.visible    = true
					js_knob.visible  = true
			else:
				# Камера
				if cam_touch_idx == -1:
					cam_touch_idx = event.index
					cam_last_pos  = event.position
		else:
			if event.index == js_touch_idx:
				js_touch_idx = -1
				js_bg.visible   = false
				js_knob.visible = false
				if player:
					player.joystick_vec = Vector2.ZERO
			if event.index == cam_touch_idx:
				cam_touch_idx = -1

	elif event is InputEventScreenDrag:
		if event.index == js_touch_idx:
			var delta_v = event.position - js_center
			if delta_v.length() > JS_RADIUS:
				delta_v = delta_v.normalized() * JS_RADIUS
			js_knob.position = js_center + delta_v - Vector2(20, 20)
			if player:
				player.joystick_vec = delta_v / JS_RADIUS
		elif event.index == cam_touch_idx:
			var d = event.position - cam_last_pos
			cam_last_pos = event.position
			if player:
				player.rotate_camera(d.x * 0.005, d.y * 0.005)

# ── ВЗАИМОДЕЙСТВИЕ ───────────────────────────────────────────────────────────
func _try_interact() -> void:
	if not player: return
	var pp = player.global_position
	if pp.distance_to(CASHIER_P) < 3.5:
		if cashier_open: _close_cashier()
		else:            _open_cashier()
	elif pp.distance_to(BED_POS) < 3.5:
		if GameManager.is_night():
			GameManager.start_sleep()
		else:
			_show_msg("🌙 Спать можно только ночью (после 22:00)")

func _mobile_interact() -> void:
	_try_interact()

func _mobile_jump() -> void:
	if player and player.is_on_floor():
		player.velocity.y = player.JUMP_SPEED

# ── ПОДСКАЗКИ ────────────────────────────────────────────────────────────────
func _update_hint() -> void:
	if cashier_open or GameManager.is_sleeping or not player:
		hint_lbl.visible = false
		return
	var pp = player.global_position
	if pp.distance_to(CASHIER_P) < 3.5:
		hint_lbl.text    = "[ E ]  Работать за кассой"
		hint_lbl.visible = true
	elif pp.distance_to(BED_POS) < 3.5:
		hint_lbl.text    = "[ E ]  Лечь спать 💤" if GameManager.is_night() else "🛏  Кровать  (после 22:00)"
		hint_lbl.visible = true
	else:
		hint_lbl.visible = false

# ── КАССА ────────────────────────────────────────────────────────────────────
func _open_cashier() -> void:
	cashier_open = true
	cashier_panel.visible = true
	if control_mode == "pc":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	current_bot = null; scanned.clear(); scan_total = 0
	_refresh_cashier()

func _close_cashier() -> void:
	cashier_open = false
	cashier_panel.visible = false
	if control_mode == "pc":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _find_bot() -> void:
	var bots = get_tree().get_nodes_in_group("bot")
	var best = null
	var best_d = 5.0
	for b in bots:
		if b.is_processed: continue
		var d = b.global_position.distance_to(CASHIER_P)
		if d < best_d:
			best_d = d; best = b
	if best != current_bot:
		current_bot = best; scanned.clear(); scan_total = 0
		_refresh_cashier()

func _refresh_cashier() -> void:
	if current_bot == null:
		items_lbl.text   = "⏳ Ожидание покупателя..."
		total_lbl.text   = "Итого: 0 ₽"
		scan_btn.disabled   = true
		finish_btn.disabled = true
	else:
		items_lbl.text = "🛒 Покупатель у кассы  (товаров: %d)\n\n" % current_bot.cart.size()
		for it in scanned:
			items_lbl.text += "✓ %s — %d ₽\n" % [it["name"], it["price"]]
		total_lbl.text      = "Итого: %d ₽" % scan_total
		scan_btn.disabled   = scanned.size() >= current_bot.cart.size()
		finish_btn.disabled = scanned.is_empty()

func _on_scan() -> void:
	if not current_bot: return
	var idx = scanned.size()
	if idx < current_bot.cart.size():
		var it = current_bot.cart[idx]
		scanned.append(it)
		scan_total += it["price"]
		_refresh_cashier()

func _on_finish() -> void:
	if not current_bot or scanned.is_empty(): return
	var sold = scan_total
	GameManager.add_money(scan_total)
	current_bot.serve()
	current_bot = null; scanned.clear(); scan_total = 0
	_refresh_cashier()
	_show_msg("✅ Продажа! +%d ₽" % sold)

# ── СПАУН ────────────────────────────────────────────────────────────────────
func _spawn_bot() -> void:
	var bot = bot_scene.instantiate()
	# Ставим позиции ДО add_child — тогда global_position не нужен
	bot.position        = ENTRANCE + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-0.5, 0.5))
	bot.entrance_pos    = ENTRANCE  + Vector3(randf_range(-0.4, 0.4), 0, 0)
	bot.cashier_pos     = CASHIER_P
	bot.exit_pos        = EXIT_P
	bot.shelf_positions = SHELVES.duplicate()
	add_child(bot)   # добавляем ПОСЛЕ установки всех полей

# ── ДЕНЬ/НОЧЬ ────────────────────────────────────────────────────────────────
func _update_sun() -> void:
	var h = GameManager.game_hour + GameManager.game_minute / 60.0
	var angle: float
	var energy: float
	var sky: Color

	if h >= 6.0 and h < 20.0:
		var t = (h - 6.0) / 14.0
		angle  = lerp(-80.0, 80.0, t)
		energy = sin(t * PI) * 1.3
		var day_sky = Color(0.45, 0.65, 1.0)
		var night_sky = Color(0.03, 0.03, 0.15)
		sky = night_sky.lerp(day_sky, sin(t * PI))
	else:
		angle  = 90.0
		energy = 0.04
		sky    = Color(0.02, 0.02, 0.12)

	sun.rotation_degrees.x = angle
	sun.light_energy = maxf(0.04, energy)
	world_env.environment.background_color = sky

# ── HUD CALLBACKS ─────────────────────────────────────────────────────────────
func _on_time(h: int, m: int) -> void:
	if time_lbl: time_lbl.text = "⏰ %02d:%02d" % [h, m]

func _on_money(v: int) -> void:
	if money_lbl: money_lbl.text = "💰 %d ₽" % v

func _on_day(d: int) -> void:
	if day_lbl: day_lbl.text = "📅 День %d" % d
	_show_msg("🌅 Наступил день %d!" % d)

func _on_sleep_start() -> void:
	if sleep_rect: sleep_rect.visible = true

func _on_sleep_end() -> void:
	if sleep_rect: sleep_rect.visible = false
	_show_msg("☀️ Доброе утро! День %d" % GameManager.day, 4.0)

func _show_msg(text: String, dur: float = 3.0) -> void:
	if msg_lbl:
		msg_lbl.text = text; msg_lbl.visible = true; msg_timer = dur

# ════════════════════════════════════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ════════════════════════════════════════════════════════════════════════════
func _build_main_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.1, 0.18)
	menu_layer.add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -200; vbox.offset_right  = 200
	vbox.offset_top  = -200; vbox.offset_bottom = 200
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	menu_layer.add_child(vbox)

	var title = Label.new()
	title.text = "🛒 Симулятор\nСупермаркета 3D"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var sep = HSeparator.new(); sep.custom_minimum_size.y = 20
	vbox.add_child(sep)

	var btn_play = _menu_btn("▶  Играть")
	btn_play.pressed.connect(_start_game)
	vbox.add_child(btn_play)

	var btn_sett = _menu_btn("⚙  Настройки")
	btn_sett.pressed.connect(_open_settings)
	vbox.add_child(btn_sett)

	var btn_quit = _menu_btn("✖  Выход")
	btn_quit.pressed.connect(func(): get_tree().quit())
	vbox.add_child(btn_quit)

func _menu_btn(text: String) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 54)
	b.add_theme_font_size_override("font_size", 22)
	return b

# ════════════════════════════════════════════════════════════════════════════
# НАСТРОЙКИ
# ════════════════════════════════════════════════════════════════════════════
func _open_settings() -> void:
	if sett_layer: sett_layer.queue_free()
	sett_layer = CanvasLayer.new()
	add_child(sett_layer)
	sett_layer.layer = 10

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.1, 0.2, 0.97)
	sett_layer.add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -260; vbox.offset_right  = 260
	vbox.offset_top  = -320; vbox.offset_bottom = 320
	vbox.add_theme_constant_override("separation", 16)
	sett_layer.add_child(vbox)

	var title = Label.new()
	title.text = "⚙  Настройки"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Разрешение
	var res_lbl = Label.new(); res_lbl.text = "Разрешение экрана:"
	res_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(res_lbl)
	var res_opt = OptionButton.new()
	res_opt.add_theme_font_size_override("font_size", 17)
	res_opt.add_item("1280 × 720")
	res_opt.add_item("1920 × 1080")
	res_opt.add_item("2560 × 1440")
	res_opt.add_item("Полный экран")
	res_opt.item_selected.connect(_on_res_selected)
	vbox.add_child(res_opt)

	# FPS
	var fps_row = HBoxContainer.new()
	var fps_chk = CheckButton.new()
	fps_chk.text = "Показывать FPS"
	fps_chk.button_pressed = show_fps
	fps_chk.add_theme_font_size_override("font_size", 18)
	fps_chk.toggled.connect(func(v): show_fps = v)
	fps_row.add_child(fps_chk)
	vbox.add_child(fps_row)

	# Чувствительность камеры
	var sens_lbl = Label.new(); sens_lbl.text = "Чувствительность камеры:"
	sens_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(sens_lbl)
	var sens_slider = HSlider.new()
	sens_slider.min_value = 0.0005; sens_slider.max_value = 0.008; sens_slider.step = 0.0001
	sens_slider.value = cam_sens
	sens_slider.custom_minimum_size.x = 300
	sens_slider.value_changed.connect(func(v):
		cam_sens = v
		if player: player.mouse_sens = v)
	vbox.add_child(sens_slider)

	# Режим управления
	var ctrl_lbl = Label.new(); ctrl_lbl.text = "Режим управления:"
	ctrl_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(ctrl_lbl)
	var ctrl_opt = OptionButton.new()
	ctrl_opt.add_theme_font_size_override("font_size", 17)
	ctrl_opt.add_item("ПК (клавиатура + мышь)")
	ctrl_opt.add_item("Телефон (сенсорный)")
	ctrl_opt.selected = 0 if control_mode == "pc" else 1
	ctrl_opt.item_selected.connect(_on_ctrl_selected)
	vbox.add_child(ctrl_opt)

	vbox.add_child(HSeparator.new())

	var btn_back = Button.new()
	btn_back.text = "◀  Назад"
	btn_back.custom_minimum_size = Vector2(220, 48)
	btn_back.add_theme_font_size_override("font_size", 20)
	btn_back.pressed.connect(func(): sett_layer.queue_free())
	vbox.add_child(btn_back)

func _on_res_selected(idx: int) -> void:
	match idx:
		0: DisplayServer.window_set_size(Vector2i(1280, 720)); DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1: DisplayServer.window_set_size(Vector2i(1920,1080)); DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		2: DisplayServer.window_set_size(Vector2i(2560,1440)); DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		3: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_ctrl_selected(idx: int) -> void:
	control_mode = "pc" if idx == 0 else "mobile"
	if player: player.control_mode = control_mode

# ════════════════════════════════════════════════════════════════════════════
# СТАРТ ИГРЫ
# ════════════════════════════════════════════════════════════════════════════
func _start_game() -> void:
	cur_screen = Screen.GAME
	if menu_layer: menu_layer.queue_free()
	if sett_layer: sett_layer.queue_free()

	_build_world()
	_build_hud()
	_build_cashier_ui()
	if control_mode == "mobile":
		_build_mobile_ui()

	GameManager.game_hour   = 8.0
	GameManager.game_minute = 0.0
	GameManager.money       = 0
	GameManager.day         = 1
	GameManager.is_sleeping = false

	GameManager.connect("time_changed",  _on_time)
	GameManager.connect("money_changed", _on_money)
	GameManager.connect("day_changed",   _on_day)
	GameManager.connect("sleep_started", _on_sleep_start)
	GameManager.connect("sleep_ended",   _on_sleep_end)

# ════════════════════════════════════════════════════════════════════════════
# МОБИЛЬНОЕ UI
# ════════════════════════════════════════════════════════════════════════════
func _build_mobile_ui() -> void:
	joystick_root = CanvasLayer.new()
	joystick_root.layer = 5
	add_child(joystick_root)

	# Фон джойстика
	js_bg = ColorRect.new()
	js_bg.custom_minimum_size = Vector2(JS_RADIUS*2, JS_RADIUS*2)
	js_bg.size = Vector2(JS_RADIUS*2, JS_RADIUS*2)
	js_bg.color = Color(1,1,1,0.15)
	js_bg.visible = false
	joystick_root.add_child(js_bg)

	# Кнопка джойстика
	js_knob = ColorRect.new()
	js_knob.custom_minimum_size = Vector2(40, 40)
	js_knob.size = Vector2(40, 40)
	js_knob.color = Color(1,1,1,0.45)
	js_knob.visible = false
	joystick_root.add_child(js_knob)

	# Кнопка прыжка
	var jump_btn = Button.new()
	jump_btn.text = "⬆"
	jump_btn.add_theme_font_size_override("font_size", 28)
	jump_btn.custom_minimum_size = Vector2(80, 80)
	jump_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump_btn.offset_left = -180; jump_btn.offset_right  = -100
	jump_btn.offset_top  = -100; jump_btn.offset_bottom = -20
	jump_btn.pressed.connect(_mobile_jump)
	joystick_root.add_child(jump_btn)

	# Кнопка взаимодействия
	var act_btn = Button.new()
	act_btn.text = "E"
	act_btn.add_theme_font_size_override("font_size", 26)
	act_btn.custom_minimum_size = Vector2(80, 80)
	act_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	act_btn.offset_left = -90; act_btn.offset_right  = -10
	act_btn.offset_top  = -100; act_btn.offset_bottom = -20
	act_btn.pressed.connect(_mobile_interact)
	joystick_root.add_child(act_btn)

# ════════════════════════════════════════════════════════════════════════════
# СТРОИТЕЛЬСТВО МИРА
# ════════════════════════════════════════════════════════════════════════════
func _mkbox(pos: Vector3, size: Vector3, col: Color, collis: bool = true) -> CSGBox3D:
	var b = CSGBox3D.new(); b.size = size; b.position = pos
	b.use_collision = collis
	var m = StandardMaterial3D.new(); m.albedo_color = col; b.material = m
	add_child(b); return b

func _mkcyl(pos: Vector3, r: float, h: float, col: Color) -> CSGCylinder3D:
	var c = CSGCylinder3D.new(); c.radius = r; c.height = h; c.position = pos
	c.use_collision = false
	var m = StandardMaterial3D.new(); m.albedo_color = col; c.material = m
	add_child(c); return c

func _mksph(pos: Vector3, r: float, col: Color) -> CSGSphere3D:
	var s = CSGSphere3D.new(); s.radius = r; s.position = pos; s.use_collision = false
	var m = StandardMaterial3D.new(); m.albedo_color = col; s.material = m
	add_child(s); return s

func _mklight(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l = OmniLight3D.new(); l.position = pos; l.light_color = col
	l.light_energy = energy; l.omni_range = rng; add_child(l); return l

func _build_world() -> void:
	# Окружение
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4,0.6,1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.5,0.6,0.8)
	env.ambient_light_energy = 0.5
	env_node.environment = env
	add_child(env_node); world_env = env_node

	sun = DirectionalLight3D.new()
	sun.position = Vector3(0,20,0); sun.shadow_enabled = true
	sun.light_color = Color(1,0.95,0.8); add_child(sun)

	# Земля
	_mkbox(Vector3(0,-0.12,0),   Vector3(80,0.2,80),  Color(0.3,0.55,0.25))
	_mkbox(Vector3(0,0.05,13.5), Vector3(22,0.08,3),  Color(0.72,0.72,0.7))  # тротуар
	_mkbox(Vector3(0,0.02,22),   Vector3(12,0.04,20), Color(0.28,0.28,0.28), false)  # дорога

	# Деревья
	_mkcyl(Vector3(13,1.0,7), 0.25,2.0, Color(0.45,0.28,0.1))
	_mksph(Vector3(13,3.2,7), 1.3,      Color(0.2,0.6,0.15))
	_mkcyl(Vector3(-13,1.0,7), 0.25,2.0, Color(0.45,0.28,0.1))
	_mksph(Vector3(-13,3.2,7), 1.3,      Color(0.2,0.6,0.15))

	# Пол магазина
	_mkbox(Vector3(0,0.0,0), Vector3(20,0.15,24), Color(0.72,0.68,0.62))

	# Стены
	_mkbox(Vector3(0,1.6,-12),  Vector3(20,3.4,0.3), Color(0.92,0.9,0.84))
	_mkbox(Vector3(-7,1.6,12),  Vector3(6,3.4,0.3),  Color(0.92,0.9,0.84))
	_mkbox(Vector3(7,1.6,12),   Vector3(6,3.4,0.3),  Color(0.92,0.9,0.84))
	_mkbox(Vector3(0,3.0,12),   Vector3(8,0.9,0.3),  Color(0.92,0.9,0.84))
	_mkbox(Vector3(-10,1.6,0),  Vector3(0.3,3.4,24), Color(0.92,0.9,0.84))
	_mkbox(Vector3(10,1.6,0),   Vector3(0.3,3.4,24), Color(0.92,0.9,0.84))
	_mkbox(Vector3(0,3.25,0),   Vector3(20,0.2,24),  Color(0.96,0.96,0.96))

	# Вывеска
	var sm = StandardMaterial3D.new(); sm.albedo_color = Color(0.1,0.5,0.9)
	sm.emission_enabled = true; sm.emission = Color(0.1,0.5,0.9); sm.emission_energy_multiplier = 0.5
	var sb = CSGBox3D.new(); sb.size = Vector3(8,0.9,0.15); sb.position = Vector3(0,4.1,11.85)
	sb.use_collision = false; sb.material = sm; add_child(sb)

	# Стеллажи
	var shelf_xs := [-7.0, -4.0, -1.0, 3.0, 6.5]
	var pcols    := [Color(0.9,0.2,0.2), Color(0.2,0.4,0.9),
	                 Color(0.95,0.85,0.1), Color(0.2,0.75,0.3), Color(0.95,0.95,0.95)]
	for i in shelf_xs.size():
		var sx = shelf_xs[i]
		var pc = pcols[i]
		var fx = 0.35 if sx < 0 else -0.35
		_mkbox(Vector3(sx,1.0,-6),       Vector3(0.18,2.0,4.5), Color(0.55,0.35,0.18))
		_mkbox(Vector3(sx+fx,0.5,-6),    Vector3(0.55,0.06,4.5), Color(0.55,0.35,0.18), false)
		_mkbox(Vector3(sx+fx,1.2,-6),    Vector3(0.55,0.06,4.5), Color(0.55,0.35,0.18), false)
		_mkbox(Vector3(sx+fx,1.9,-6),    Vector3(0.55,0.06,4.5), Color(0.55,0.35,0.18), false)
		for j in 3:
			var pz = -7.5 + j * 0.65
			if i == 1 or i == 4:
				_mkcyl(Vector3(sx+fx*0.8, 0.72, pz), 0.12,0.38, pc)
				_mkcyl(Vector3(sx+fx*0.8, 1.42, pz), 0.12,0.38, pc)
			elif i == 3:
				_mksph(Vector3(sx+fx*0.8, 0.65, pz), 0.13, pc)
				_mksph(Vector3(sx+fx*0.8, 1.35, pz), 0.13, pc)
			else:
				_mkbox(Vector3(sx+fx*0.8, 0.65, pz), Vector3(0.28,0.25,0.28), pc, false)
				_mkbox(Vector3(sx+fx*0.8, 1.35, pz), Vector3(0.28,0.25,0.28), pc, false)

	# Касса
	_mkbox(Vector3(-3.5,0.55,7.5), Vector3(4.5,1.1,1.5),  Color(0.25,0.55,0.38))
	_mkbox(Vector3(-3.5,1.08,7.5), Vector3(4.5,0.06,1.5), Color(0.96,0.96,0.96), false)
	var mm = StandardMaterial3D.new(); mm.albedo_color = Color(0.05,0.05,0.12)
	mm.emission_enabled = true; mm.emission = Color(0.1,0.9,0.2); mm.emission_energy_multiplier = 1.2
	var mon = CSGBox3D.new(); mon.size = Vector3(0.75,0.55,0.08)
	mon.position = Vector3(-3.5,1.6,7.8); mon.use_collision = false; mon.material = mm; add_child(mon)
	_mkcyl(Vector3(-3.5,1.18,7.8), 0.08,0.26, Color(0.45,0.28,0.1))

	# Кровать
	_mkbox(Vector3(7.5,0.18,-9.5),  Vector3(1.9,0.22,3.2), Color(0.45,0.28,0.1))
	_mkbox(Vector3(7.5,0.38,-9.5),  Vector3(1.7,0.18,3.0), Color(0.18,0.32,0.72), false)
	_mkbox(Vector3(7.5,0.55,-8.15), Vector3(1.5,0.18,0.5), Color(0.96,0.94,0.9),  false)
	_mkbox(Vector3(7.5,0.5,-10.1),  Vector3(1.65,0.14,2.0),Color(0.7,0.15,0.15),  false)
	_mkcyl(Vector3(8.7,0.6,-8.5), 0.1,1.0, Color(0.45,0.28,0.1))
	_mksph(Vector3(8.7,1.2,-8.5), 0.22,    Color(1.0,0.9,0.5))

	# Освещение
	_mklight(Vector3(0,3.1,0),      Color(1,1,0.92),   1.0, 14.0)
	_mklight(Vector3(0,3.1,-6),     Color(1,1,0.95),   0.9, 12.0)
	_mklight(Vector3(-3.5,3.0,7),   Color(0.85,1,1),   1.1,  8.0)
	_mklight(Vector3(8.7,1.5,-8.5), Color(1,0.8,0.45), 0.7,  4.5)

	# Игрок
	player = CharacterBody3D.new()
	player.position = Vector3(-5, 0.5, 5)
	player.add_to_group("player")
	player.set_script(load("res://scripts/player.gd"))
	player.control_mode = control_mode
	player.mouse_sens   = cam_sens

	var pcap = CapsuleShape3D.new(); pcap.radius = 0.3; pcap.height = 1.6
	var pcol = CollisionShape3D.new(); pcol.shape = pcap; pcol.position = Vector3(0,0.8,0)
	player.add_child(pcol)

	var phead = Node3D.new(); phead.name = "Head"; phead.position = Vector3(0,1.65,0)
	player.add_child(phead)

	var cam = Camera3D.new(); cam.fov = 80.0; phead.add_child(cam)
	add_child(player)

# ════════════════════════════════════════════════════════════════════════════
# HUD
# ════════════════════════════════════════════════════════════════════════════
func _build_hud() -> void:
	hud_root = CanvasLayer.new(); add_child(hud_root)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hbox.offset_top = 8; hbox.offset_bottom = 52
	hbox.add_theme_constant_override("separation", 30)
	hud_root.add_child(hbox)

	day_lbl   = _lbl(hbox, "📅 День 1", 18)
	time_lbl  = _lbl(hbox, "⏰ 08:00",  20)
	money_lbl = _lbl(hbox, "💰 0 ₽",    20)

	if show_fps:
		fps_lbl = _lbl(hbox, "FPS: --", 16)

	var bot_h = _lbl(hud_root, "WASD — движение  |  Shift — бег  |  E — взаимодействие  |  Пробел — прыжок", 14)
	if control_mode == "mobile":
		bot_h.text = "Управление: джойстик слева, камера справа"
	bot_h.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bot_h.offset_top = -34; bot_h.offset_bottom = -6; bot_h.offset_right = 750
	bot_h.modulate = Color(1,1,1,0.7)

	hint_lbl = _lbl(hud_root, "", 20)
	hint_lbl.set_anchors_preset(Control.PRESET_CENTER)
	hint_lbl.offset_left = -200; hint_lbl.offset_right  = 200
	hint_lbl.offset_top  = 55;   hint_lbl.offset_bottom = 90
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.modulate = Color(1.0,1.0,0.3); hint_lbl.visible = false

	msg_lbl = _lbl(hud_root, "", 22)
	msg_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_lbl.offset_left = -230; msg_lbl.offset_right  = 230
	msg_lbl.offset_top  = 60;   msg_lbl.offset_bottom = 100
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.modulate = Color(0.3,1.0,0.4); msg_lbl.visible = false

	sleep_rect = ColorRect.new()
	sleep_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	sleep_rect.color = Color(0,0,0.15,0.97); sleep_rect.visible = false
	hud_root.add_child(sleep_rect)
	var sl = _lbl(sleep_rect, "💤 Вы спите...\nУтро наступит через мгновение", 30)
	sl.set_anchors_preset(Control.PRESET_CENTER)
	sl.offset_left = -300; sl.offset_right  = 300
	sl.offset_top  = -60;  sl.offset_bottom = 60
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

func _lbl(parent: Node, text: String, size: int) -> Label:
	var l = Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l); return l

# ════════════════════════════════════════════════════════════════════════════
# КАССА UI
# ════════════════════════════════════════════════════════════════════════════
func _build_cashier_ui() -> void:
	var canvas = CanvasLayer.new(); canvas.layer = 3; add_child(canvas)

	cashier_panel = PanelContainer.new()
	cashier_panel.set_anchors_preset(Control.PRESET_CENTER)
	cashier_panel.offset_left = -245; cashier_panel.offset_right  = 245
	cashier_panel.offset_top  = -315; cashier_panel.offset_bottom = 315
	cashier_panel.visible = false; canvas.add_child(cashier_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	cashier_panel.add_child(vbox)

	var t = _lbl(vbox, "🏪  К А С С А", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(HSeparator.new())

	items_lbl = _lbl(vbox, "⏳ Ожидание покупателя...", 16)
	items_lbl.custom_minimum_size = Vector2(450, 200)
	items_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

	vbox.add_child(HSeparator.new())

	total_lbl = _lbl(vbox, "Итого: 0 ₽", 22)
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	scan_btn = Button.new(); scan_btn.text = "📦  Пробить следующий товар"
	scan_btn.add_theme_font_size_override("font_size", 18)
	scan_btn.custom_minimum_size = Vector2(0, 44); scan_btn.disabled = true
	scan_btn.pressed.connect(_on_scan); vbox.add_child(scan_btn)

	finish_btn = Button.new(); finish_btn.text = "✅  Завершить и принять оплату"
	finish_btn.add_theme_font_size_override("font_size", 18)
	finish_btn.custom_minimum_size = Vector2(0, 44); finish_btn.disabled = true
	finish_btn.pressed.connect(_on_finish); vbox.add_child(finish_btn)

	var cb = Button.new(); cb.text = "❌  Закрыть  [Esc]"
	cb.add_theme_font_size_override("font_size", 16)
	cb.custom_minimum_size = Vector2(0, 38)
	cb.pressed.connect(_close_cashier); vbox.add_child(cb)
