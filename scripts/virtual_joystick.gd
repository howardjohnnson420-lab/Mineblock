extends Control
class_name MineblockVirtualJoystick
signal value_changed(value: Vector2)
var _active_touch: int = -1
var _mouse_active := false
var _value := Vector2.ZERO

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    custom_minimum_size = Vector2(164, 164)
    queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var e := event as InputEventScreenTouch
        if e.pressed and _active_touch == -1:
            _active_touch = e.index; _set_from_position(e.position); accept_event()
        elif not e.pressed and e.index == _active_touch:
            _active_touch = -1; _set_value(Vector2.ZERO); accept_event()
    elif event is InputEventScreenDrag:
        var e := event as InputEventScreenDrag
        if e.index == _active_touch:
            _set_from_position(e.position); accept_event()
    elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
        var e := event as InputEventMouseButton
        if e.pressed:
            _mouse_active = true; _set_from_position(e.position); accept_event()
        elif _mouse_active:
            _mouse_active = false; _set_value(Vector2.ZERO); accept_event()
    elif event is InputEventMouseMotion and _mouse_active:
        _set_from_position((event as InputEventMouseMotion).position); accept_event()

func _set_from_position(p: Vector2) -> void:
    var offset := p - size * 0.5
    var radius := minf(size.x, size.y) * 0.42
    if offset.length() > radius: offset = offset.normalized() * radius
    var normalized := offset / maxf(1.0, radius)
    if normalized.length() < 0.14: normalized = Vector2.ZERO
    _set_value(normalized)

func _set_value(value: Vector2) -> void:
    _value = value
    value_changed.emit(_value)
    queue_redraw()

func _draw() -> void:
    var center := size * 0.5
    var radius := minf(size.x, size.y) * 0.42
    draw_circle(center, radius, Color(0.04, 0.07, 0.11, 0.36))
    draw_arc(center, radius, 0.0, TAU, 48, Color(0.85, 0.92, 1.0, 0.75), 2.0, true)
    draw_circle(center + _value * radius, radius * 0.28, Color(0.83, 0.91, 1.0, 0.68))
