extends Node
## Autoload: rejestruje akcje wejścia w kodzie, żeby nie trzeba było
## ich ręcznie klikać w Project Settings > Input Map.


func _ready() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("jump", KEY_SPACE)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("crouch", KEY_CTRL)
	_bind_key("crouch", KEY_C)
	_bind_key("shove", KEY_B)
	_bind_key("interact", KEY_E)
	_bind_key("camera_toggle", KEY_V)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	_bind_event("grab", click)


## F11 przełącza pełny ekran / okno (przydatne przy testach dwóch instancji na jednym PC).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F11:
		var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _bind_key(action: StringName, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	_bind_event(action, ev)


func _bind_event(action: StringName, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, ev)
