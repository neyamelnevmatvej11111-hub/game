extends Node

var game_hour: float = 8.0
var game_minute: float = 0.0
# 1 реальная секунда = 1 игровая минута (time_speed=1.0)
# Чтобы 1 сек реал = 1 мин игры: time_speed = 1.0
var time_speed: float = 1.0
var is_sleeping: bool = false
var sleep_timer: float = 0.0
var money: int = 0
var day: int = 1

signal time_changed(hour, minute)
signal money_changed(amount)
signal day_changed(day)
signal sleep_started()
signal sleep_ended()

func _process(delta: float) -> void:
	if is_sleeping:
		sleep_timer += delta
		if sleep_timer >= 3.0:
			_wake_up()
		return
	game_minute += delta * time_speed
	if game_minute >= 60.0:
		game_minute -= 60.0
		game_hour += 1.0
		if game_hour >= 24.0:
			game_hour = 0.0
			day += 1
			emit_signal("day_changed", day)
	emit_signal("time_changed", int(game_hour), int(game_minute))

func get_time_str() -> String:
	return "%02d:%02d" % [int(game_hour), int(game_minute)]

func is_night() -> bool:
	return game_hour >= 22.0 or game_hour < 7.0

func is_store_open() -> bool:
	return game_hour >= 8.0 and game_hour < 22.0

func add_money(amount: int) -> void:
	money += amount
	emit_signal("money_changed", money)

func start_sleep() -> void:
	is_sleeping = true
	sleep_timer = 0.0
	emit_signal("sleep_started")

func _wake_up() -> void:
	is_sleeping = false
	game_hour = 8.0
	game_minute = 0.0
	emit_signal("sleep_ended")
