extends CharacterBody3D
class_name PlayerController
signal break_requested
signal place_requested
signal inventory_requested
signal pause_requested
signal fly_changed(enabled: bool)
signal selected_hotbar_changed(slot: int)
@export var walk_speed: float = 7.0
@export var fly_speed: float = 11.0
@export var jump_velocity: float = 8.0
@export var mouse_sensitivity: float = 0.0022
@export var touch_sensitivity: float = 0.0030
@onready var camera: Camera3D = $Camera3D
var is_flying := false
var mobile_move_vector := Vector2.ZERO
var mobile_vertical := 0.0
var look_enabled := true
var gameplay_paused: bool = false
var camera_pitch := 0.0
var _touch_look_index: int = -1
var _last_jump_ms: int = -500

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    floor_snap_length = 0.2
    safe_margin = 0.001
    camera.current = true

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and look_enabled:
        var e := event as InputEventMouseMotion
        rotate_y(-e.relative.x * mouse_sensitivity)
        camera_pitch = clampf(camera_pitch - e.relative.y * mouse_sensitivity, deg_to_rad(-88), deg_to_rad(88))
        camera.rotation.x = camera_pitch
    elif event is InputEventScreenTouch:
        var e := event as InputEventScreenTouch
        var vs := get_viewport().get_visible_rect().size
        if e.pressed and _touch_look_index == -1 and e.position.x > vs.x * 0.34 and e.position.y < vs.y - 118.0:
            _touch_look_index = e.index
        elif not e.pressed and e.index == _touch_look_index:
            _touch_look_index = -1
    elif event is InputEventScreenDrag:
        var e := event as InputEventScreenDrag
        if e.index == _touch_look_index and look_enabled:
            rotate_y(-e.relative.x * touch_sensitivity)
            camera_pitch = clampf(camera_pitch - e.relative.y * touch_sensitivity, deg_to_rad(-88), deg_to_rad(88))
            camera.rotation.x = camera_pitch
    elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var e := event as InputEventMouseButton
        if e.pressed and e.button_index == MOUSE_BUTTON_LEFT: break_requested.emit()
        elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT: place_requested.emit()
    elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
        var e := event as InputEventKey
        if e.keycode == KEY_ESCAPE:
            pause_requested.emit(); get_viewport().set_input_as_handled()
        elif e.keycode == KEY_E:
            inventory_requested.emit(); get_viewport().set_input_as_handled()
        elif e.keycode == KEY_F:
            toggle_flight()
        elif e.keycode >= KEY_1 and e.keycode <= KEY_9:
            selected_hotbar_changed.emit(e.keycode - KEY_1)

func _physics_process(delta: float) -> void:
    if gameplay_paused:
        velocity = Vector3.ZERO
        return
    var keyboard_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var move_vector := keyboard_vector
    if mobile_move_vector.length() > 0.01: move_vector = mobile_move_vector
    var yaw_basis := Basis(Vector3.UP, rotation.y)
    var planar := (yaw_basis.x * move_vector.x + -yaw_basis.z * -move_vector.y).normalized()
    if is_flying:
        var rise := mobile_vertical
        if Input.is_action_pressed("jump"): rise += 1.0
        if Input.is_key_pressed(KEY_SHIFT): rise -= 1.0
        var flight_forward := -camera.global_transform.basis.z.normalized()
        var flight_right := Basis(Vector3.UP, rotation.y).x
        var flight_direction := flight_right * move_vector.x + flight_forward * -move_vector.y
        if flight_direction.length() > 1.0: flight_direction = flight_direction.normalized()
        velocity = flight_direction * fly_speed + Vector3.UP * clampf(rise, -1.0, 1.0) * fly_speed
        move_and_slide()
    else:
        if not is_on_floor(): velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)) * delta
        if Input.is_action_just_pressed("jump"):
            var now := Time.get_ticks_msec()
            if now - _last_jump_ms < 320:
                toggle_flight()
            elif is_on_floor():
                velocity.y = jump_velocity
            _last_jump_ms = now
        velocity.x = planar.x * walk_speed
        velocity.z = planar.z * walk_speed
        move_and_slide()

func set_mobile_move(value: Vector2) -> void:
    mobile_move_vector = value
func set_mobile_vertical(value: float) -> void:
    mobile_vertical = clampf(value, -1.0, 1.0)
func toggle_flight() -> void:
    is_flying = not is_flying
    if is_flying: velocity = Vector3.ZERO
    fly_changed.emit(is_flying)
func set_gameplay_paused(paused: bool) -> void:
    gameplay_paused = paused

func set_mouse_capture(captured: bool) -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
    look_enabled = captured
func apply_saved_view(yaw: float, pitch: float) -> void:
    rotation.y = yaw
    camera_pitch = clampf(pitch, deg_to_rad(-88), deg_to_rad(88))
    camera.rotation.x = camera_pitch
