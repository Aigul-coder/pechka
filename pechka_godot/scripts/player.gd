class_name Player
extends CharacterBody3D

## Печник. Ходит ногами, смотрит мышью, пинает то, во что упирается.
## Камера сюда не прицеплена: игра сама ставит её в положение глаз, чтобы
## одинаково работали и вид от первого лица, и облёт вокруг печки.

const EYE := 1.61
const RADIUS := 0.29
const HEIGHT := 1.78
const WALK := 2.6
const RUN := 4.6
const JUMP := 3.9
const GRAV := 14.0

var yaw := 0.0
var pitch := 0.0
var frozen := false            ## в режиме облёта тело не мешает ни лучам, ни физике

var _warmup := 0               ## до этой отметки времени мышь не слушаем
var _shake := 0.0              ## качает при отравлении угаром
var _burden := 0.0             ## мокрая одежда и холод тянут вниз
var _shiver := 0.0             ## дрожь от мороза
var _step := 0.0               ## накопленный путь — под шаги
var _bob := 0.0

signal stepped(at: Vector3, running: bool)


static func create(at: Vector3) -> Player:
	var p := Player.new()
	p.name = "Player"
	p.collision_layer = Piece.LAYER_PLAYER
	# по мелочи вроде угля и золы не спотыкаемся, иначе ходьба превращается в
	# борьбу с мусором под ногами
	p.collision_mask = Piece.LAYER_WORLD | Piece.LAYER_SOLID
	p.floor_max_angle = deg_to_rad(52.0)
	p.floor_snap_length = 0.35
	p.slide_on_ceiling = false

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	p.add_child(cs)

	p.position = at + Vector3(0, HEIGHT * 0.5 + 0.02, 0)
	return p


func look(rel: Vector2) -> void:
	# при захвате мыши система переносит курсор в середину окна и присылает
	# один огромный сдвиг — от него взгляд улетает в случайную сторону
	if Time.get_ticks_msec() < _warmup or rel.length() > 300.0:
		return
	# и на всякий случай не даём одному событию раскрутить голову целиком
	rel = rel.limit_length(140.0)
	yaw -= rel.x * 0.0028
	pitch = clampf(pitch - rel.y * 0.0028, -1.45, 1.42)


## Мышь только что захватили: следующие события — мусор от переноса курсора.
func reset_look() -> void:
	_warmup = Time.get_ticks_msec() + 400


## Куда смотрит игрок. Отдаём готовое положение глаз вместе с качкой.
func eye() -> Transform3D:
	var sway := Vector3.ZERO
	if _shake > 0.0:
		sway = Vector3(sin(_bob * 1.7) * _shake * 0.06, sin(_bob * 2.3) * _shake * 0.04, 0.0)
	if _shiver > 0.02:
		# дрожь частая и мелкая — не путать с плавной качкой от угара
		var f := Time.get_ticks_msec() * 0.031
		sway += Vector3(sin(f * 3.1) * 0.004, cos(f * 4.7) * 0.003, 0.0) * _shiver
	var basis := Basis.from_euler(Vector3(pitch + sway.y, yaw + sway.x, _shake * sin(_bob * 1.1) * 0.05))
	var head := global_position + Vector3(0, EYE - HEIGHT * 0.5, 0)
	head.y += sin(_bob * 2.0) * 0.012 * clampf(velocity.length() / RUN, 0.0, 1.0)
	return Transform3D(basis, head)


func set_shake(x: float) -> void:
	_shake = clampf(x, 0.0, 1.0)


## Мокрая одежда и мороз: ноги тяжелеют, шаг короче.
func set_burden(x: float) -> void:
	_burden = clampf(x, 0.0, 0.7)


## Озноб: мелкая дрожь в руках, от которой пляшет прицел.
func set_shiver(x: float) -> void:
	_shiver = clampf(x, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if frozen:
		return

	var wish := Vector3.ZERO
	var fwd := -Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	if Input.is_key_pressed(KEY_W): wish += fwd
	if Input.is_key_pressed(KEY_S): wish -= fwd
	if Input.is_key_pressed(KEY_A): wish -= right
	if Input.is_key_pressed(KEY_D): wish += right

	var running := Input.is_key_pressed(KEY_SHIFT) and wish != Vector3.ZERO
	var speed := RUN if running else WALK
	# пока угар не отпустил, ноги заплетаются
	speed *= 1.0 - _shake * 0.45 - _burden
	var goal := wish.normalized() * speed
	var flat := Vector3(velocity.x, 0, velocity.z)
	flat = flat.lerp(goal, 1.0 - exp(-delta * (11.0 if is_on_floor() else 3.0)))
	velocity.x = flat.x
	velocity.z = flat.z

	if is_on_floor():
		velocity.y = JUMP if Input.is_key_pressed(KEY_SPACE) else -0.1
	else:
		velocity.y -= GRAV * delta

	move_and_slide()

	# шаги и пинки: во что упёрлись, то и толкаем
	var moved := Vector3(velocity.x, 0, velocity.z).length()
	_bob += delta * (moved * 2.4 + 0.6)
	if is_on_floor() and moved > 0.4:
		_step += moved * delta
		var stride := 0.85 if running else 1.15
		if _step >= stride:
			_step = 0.0
			stepped.emit(global_position, running)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb == null:
			continue
		var push := -c.get_normal() * minf(moved, 3.0) * 0.5
		rb.apply_impulse(push * sqrt(maxf(rb.mass, 0.05)), c.get_position() - rb.global_position)
