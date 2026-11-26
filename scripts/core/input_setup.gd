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

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	_bind_event("grab", click)


func _bind_key(action: StringName, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	_bind_event(action, ev)


func _bind_event(action: StringName, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, ev)
