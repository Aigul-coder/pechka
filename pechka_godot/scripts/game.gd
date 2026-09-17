extends Node3D

## Печка 3D. Кладём кирпич на фундамент, мажем цементом, ставим трубу,
## сыплем опилки и поджигаем спичкой.

enum Tool { HAND, BRICK, CEMENT, SAWDUST, MATCH, PIPE, PROP, HAY, CHIP, COAL, LEVEL, PICK }

const TOOL_NAMES := ["рука", "кирпич", "цемент", "опилки", "спичка", "труба", "подпорка",
	"сухая трава", "щепки", "уголь", "уровень", "кирочка"]
const TOOL_KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
const FRACS := [1.0, 0.75, 0.5]
const FRAC_NAMES := ["целый", "трёхчетвертка", "половинка"]

const CELL := Vector3(0.262, 0.10, 0.128)
const BASE_Y := PechWorld.BASE_Y
const MAX_PIECES := 760
const REACH := 60.0

var world: PechWorld
var fire: FireSystem
var sfx: Sfx
var hud: Hud
var cam: Camera3D
var kettle: Kettle
var bucket: Bucket
var pot: Cookware
var bread: Cookware
var carried: RigidBody3D = null   ## что игрок держит в руках
var pieces_root: Node3D
var mortar_root: MultiMeshInstance3D
var _seams: Array[Transform3D] = []
var _seams_dirty := false
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var marker: MeshInstance3D
var _ghost_meshes: Dictionary = {}
var _probe_shape: BoxShape3D
var _probe_params: PhysicsShapeQueryParameters3D

var tool: Tool = Tool.BRICK
var frac_idx := 0               # целый / трёхчетвертка / половинка
var rotated := false
var running_bond := true
const TEMP_MAX := 1000.0
const FIRE_MERGE := 0.3     # ближе этого горящие предметы считаются одним костром
const CRACK_TEMP := 700.0   # выше этого кладка начинает рваться
const REICH_SHOW := 5.0     # сколько держится пасхалка, прежде чем всё вернуть
const DUST_FIRE := 0.32     # с такой концентрации пыли хватает искры

const TIME_NAMES := PechWeather.PHASE_NAMES
const DAMPER_NAMES := ["закрыта", "приоткрыта", "открыта"]
const DAMPER_AIR := [0.18, 0.55, 1.0]

var stove_temp := 20.0
var _coals := 0.0
var damper := 2                 # положение заслонки, DAMPER_*
var time_of_day := 2            # индекс в TIME_NAMES, начинаем с полудня
var _draught := 0.0             # тяга трубы, 0..1
var _air := 0.0                 # тяга с учётом заслонки
var _haze := 0.0                # сколько дыма повисло в сарае
var _fire_center := Vector3(0, BASE_Y + 0.2, 0)
var _crack_cd := 1.0
var _coal_dust := 0.0           # концентрация угольной пыли в воздухе
var _dust_at := Vector3.ZERO
var _settle := 1.6              # пауза на укладку стартовых куч
var _blast_cd := 0.0
var room_temp := 17.0           # сколько градусов в сарае
var _retain := 0.0              # насколько кладка держит тепло, 0..1
var _retain_cd := 0.0
var _warm_done := false
var _soot := 0.0                # сажа в трубе, 0..1
var _flue_fire := 0.0           # сколько ещё горит труба, секунды
var _roof_scorch := 0.0
var _co := 0.0                  # угарный газ в сарае, 0..1
var _co_hold := 0.0             # сколько уже дышим полной дозой
var _temp_force := 0.0          # отладка: держать температуру на заданной
var _reichstag := false
var _reich_t := 0.0             # сколько ещё гореть пасхалке
var _pieces: Array[Piece] = []
var _burning: Array[Piece] = []  # что горит сейчас, собирается один раз за кадр
var _n_brick := 0
var _n_cemented := 0
var _n_burning := 0
var _pipe_top: Piece = null      # самое высокое звено трубы
var _stir := 0.0                 # насколько сильно ворошат уголь
var _stir_at := Vector3.ZERO
var _hud_cd := 0.0
var _burn_acc := 0.0
var _bins: Dictionary = {}       # решётка соседей: ключ ячейки -> предметы
const BIN := 0.5                 # размер ячейки, чуть больше радиуса поджига
const BURN_STEP := 0.05          # шаг расчёта распространения огня
var _variant := 0
var _cooldown := 0.0

enum Mode { WALK, ORBIT, FLY }

var mode: Mode = Mode.WALK
var player: Player
var cam_yaw := 0.38
var cam_pitch := 0.24
var cam_dist := 3.5
var cam_target := Vector3(0, 0.62, 0.05)
var _orbit := false
var _pan := false
var _fly_vel := Vector3.ZERO

var _prof := [0, 0, 0, 0, 0, 0, 0, 0]
var _t_in := 0
var _bolt_at := 0               # отладка: на каком кадре ударить молнией
var _no_wind_smoke := false     # отладка: выключить снос дыма ветром
var _soaked := 0.0              # насколько игрок промок, 0..1
var _chill := 0.0               # насколько замёрз, 0..1
var _froze := false
var _ach: Dictionary = {}       # выданные достижения
var _last100: Array[float] = []
var _shot_path := ""
var _shot_frames := 150
var _frame := 0


func _ready() -> void:
	world = PechWorld.new()
	world.name = "World"
	add_child(world)

	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)

	# Все швы — один меш с сотнями копий вместо сотни узлов: раствор рисуется
	# за один вызов и в тени не участвует, всё равно его не видно.
	mortar_root = MultiMeshInstance3D.new()
	mortar_root.name = "Mortar"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	mm.mesh = unit
	mortar_root.multimesh = mm
	mortar_root.material_override = Mats.mortar()
	mortar_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mortar_root)

	fire = FireSystem.new()
	fire.name = "Fire"
	add_child(fire)

	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 62.0
	cam.near = 0.03
	cam.far = 400.0
	add_child(cam)
	cam.current = true

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.build(TOOL_NAMES, TOOL_KEYS)
	hud.set_tool(tool)

	# встаём на землю перед печкой, а не в бетон фундамента
	player = Player.create(Vector3(0.35, 0.3, 3.0))
	add_child(player)
	player.stepped.connect(_on_step)
	world.sky.struck.connect(_on_struck)
	world.sky.thunder.connect(func(power: float, at: Vector3) -> void: sfx.thunder(power, at))
	world.sky.gust.connect(_on_gust)
	world.sky.rainbow_out.connect(func() -> void: _award("beauty", "КРАСОТА", "радуга над сараем"))

	_make_ghost()
	# стартовую расстановку собираем молча, иначе игра начинается с грохота
	sfx.muted = true
	_build_demo_stove()
	sfx.muted = false
	_parse_cmdline()
	_set_mode(mode)
	hud.hide_toast()


func _on_step(at: Vector3, running: bool) -> void:
	sfx.step(at, running)


func _parse_cmdline() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-frames="):
			_shot_frames = int(a.substr(14))
		elif a.begins_with("--cam="):
			var parts := a.substr(6).split(",")
			if parts.size() >= 3:
				cam_yaw = float(parts[0])
				cam_pitch = float(parts[1])
				cam_dist = float(parts[2])
			if parts.size() >= 6:
				cam_target = Vector3(float(parts[3]), float(parts[4]), float(parts[5]))
			mode = Mode.ORBIT   # снимки делаем с облёта, а не из глаз
		elif a == "--lit":
			_ignite_demo()
		elif a == "--boom":
			_ignite_demo()
			_trigger_reichstag()
		elif a == "--nowind":
			_no_wind_smoke = true
		elif a == "--nohud":
			hud.chrome(false)
		elif a.begins_with("--eye="):
			# свободная камера: точка съёмки и углы в градусах, плюс вверх — выше горизонта
			var e := a.substr(6).split(",")
			if e.size() >= 3:
				cam_target = Vector3(float(e[0]), float(e[1]), float(e[2]))
			if e.size() >= 4:
				cam_yaw = deg_to_rad(float(e[3]))
			if e.size() >= 5:
				cam_pitch = deg_to_rad(-float(e[4]))
			mode = Mode.FLY
		elif a.begins_with("--fp="):
			# кадр от первого лица: где стоим и куда смотрим
			var fp := a.substr(5).split(",")
			if fp.size() >= 3:
				player.global_position = Vector3(float(fp[0]), float(fp[1]), float(fp[2]))
			if fp.size() >= 4:
				player.yaw = deg_to_rad(float(fp[3]))
			if fp.size() >= 5:
				player.pitch = deg_to_rad(float(fp[4]))
			mode = Mode.WALK
		elif a == "--bolt":
			_bolt_at = maxi(_shot_frames - 5, 1)
		elif a.begins_with("--sky="):
			world.set_weather(int(a.substr(6)))
		elif a.begins_with("--season="):
			world.set_season(int(a.substr(9)))
		elif a.begins_with("--time="):
			time_of_day = clampi(int(a.substr(7)), 0, TIME_NAMES.size() - 1)
			world.set_time_of_day(time_of_day)
		elif a == "--coal":
			_pour_coal(Vector3(0, BASE_Y + 0.1, 0.05), 8)
		elif a == "--fling":
			# швырнуть уголь прямо в топке — так пыль поднимается по-настоящему
			_pour_coal(Vector3(0, BASE_Y + 0.35, 0.1), 10)
			for p in _pieces:
				if p.kind == Piece.Kind.COAL and p.global_position.length() < 1.2:
					p.apply_central_impulse(Vector3(randf_range(-1, 1), randf_range(0.5, 1.4),
						randf_range(-1, 1)).normalized() * 1.5)
			_settle = 0.0
		elif a == "--dustboom":
			_dust_at = Vector3(0, BASE_Y + 0.25, 0.4)
			_coal_dust = 0.85
			_settle = 0.0
		elif a.begins_with("--quality="):
			world.set_quality(int(a.substr(10)))
		elif a.begins_with("--weather="):
			world.set_weather(int(a.substr(10)))
		elif a.begins_with("--soot="):
			_soot = clampf(float(a.substr(7)), 0.0, 1.0)
		elif a.begins_with("--co="):
			_co = clampf(float(a.substr(5)), 0.0, 1.0)
		elif a.begins_with("--room="):
			room_temp = float(a.substr(7))
		elif a == "--water":
			_pick_up(bucket)
			bucket.fill(1.0)
		elif a == "--splash":
			bucket.fill(1.0)
			_splash_at(Vector3(0, BASE_Y + 0.95, 0.15))
		elif a.begins_with("--temp="):
			_temp_force = float(a.substr(7))
		elif a.begins_with("--haze="):
			_haze = clampf(float(a.substr(7)), 0.0, 1.0)
		elif a.begins_with("--damper="):
			damper = clampi(int(a.substr(9)), 0, DAMPER_NAMES.size() - 1)
		elif a == "--savetest":
			var before := _pieces.size()
			_save_game()
			_load_game()
			print("savetest: было %d, стало %d, швов %d" % [before, _pieces.size(), _seams.size()])
		elif a == "--bonfire":
			_light_bonfire()
	if _shot_path != "":
		hud.hide_intro()


# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if hud.intro_visible():
		if event is InputEventKey and event.pressed:
			hud.hide_intro()
			return
		if event is InputEventMouseButton and event.pressed:
			hud.hide_intro()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_act()
			MOUSE_BUTTON_RIGHT:
				if mode == Mode.WALK:
					if mb.pressed:
						_splash()
				elif mb.pressed and Input.is_key_pressed(KEY_SHIFT):
					_pan = true
				else:
					_orbit = mb.pressed
					if not mb.pressed:
						_pan = false
			MOUSE_BUTTON_MIDDLE:
				_pan = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				cam_dist = clampf(cam_dist * 0.88, 0.7, 40.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_dist = clampf(cam_dist * 1.13, 0.7, 40.0)
				_update_camera()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mode == Mode.WALK:
			player.look(mm.relative)
			_update_camera()
		elif mode == Mode.FLY:
			cam_yaw -= mm.relative.x * 0.0032
			cam_pitch = clampf(cam_pitch - mm.relative.y * 0.0032, -1.45, 1.45)
			_update_camera()
		elif _pan:
			var right := cam.global_transform.basis.x
			var up := cam.global_transform.basis.y
			var k := cam_dist * 0.0016
			cam_target -= right * mm.relative.x * k
			cam_target += up * mm.relative.y * k
			cam_target.y = clampf(cam_target.y, 0.05, 8.0)
			_update_camera()
		elif _orbit:
			cam_yaw -= mm.relative.x * 0.0062
			cam_pitch = clampf(cam_pitch + mm.relative.y * 0.0055, -0.25, 1.44)
			_update_camera()

	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_1: _set_tool(Tool.HAND)
			KEY_2: _set_tool(Tool.BRICK)
			KEY_3: _set_tool(Tool.CEMENT)
			KEY_4: _set_tool(Tool.SAWDUST)
			KEY_5: _set_tool(Tool.MATCH)
			KEY_6: _set_tool(Tool.PIPE)
			KEY_7: _set_tool(Tool.PROP)
			KEY_8: _set_tool(Tool.HAY)
			KEY_9: _set_tool(Tool.CHIP)
			KEY_0: _set_tool(Tool.COAL)
			KEY_MINUS: _set_tool(Tool.LEVEL)
			KEY_EQUAL: _set_tool(Tool.PICK)
			KEY_H:
				frac_idx = (frac_idx + 1) % FRACS.size()
				_ghost_meshes.erase(Tool.BRICK)
				hud.toast("кирпич: %s" % FRAC_NAMES[frac_idx])
			KEY_R:
				rotated = not rotated
			KEY_B:
				running_bond = not running_bond
				hud.toast("перевязка включена" if running_bond else "кладём в стык")
			KEY_N:
				time_of_day = (time_of_day + 1) % TIME_NAMES.size()
				world.set_time_of_day(time_of_day)
				hud.toast("на дворе %s" % TIME_NAMES[time_of_day])
			KEY_O:
				world.set_season((world.sky.season + 1) % 4)
				hud.toast("на дворе %s, %d °C" % [world.sky.season_name(),
					roundi(world.outside_temp())])
			KEY_P:
				world.sky.next_kind()
				world.weather = world.sky.kind
				hud.toast("на дворе %s, %d °C, ветер %s" % [world.sky.kind_name(),
					roundi(world.outside_temp()), world.sky.wind_name()])
			KEY_Z:
				damper = (damper + 1) % DAMPER_NAMES.size()
				sfx.clack(cam_target, 0.4)
				hud.toast("заслонка %s" % DAMPER_NAMES[damper])
			KEY_M:
				sfx.muted = not sfx.muted
				hud.toast("звук выключен" if sfx.muted else "звук включён")
			KEY_X:
				_remove_under_cursor()
			KEY_C:
				_clear_all()
			KEY_F1:
				hud.toggle_hints()
			KEY_F2:
				_set_mode(Mode.ORBIT if mode == Mode.FLY else Mode.FLY)
			KEY_TAB:
				_set_mode(Mode.ORBIT if mode == Mode.WALK else Mode.WALK)
			KEY_F3:
				world.next_quality()
				hud.toast("качество картинки: %s" % world.quality_name())
			KEY_F5:
				_save_game()
			KEY_F9:
				_load_game()
			KEY_F12:
				_save_shot()
			KEY_ESCAPE:
				if mode != Mode.ORBIT:
					_set_mode(Mode.ORBIT)
				else:
					get_tree().quit()


func _set_tool(t: Tool) -> void:
	tool = t
	hud.set_tool(tool)


func _set_mode(m: Mode) -> void:
	mode = m
	# в режимах от первого лица и облёта мышь ведёт взгляд, а не курсор
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if m == Mode.ORBIT else Input.MOUSE_MODE_CAPTURED
	if player != null:
		player.reset_look()
		# тело не должно ни ловить лучи, ни толкать кладку, пока им не ходят
		player.frozen = m != Mode.WALK
		player.velocity = Vector3.ZERO
		player.process_mode = Node.PROCESS_MODE_INHERIT if m == Mode.WALK else Node.PROCESS_MODE_DISABLED
		player.collision_layer = Piece.LAYER_PLAYER if m == Mode.WALK else 0
	match m:
		Mode.WALK: hud.toast("ходим ногами: WASD, пробел — прыжок, Tab — камера вокруг печки")
		Mode.ORBIT: hud.toast("камера вокруг печки: ПКМ вращать, колесо — зум")
		Mode.FLY: hud.toast("свободный полёт: WASD, Q/E вверх-вниз")
	_update_camera()


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	_t_in = Time.get_ticks_usec()
	if mode == Mode.FLY:
		_fly(delta)
	elif mode == Mode.WALK:
		_update_camera()
	var t0 := Time.get_ticks_usec()
	_scan(delta)
	var t1 := Time.get_ticks_usec()
	_update_ghost()
	var t2 := Time.get_ticks_usec()
	_update_draught()
	_burn(delta)
	var t3 := Time.get_ticks_usec()
	_sync_fire(delta)
	var t4 := Time.get_ticks_usec()
	_stress(delta)
	_update_coal_dust(delta)
	_update_kettle(delta)
	_update_carry()
	_update_cooking(delta)
	var t5 := Time.get_ticks_usec()
	_update_retain(delta)
	var t6 := Time.get_ticks_usec()
	_update_room(delta)
	_update_gas(delta)
	_update_reich(delta)
	_update_weather(delta)
	var t7 := Time.get_ticks_usec()
	if _shot_path != "":
		_prof[0] += t1 - t0
		_prof[1] += t2 - t1
		_prof[2] += t3 - t2
		_prof[3] += t4 - t3
		_prof[4] += t5 - t4
		_prof[5] += t6 - t5
		_prof[6] += t7 - t6
		_prof[7] += Time.get_ticks_usec() - _t_in
		# среднее по последней сотне кадров: первые секунды уходят на прогрев
		# шейдеров и разгон освещения, судить по ним о скорости нельзя
		_last100.append(delta)
		if _last100.size() > 100:
			_last100.remove_at(0)
	_hud_cd -= delta
	if _hud_cd <= 0.0:
		# цифры в панели меняются медленно, обновлять их каждый кадр незачем
		_hud_cd = 0.1
		hud.update_stats(stove_temp, _n_brick, _n_cemented, _n_burning, rotated, running_bond)
		hud.update_air(_air, DAMPER_NAMES[damper], _haze, _coal_dust)
		hud.update_room(room_temp, world.outside_temp(), world.sky.kind_name(), _warm_done)
		hud.update_sky(world.sky)
		hud.update_flue(_soot, _co, _flue_fire > 0.0, _retain)
		hud.update_fps(Engine.get_frames_per_second(), _pieces.size())
	if _seams_dirty:
		_flush_seams()
	_frame += 1
	if _bolt_at > 0 and _frame == _bolt_at:
		world.sky.strike_now()
	if _shot_path != "" and _frame >= _shot_frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("screenshot -> ", _shot_path)
		var avg := 0.0
		for d in _last100:
			avg += d
		avg = avg / maxf(float(_last100.size()), 1.0)
		print("bench last100=%.1ffps (%.1fms) fps=%.1f process=%.2fms physics=%.2fms draws=%d prims=%d objects=%d" % [
			1.0 / maxf(avg, 0.0001), avg * 1000.0,
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		print("cam %v look %v player %v yaw=%.2f" % [
			cam.global_position, -cam.global_transform.basis.z, player.global_position, player.yaw])
		var names := ["scan", "ghost", "burn", "fire", "misc", "retain", "gas", "total"]
		var line := PackedStringArray()
		for i in names.size():
			line.append("%s=%.2fms" % [names[i], float(_prof[i]) / float(_frame) / 1000.0])
		print("prof ", " ".join(line))
		get_tree().quit()


func _fly(delta: float) -> void:
	var b := cam.global_transform.basis
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): wish -= b.z
	if Input.is_key_pressed(KEY_S): wish += b.z
	if Input.is_key_pressed(KEY_A): wish -= b.x
	if Input.is_key_pressed(KEY_D): wish += b.x
	if Input.is_key_pressed(KEY_E): wish += Vector3.UP
	if Input.is_key_pressed(KEY_Q): wish -= Vector3.UP
	var speed := 8.0 if Input.is_key_pressed(KEY_SHIFT) else 3.0
	_fly_vel = _fly_vel.lerp(wish.normalized() * speed, 1.0 - exp(-delta * 9.0))
	cam_target += _fly_vel * delta
	_update_camera()


func _update_camera() -> void:
	if mode == Mode.WALK:
		cam.global_transform = player.eye()
		return
	if mode == Mode.FLY:
		var look := Basis.from_euler(Vector3(cam_pitch * -1.0, cam_yaw, 0.0))
		cam.global_transform = Transform3D(look, cam_target)
		return
	var dir := Vector3(
		cos(cam_pitch) * sin(cam_yaw),
		sin(cam_pitch),
		cos(cam_pitch) * cos(cam_yaw)
	)
	cam.position = cam_target + dir * cam_dist
	cam.look_at(cam_target, Vector3.UP)


# ---------------------------------------------------------------- прицел

func _screen_point() -> Vector2:
	if mode == Mode.ORBIT:
		return get_viewport().get_mouse_position()
	return get_viewport().get_visible_rect().size * 0.5


## Ногами дотягиваешься только до того, что рядом; с облёта — куда достанет луч.
func _reach() -> float:
	return 2.9 if mode == Mode.WALK else REACH


func _ray(mask: int) -> Dictionary:
	var mp := _screen_point()
	var from := cam.project_ray_origin(mp)
	var to := from + cam.project_ray_normal(mp) * _reach()
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	q.collide_with_bodies = true
	if player != null:
		q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _place_target() -> Dictionary:
	var hit := _ray(Piece.LAYER_WORLD | Piece.LAYER_SOLID)
	if hit.is_empty():
		return {}
	# с облёта луч уходит далеко за сарай: класть кирпич у горизонта незачем
	if (hit["position"] as Vector3).distance_to(cam.global_position) > 14.0:
		return {}
	var probe: Vector3 = hit["position"] + (hit["normal"] as Vector3) * 0.035
	var pos := Vector3.ZERO
	var rot := Basis.IDENTITY
	match tool:
		Tool.BRICK:
			pos = _snap_brick(probe)
			if rotated:
				rot = Basis.from_euler(Vector3(0, PI * 0.5, 0))
		Tool.PIPE:
			pos = _snap_pipe(probe)
		Tool.PROP:
			pos = _snap_prop(probe)
			if rotated:
				rot = Basis.from_euler(Vector3(0, 0, PI * 0.5))
		_:
			pos = hit["position"]
	return {"pos": pos, "basis": rot, "hit": hit}


func _snap_brick(p: Vector3) -> Vector3:
	var layer: int = maxi(0, floori((p.y - BASE_Y) / CELL.y + 0.12))
	var cx: float = CELL.z if rotated else CELL.x
	var cz: float = CELL.x if rotated else CELL.z
	var off := (cx * 0.5) if (running_bond and layer % 2 == 1) else 0.0
	var col := roundi((p.x - off) / cx)
	var row := roundi(p.z / cz)
	return Vector3(col * cx + off, BASE_Y + layer * CELL.y + Piece.BRICK_SIZE.y * 0.5, row * cz)


func _snap_pipe(p: Vector3) -> Vector3:
	var layer: int = maxi(0, floori((p.y - BASE_Y) / Piece.PIPE_H + 0.2))
	var col := roundi(p.x / CELL.x)
	var row := roundi(p.z / CELL.z)
	return Vector3(col * CELL.x, BASE_Y + layer * (Piece.PIPE_H - 0.015) + Piece.PIPE_H * 0.5, row * CELL.z)


func _snap_prop(p: Vector3) -> Vector3:
	var y := p.y + (Piece.PROP_R if rotated else Piece.PROP_H * 0.5)
	return Vector3(p.x, y, p.z)


func _free_at(pos: Vector3, rot: Basis, size: Vector3) -> bool:
	if _probe_shape == null:
		_probe_shape = BoxShape3D.new()
		_probe_params = PhysicsShapeQueryParameters3D.new()
		_probe_params.shape = _probe_shape
		_probe_params.collision_mask = Piece.LAYER_SOLID
		_probe_params.collide_with_bodies = true
	_probe_shape.size = size * 0.82
	_probe_params.transform = Transform3D(rot, pos)
	return get_world_3d().direct_space_state.intersect_shape(_probe_params, 1).is_empty()


# ---------------------------------------------------------------- призрак

func _make_ghost() -> void:
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.45, 1.0, 0.55, 0.35)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_mat.no_depth_test = false

	ghost = MeshInstance3D.new()
	ghost.name = "Ghost"
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ghost.material_override = ghost_mat
	ghost.visible = false
	add_child(ghost)

	marker = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sm.radial_segments = 16
	sm.rings = 8
	marker.mesh = sm
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	marker.material_override = ghost_mat
	marker.visible = false
	add_child(marker)


func _update_ghost() -> void:
	var t := _place_target()
	if t.is_empty():
		ghost.visible = false
		marker.visible = false
		return

	if tool == Tool.BRICK or tool == Tool.PIPE or tool == Tool.PROP:
		marker.visible = false
		ghost.visible = true
		var size := _tool_size()
		ghost.mesh = _tool_mesh()
		ghost.global_transform = Transform3D(t["basis"], t["pos"])
		var ok := _free_at(t["pos"], t["basis"], size)
		ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.32) if ok else Color(1.0, 0.28, 0.2, 0.35)
	else:
		ghost.visible = false
		marker.visible = tool != Tool.HAND
		marker.position = t["pos"]
		ghost_mat.albedo_color = Color(0.95, 0.75, 0.35, 0.4)


func _tool_size() -> Vector3:
	match tool:
		Tool.BRICK: return Vector3(Piece.BRICK_SIZE.x * _frac(), Piece.BRICK_SIZE.y, Piece.BRICK_SIZE.z)
		Tool.PIPE: return Vector3(Piece.PIPE_R * 2.0, Piece.PIPE_H, Piece.PIPE_R * 2.0)
		_: return Vector3(Piece.PROP_R * 2.0, Piece.PROP_H, Piece.PROP_R * 2.0)


func _frac() -> float:
	return FRACS[frac_idx]


func _tool_mesh() -> Mesh:
	if _ghost_meshes.has(tool):
		return _ghost_meshes[tool]
	var mesh: Mesh
	match tool:
		Tool.BRICK:
			var bm := BoxMesh.new()
			bm.size = _tool_size()
			mesh = bm
		Tool.PIPE:
			var cm := CylinderMesh.new()
			cm.top_radius = Piece.PIPE_R
			cm.bottom_radius = Piece.PIPE_R
			cm.height = Piece.PIPE_H
			cm.radial_segments = 20
			mesh = cm
		_:
			var pm := CylinderMesh.new()
			pm.top_radius = Piece.PROP_R
			pm.bottom_radius = Piece.PROP_R
			pm.height = Piece.PROP_H
			pm.radial_segments = 14
			mesh = pm
	_ghost_meshes[tool] = mesh
	return mesh


# ---------------------------------------------------------------- действия

func _act() -> void:
	var t := _place_target()
	if t.is_empty():
		return
	var hit: Dictionary = t["hit"]
	match tool:
		Tool.HAND:
			_hand(hit, t["pos"])
		Tool.BRICK:
			_spawn(Piece.Kind.BRICK, t["pos"], t["basis"], _tool_size())
		Tool.PIPE:
			_spawn(Piece.Kind.PIPE, t["pos"], t["basis"], Vector3(Piece.PIPE_R * 2.0, Piece.PIPE_H, Piece.PIPE_R * 2.0))
		Tool.PROP:
			_spawn(Piece.Kind.PROP, t["pos"], t["basis"], Vector3(Piece.PROP_R * 2.0, Piece.PROP_H, Piece.PROP_R * 2.0))
		Tool.CEMENT:
			_cement_at(hit)
		Tool.SAWDUST:
			_pour_dust(t["pos"])
		Tool.HAY:
			_pour_hay(t["pos"])
			hud.toast("сухая трава: вспыхнет от искры и повалит дымом")
		Tool.CHIP:
			_pour_chips(t["pos"])
			hud.toast("щепки: разгораются быстро, горят долго")
		Tool.COAL:
			_pour_coal(t["pos"])
			hud.toast("уголь: сам не займётся, подложи щепок — зато даёт 1000°")
		Tool.MATCH:
			_strike_match(t["pos"])
		Tool.LEVEL:
			_check_level(hit)
		Tool.PICK:
			_pick_at(hit)


## Рука делает всё руками: берёт и ставит утварь, черпает воду из бочки,
## плещет её, а во что взяться нельзя — то просто толкает.
func _hand(hit: Dictionary, at: Vector3) -> void:
	if carried != null:
		_put_down(hit, at)
		return

	var body: Object = hit.get("collider")
	var p := body as Piece
	if p != null:
		if p.cemented:
			sfx.clack(p.global_position, 0.3)
			hud.toast("схвачено цементом — руками не сдвинуть")
		else:
			p.unfreeze()
			p.apply_central_impulse(Vector3(0, 1.2, 0) + (cam.global_transform.basis.z * -1.0) * 0.8)
			sfx.clack(p.global_position, 0.5)
		return

	var rb := body as RigidBody3D
	if rb == null:
		return
	if rb == world.barrel:
		_dip_barrel()
		return
	if rb.has_meta("carry"):
		_pick_up(rb)
		return
	# утварь сарая тоже живая: толкаем её тем же движением, только силу считаем
	# от массы, иначе бочка улетит как ведро
	var shove := (Vector3(0, 0.55, 0) + cam.global_transform.basis.z * -1.0).normalized()
	rb.apply_impulse(shove * 2.2 * sqrt(rb.mass), hit["position"] - rb.global_position)
	sfx.clack(hit["position"], 0.45)


func _pick_up(rb: RigidBody3D) -> void:
	carried = rb
	rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rb.freeze = true
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	sfx.clack(rb.global_position, 0.35)
	var what := "ведро" if rb is Bucket else ("чайник" if rb is Kettle else "поклажа")
	if rb is Cookware:
		what = "чугунок" if (rb as Cookware).kind == Cookware.Kind.POT else "хлеб"
	hud.toast("взял %s — ЛКМ поставить, ПКМ выплеснуть" % what if rb is Bucket else "взял %s" % what)


func _put_down(hit: Dictionary, at: Vector3) -> void:
	var rb := carried
	carried = null
	var lift: float = 0.06
	if rb is Bucket:
		lift = Bucket.H * 0.5
	elif rb is Kettle:
		lift = Kettle.H * 0.5
	elif rb is Cookware:
		lift = 0.1
	var drop: Vector3 = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * lift
	if drop.distance_to(at) > 1.5:
		drop = at
	rb.global_transform = Transform3D(Basis.IDENTITY, drop)
	rb.freeze = false
	rb.linear_velocity = Vector3.ZERO
	sfx.clack(drop, 0.4)


## Черпнуть из бочки. Без ведра в руках черпать нечем.
func _dip_barrel() -> void:
	var b := bucket
	if b == null:
		return
	if carried != b:
		hud.toast("возьми ведро — оно у бочки")
		return
	b.fill(1.0)
	sfx.hiss(b.global_position)
	hud.toast("ведро полное — ПКМ выплеснуть")


## Выплеснуть ведро по прицелу. На раскалённой кладке вода срывает кирпичи
## паром, в огне — гасит его, а мимо — просто лужа.
func _splash() -> void:
	if bucket == null or bucket.water < 0.1:
		hud.toast("ведро пустое — набери из бочки")
		return
	var t := _place_target()
	_splash_at(t["pos"] if not t.is_empty() else cam.global_position - cam.global_transform.basis.z * 1.6)


func _splash_at(at: Vector3) -> void:
	var b := bucket
	b.fill(0.0)
	sfx.hiss(at)
	fire.steam_burst(at, 1.0)

	var doused := 0
	for p in _pieces:
		var d := p.global_position.distance_to(at)
		if d > 1.1:
			continue
		if p.burning:
			p.burning = false
			p.heat = 0.0
			doused += 1
		else:
			p.heat = maxf(0.0, p.heat - 0.5)

	# термический удар: раскалённый кирпич от холодной воды лопается
	var cracked := 0
	if stove_temp > 320.0:
		var shock := clampf((stove_temp - 320.0) / 500.0, 0.0, 1.0)
		for p in _pieces:
			if cracked >= int(1 + shock * 5.0):
				break
			if not p.cemented or p.cracked:
				continue
			if p.global_position.distance_to(at) > 0.75:
				continue
			p.cracked = true
			p.unfreeze()
			cracked += 1
		stove_temp = maxf(20.0, stove_temp - 60.0 - shock * 180.0)
		sfx.crash(at, 0.5)

	if _reichstag and doused > 0:
		_douse_inferno()
	if cracked > 0:
		hud.toast("пар в лицо, кирпичей лопнуло: %d" % cracked)
	elif doused > 0:
		hud.toast("залито, погасло: %d" % doused)
	else:
		hud.toast("вода ушла в землю")


## Потушить пожар в сарае: одним ведром не выйдет, но каждое сбивает огонь.
func _douse_inferno() -> void:
	var lit := 0
	for p in _pieces:
		if p.burning:
			lit += 1
	if lit > 3:
		return
	_reichstag = false
	world.restore_roof()
	world.set_calm()
	fire.stop_inferno()
	hud.hide_achievement()
	hud.toast("пожар потушен")


func _spawn(kind: Piece.Kind, pos: Vector3, rot: Basis, size: Vector3) -> void:
	if not _free_at(pos, rot, size):
		hud.toast("тут уже занято")
		return
	_trim_pieces()
	var off := randf_range(-0.009, 0.009)
	var jitter := Basis.from_euler(Vector3(0, randf_range(-0.012, 0.012), 0))
	var p := Piece.create(kind, _variant, _frac() if kind == Piece.Kind.BRICK else 1.0)
	_variant += 1
	pieces_root.add_child(p)
	p.global_transform = Transform3D(rot * jitter, pos + Vector3(off, 0, off * 0.7))
	_pieces.append(p)
	sfx.clack(pos, 0.7 if kind == Piece.Kind.PROP else 1.0)


func _pour_dust(pos: Vector3) -> void:
	_trim_pieces()
	sfx.pour(pos)
	for i in 20:
		var p := Piece.create(Piece.Kind.DUST)
		pieces_root.add_child(p)
		p.global_position = pos + Vector3(randf_range(-0.11, 0.11), 0.12 + randf() * 0.14, randf_range(-0.11, 0.11))
		p.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		p.linear_velocity = Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
		_pieces.append(p)


## Сухая трава: горсть скрученных пучков. Вспыхивает мгновенно и валит дымом.
func _pour_hay(pos: Vector3, count: int = 9, spread := 0.13) -> void:
	_trim_pieces()
	sfx.pour(pos)
	for i in count:
		var p := Piece.create(Piece.Kind.HAY)
		pieces_root.add_child(p)
		p.global_transform = Transform3D(
			Basis.from_euler(Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))),
			pos + Vector3(randf_range(-spread, spread), 0.1 + randf() * 0.16, randf_range(-spread, spread))
		)
		_pieces.append(p)


## Щепки: тонкие сухие пластинки, разгораются быстрее дров, но горят дольше травы.
func _pour_chips(pos: Vector3, count: int = 16, spread := 0.12) -> void:
	_trim_pieces()
	sfx.pour(pos)
	for i in count:
		var p := Piece.create(Piece.Kind.CHIP)
		pieces_root.add_child(p)
		p.global_transform = Transform3D(
			Basis.from_euler(Vector3(randf_range(-0.9, 0.9), randf() * TAU, randf_range(-0.9, 0.9))),
			pos + Vector3(randf_range(-spread, spread), 0.1 + randf() * 0.18, randf_range(-spread, spread))
		)
		p.linear_velocity = Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		_pieces.append(p)


## Уголь. Спичкой его не разожжёшь — нужен слой жара под ним, зато потом
## держит температуру, недостижимую для дерева.
func _pour_coal(pos: Vector3, count: int = 10, spread := 0.11) -> void:
	_trim_pieces()
	sfx.pour(pos)
	for i in count:
		var p := Piece.create(Piece.Kind.COAL)
		pieces_root.add_child(p)
		p.global_transform = Transform3D(
			Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)),
			pos + Vector3(randf_range(-spread, spread), 0.12 + randf() * 0.16, randf_range(-spread, spread))
		)
		_pieces.append(p)


func _strike_match(pos: Vector3) -> void:
	sfx.strike(pos)
	var best: Piece = null
	var best_d := 0.85
	for p in _pieces:
		if not p.is_flammable() or p.burning:
			continue
		var d := p.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		hud.toast("нечего поджигать — насыпь опилок")
		return
	best.burning = true
	best.heat = 1.0
	sfx.flare(best.global_position, best.kind == Piece.Kind.HAY)
	hud.toast("занялось!")


## Уровень. Показывает и наклон самого кирпича, и косину всего ряда: то, что
## на глаз не видно, а печка потом это помнит.
func _check_level(hit: Dictionary) -> void:
	var p := hit.get("collider") as Piece
	if p == null or not p.is_solid():
		hud.toast("уровень ставим на кирпич")
		return
	var tilt := rad_to_deg(p.global_transform.basis.y.angle_to(Vector3.UP))
	var y := p.global_position.y
	var lo := y
	var hi := y
	var mates := 0
	for q in _pieces:
		if q == p or q.kind != Piece.Kind.BRICK:
			continue
		if absf(q.global_position.y - y) > CELL.y * 0.45:
			continue    # другой ряд, с ним сравнивать нечего
		if q.global_position.distance_to(p.global_position) > 1.1:
			continue
		lo = minf(lo, q.global_position.y)
		hi = maxf(hi, q.global_position.y)
		mates += 1
	var step := (hi - lo) * 1000.0
	sfx.clack(p.global_position, 0.2)
	if mates == 0:
		hud.toast("наклон кирпича %.1f° · рядом никого" % tilt)
	elif step < 3.0 and tilt < 1.2:
		hud.toast("ряд ровный: наклон %.1f°, разбег %.0f мм" % [tilt, step])
	else:
		hud.toast("перекос: наклон %.1f°, ряд гуляет на %.0f мм" % [tilt, step])


## Кирочка. В трубе выбивает сажу, целый кирпич колет пополам, а схваченный
## цементом выламывает из кладки.
func _pick_at(hit: Dictionary) -> void:
	var p := hit.get("collider") as Piece
	if p == null:
		hud.toast("кирочкой бьём по кирпичу или трубе")
		return
	if p.kind == Piece.Kind.PIPE:
		if _soot < 0.03:
			hud.toast("труба и так чистая")
			return
		sfx.clack(p.global_position, 0.8)
		fire.set_coal_dust(p.global_position, 0.0)
		_soot = 0.0
		hud.toast("труба прочищена, тяга вернулась")
		return
	if p.kind != Piece.Kind.BRICK:
		hud.toast("кирочкой бьём по кирпичу или трубе")
		return
	if p.cemented:
		p.cracked = true
		p.unfreeze()
		p.apply_central_impulse(Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3)))
		sfx.crash(p.global_position, 0.45)
		hud.toast("выломан из кладки")
		return
	if p.frac <= 0.5:
		hud.toast("колоть дальше некуда")
		return

	# половинки разлетаются в стороны от удара
	var t := p.global_transform
	var half := p.frac * 0.5
	var off := Piece.BRICK_SIZE.x * half * 0.5
	_pieces.erase(p)
	p.queue_free()
	for s in [-1.0, 1.0]:
		var h := Piece.create(Piece.Kind.BRICK, _variant, half)
		_variant += 1
		pieces_root.add_child(h)
		h.global_transform = Transform3D(t.basis, t.origin + t.basis.x * off * s)
		h.apply_central_impulse(t.basis.x * s * 0.5 + Vector3(0, 0.3, 0))
		_pieces.append(h)
	sfx.crash(t.origin, 0.4)
	hud.toast("расколот на две %s" % ("половинки" if half >= 0.5 else "части"))


func _cement_at(hit: Dictionary) -> void:
	var p := hit.get("collider") as Piece
	if p == null or not p.is_solid():
		hud.toast("цемент кладём на кирпич или трубу")
		return
	p.cement()
	sfx.splat(p.global_position)
	var seams := 0
	var weak := 0
	for other in _pieces:
		if other == p or not other.is_solid():
			continue
		var tol := 0.075 if (p.kind == Piece.Kind.PIPE or other.kind == Piece.Kind.PIPE) else 0.035
		var a := _aabb(p).grow(tol)
		var b := _aabb(other)
		if not a.intersects(b):
			continue
		other.cement()
		var q := _seam_bond(p, other)
		p.bond = maxf(p.bond, q)
		other.bond = maxf(other.bond, q)
		if q < 0.6:
			weak += 1
		_spawn_mortar(a.intersection(b.grow(tol * 0.5)))
		seams += 1
	if p.kind == Piece.Kind.PIPE and seams > 0:
		hud.toast("труба приделана цементом")
	elif seams > 0 and weak > 0:
		hud.toast("схватилось швов: %d, сквозных: %d — слабое место" % [seams, weak])
	elif seams > 0:
		hud.toast("схватилось швов: %d" % seams)
	else:
		hud.toast("рядом нечего скреплять")


## Качество шва. Кирпич, положенный со сдвигом, вяжет кладку; уложенный точно
## над нижним даёт сквозной вертикальный шов — по нему она и лопнет.
func _seam_bond(a: Piece, b: Piece) -> float:
	var ab := _aabb(a)
	var bb := _aabb(b)
	if absf(ab.get_center().y - bb.get_center().y) < 0.02:
		return 1.0   # кирпичи одного ряда, сквозного шва тут не будет
	var axis := 0 if ab.size.x >= ab.size.z else 2
	var off: float = absf(ab.get_center()[axis] - bb.get_center()[axis])
	var span: float = maxf(ab.size[axis], 0.01)
	return clampf(0.35 + off / (span * 0.5) * 0.65, 0.35, 1.0)


func _spawn_mortar(box: AABB) -> void:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return
	var size := box.size
	# шов делаем чуть шире по двум длинным осям, чтобы он выглядел размазанным
	var axis := 0
	if size.y < size.x and size.y < size.z:
		axis = 1
	elif size.z < size.x and size.z < size.y:
		axis = 2
	for i in 3:
		if i != axis:
			size[i] = maxf(size[i] * 0.96, 0.02)
	size[axis] = maxf(size[axis], 0.014)
	_add_seam(box.get_center(), Basis.from_euler(Vector3(0, randf_range(-0.02, 0.02), 0)), size)


func _add_seam(at: Vector3, rot: Basis, size: Vector3) -> void:
	_seams.append(Transform3D(rot * Basis.from_scale(size), at))
	_seams_dirty = true


func _flush_seams() -> void:
	_seams_dirty = false
	var mm := mortar_root.multimesh
	mm.instance_count = _seams.size()
	for i in _seams.size():
		mm.set_instance_transform(i, _seams[i])


func _remove_under_cursor() -> void:
	var hit := _ray(Piece.LAYER_SOLID | Piece.LAYER_DEBRIS)
	if hit.is_empty():
		return
	var p := hit.get("collider") as Piece
	if p == null:
		return
	_pieces.erase(p)
	p.queue_free()


func _clear_all() -> void:
	for p in _pieces:
		p.queue_free()
	_pieces.clear()
	_seams.clear()
	_flush_seams()
	fire.set_fires([])
	fire.set_chimney(Vector3.ZERO, false)
	fire.stop_inferno()
	fire.set_room_smoke(Vector3.ZERO, 0.0)
	fire.set_coal_dust(Vector3.ZERO, 0.0)
	_coal_dust = 0.0
	sfx.set_fire(Vector3.ZERO, 0.0)
	sfx.set_flue(Vector3.ZERO, 0.0)
	_haze = 0.0
	world.set_haze(0.0)
	if kettle != null:
		kettle.water = 20.0
		kettle.boiled = false
		kettle.set_steam(0.0)
	sfx.set_kettle(Vector3.ZERO, 0.0, 0.0)
	stove_temp = 20.0
	_coals = 0.0
	_soot = 0.0
	_co = 0.0
	_co_hold = 0.0
	_flue_fire = 0.0
	_retain = 0.0
	fire.set_flue_fire(Vector3.ZERO, false)
	if _reichstag:
		_reichstag = false
		world.restore_roof()
		world.set_calm()
		hud.hide_achievement()
	hud.toast("площадка очищена")


func _trim_pieces() -> void:
	while _pieces.size() > MAX_PIECES:
		var oldest: Piece = null
		for p in _pieces:
			if p.kind == Piece.Kind.ASH or p.kind == Piece.Kind.DUST:
				oldest = p
				break
		if oldest == null:
			oldest = _pieces[0]
		_pieces.erase(oldest)
		oldest.queue_free()


# ---------------------------------------------------------------- горение

func _burn(delta: float) -> void:
	# при закрытой заслонке топливо тлеет часами, при открытой прогорает вмиг
	var blow := 0.45 + 0.85 * _air
	var dead: Array[Piece] = []
	for p in _burning:
		p.fuel -= delta * _burn_rate(p.kind) * blow
		if p.fuel <= 0.0:
			dead.append(p)

	_burn_acc += delta
	if _burn_acc >= BURN_STEP and not _burning.is_empty():
		_spread(_burn_acc)
		_burn_acc = 0.0

	for p in dead:
		_burn_out(p)

	# остывание
	for p in _pieces:
		if p.burning:
			p.refresh_look()
			continue
		if p.heat <= 0.0:
			continue    # холодный предмет перерисовывать нечего
		p.heat = maxf(0.0, p.heat - delta * 0.16)
		p.refresh_look()

	_update_temp(delta)


## Распространение огня. Считаем не каждый кадр и не перебором всего списка:
## соседей берём из решётки, иначе выходит квадрат от числа предметов, а их
## тут три сотни.
func _spread(step: float) -> void:
	_rebuild_bins()
	for p in _burning:
		var at := p.global_position
		for q in _neighbors(at):
			if q == p or q.burning:
				continue
			var d := q.global_position.distance_to(at)
			if d > 0.42:
				continue
			if q.is_flammable():
				q.heat += step * (0.42 - d) * 5.0 * _catch_speed(q.kind)
				if q.heat >= 0.9:
					q.burning = true
					q.heat = 1.0
					sfx.flare(q.global_position, q.kind == Piece.Kind.HAY)
			elif d < 0.26:
				q.heat = minf(q.heat + step * 0.5 * (0.26 - d) * 3.0, 0.7)


func _bin_of(at: Vector3) -> Vector3i:
	return Vector3i(floori(at.x / BIN), floori(at.y / BIN), floori(at.z / BIN))


func _rebuild_bins() -> void:
	_bins.clear()
	for p in _pieces:
		var key := _bin_of(p.global_position)
		if _bins.has(key):
			var cell: Array[Piece] = _bins[key]
			cell.append(p)
		else:
			var cell: Array[Piece] = [p]
			_bins[key] = cell


func _neighbors(at: Vector3) -> Array[Piece]:
	var out: Array[Piece] = []
	var c := _bin_of(at)
	for dx in 3:
		for dy in 3:
			for dz in 3:
				var key := Vector3i(c.x + dx - 1, c.y + dy - 1, c.z + dz - 1)
				if _bins.has(key):
					var cell: Array[Piece] = _bins[key]
					out.append_array(cell)
	return out


## Один проход по предметам вместо шести. Раньше каждая система бегала по всему
## списку сама, и на трёх сотнях предметов это и было главным тормозом.
func _scan(_delta: float) -> void:
	_burning.clear()
	_n_brick = 0
	_n_cemented = 0
	_pipe_top = null
	_stir = 0.0
	var stir_sum := Vector3.ZERO
	for p in _pieces:
		if p.cemented:
			_n_cemented += 1
		if p.burning:
			_burning.append(p)
		match p.kind:
			Piece.Kind.BRICK:
				_n_brick += 1
			Piece.Kind.PIPE:
				if _pipe_top == null or p.global_position.y > _pipe_top.global_position.y:
					_pipe_top = p
			Piece.Kind.COAL:
				if not p.freeze:
					var v := p.linear_velocity.length() + p.angular_velocity.length() * 0.08
					if v > 1.6:
						# просто ссыпать уголь не страшно, страшно швырять
						var s := minf((v - 1.6) * 0.4, 1.0)
						_stir += s
						stir_sum += p.global_position * s
	_n_burning = _burning.size()
	if _stir > 0.0:
		_stir_at = stir_sum / _stir


## Температура зависит не от числа горящих штук, а от того, что и где горит.
## Пучок травы даёт вспышку и дым, кругляк — настоящий жар, а держит его
## кладка: костёр на траве не разогреется, сколько в него ни кидай.
func _update_temp(delta: float) -> void:
	var power := 0.0
	var peak := 20.0
	for p in _burning:
		power += _heat_power(p.kind)
		peak = maxf(peak, _fuel_peak(p.kind))

	var shell := float(_n_cemented)
	var insul := minf(shell / 42.0, 1.0)
	var load := clampf(power / 6.0, 0.0, 1.0)
	# открытый костёр до потолка своего топлива не дотянет: нужна набитая
	# топка, обложенная кладкой
	var target := 20.0 + (peak - 20.0) * (0.22 + 0.3 * load + 0.22 * insul + 0.26 * _air)

	# жарче горящего дерева топку тянут только угли, а они копятся долго и
	# только когда есть чем дышать
	_coals = clampf(_coals + delta * (power * insul * _air * 0.008 - 0.012), 0.0, 1.0)
	target = maxf(target, 20.0 + _coals * (TEMP_MAX - 20.0))
	if _reichstag:
		target = TEMP_MAX   # сарай горит целиком, остывать уже нечему
	if _temp_force > 0.0:
		target = _temp_force

	# тепловая инерция: массивная кладка и разогревается, и стынет медленно
	var mass := 1.0 + minf(shell / 60.0, 1.5)
	var speed := (0.5 if power > 0.0 else 0.16) / mass
	stove_temp = lerpf(stove_temp, maxf(target, 20.0), 1.0 - exp(-delta * speed))

	if not _reichstag and stove_temp >= TEMP_MAX - 4.0:
		_trigger_reichstag()


## Предельная температура горящего топлива. Дерево жарче своего потолка не
## станет — всё, что выше 600°, это уже угли, а не пламя.
func _fuel_peak(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.COAL: return 1000.0   # уже не дерево, а кокс
		Piece.Kind.CHIP: return 450.0
		Piece.Kind.DUST: return 400.0
		Piece.Kind.PROP: return 350.0
		Piece.Kind.HAY: return 300.0
		_: return 20.0


## Высота языков пламени в метрах.
func _flame_height(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.PROP: return 0.40
		Piece.Kind.HAY: return 0.35
		Piece.Kind.DUST: return 0.30
		Piece.Kind.COAL: return 0.16    # уголь почти не даёт языков, он просто раскалён
		Piece.Kind.CHIP: return 0.15
		_: return 0.25


## Кругляк разгорается лениво, щепки и труха полыхают рывком.
func _flame_speed(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.PROP: return 0.7
		Piece.Kind.COAL: return 0.55
		Piece.Kind.CHIP: return 1.4
		Piece.Kind.HAY: return 1.3
		_: return 1.0


## Оттенок дыма: дерево коптит тёмно-серым, опилки и труха — светлым.
func _smoke_tone(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.DUST: return 1.0
		Piece.Kind.HAY: return 0.8
		Piece.Kind.CHIP: return 0.2
		_: return 0.0


## Свод над очагом. Под кирпичной перекрышей пламя обязано остаться в топке,
## наружу оно вырывается только там, где сверху открыто.
func _headroom(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		at + Vector3(0, 0.03, 0), at + Vector3(0, 1.2, 0),
		Piece.LAYER_WORLD | Piece.LAYER_SOLID
	)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 1.2
	return maxf((hit["position"] as Vector3).y - at.y - 0.05, 0.05)


## Пасхалка. Печка раскалилась до предела — и сарай ушёл вместе с ней:
## горит вся площадь, крыша встаёт обратно в своё сломанное положение.
func _trigger_reichstag() -> void:
	_reichstag = true
	sfx.crash(Vector3(0, 2.0, 0))
	sfx.flare(Vector3(0, 0.6, 0), true)
	world.blow_roof()
	world.set_apocalypse()
	fire.start_inferno(PechWorld.SHED_HX, PechWorld.SHED_HZ, 0.06)
	for p in _pieces:
		if p.is_flammable():
			p.burning = true
			p.heat = 1.0
	hud.achievement("РЕЙХСТАГ 45-ГО", "%d °C — сарай взят, крышу сдуло" % roundi(TEMP_MAX))
	_reich_t = REICH_SHOW


## Погода и игрок. Дождь мочит, мороз студит, ветер задувает в трубу,
## а звук снаружи зависит от того, стоит ли игрок под крышей.
func _update_weather(delta: float) -> void:
	var w := world.sky
	if w == null:
		return
	var drop: int = PechWeather.KINDS[w.kind]["drop"]
	var power: float = float(PechWeather.KINDS[w.kind]["power"])
	var inside := _player_inside()
	sfx.set_weather_sound(power, inside, w.wind01(), drop == PechWeather.Drop.HAIL)
	if not _no_wind_smoke:
		fire.set_wind(w.wind_vec())

	# мокнет только тот, кто стоит под дождём
	if drop == PechWeather.Drop.RAIN and not inside:
		_soaked = clampf(_soaked + delta * power * 0.12, 0.0, 1.0)
	else:
		_soaked = maxf(0.0, _soaked - delta * (0.05 + (0.12 if room_temp > 24.0 else 0.0)))

	# мёрзнет тот, кому холодно: на улице по погоде, в сарае по печке
	var felt := room_temp if inside else w.outside_temp() - w.beaufort * 0.7
	if felt < 5.0:
		_chill = clampf(_chill + delta * (5.0 - felt) * 0.012 * (1.0 + _soaked), 0.0, 1.0)
	else:
		_chill = maxf(0.0, _chill - delta * clampf((felt - 5.0) * 0.02, 0.01, 0.2))

	# мокрая одежда и озноб сбивают шаг, и это видно по походке
	player.set_burden(_soaked * 0.25 + _chill * 0.35)
	player.set_shiver(_chill)
	hud.set_chill(_chill, _soaked)

	if _chill > 0.98 and not _froze:
		_froze = true
		hud.toast("руки не слушаются — к печке, греться")
	elif _chill < 0.5:
		_froze = false

	if w.season == PechWeather.Season.WINTER and w.outside_temp() <= -30.0 and not _ach.has("polar"):
		_award("polar", "ПОЛЯРНИК", "пережил мороз в −30")
	if w.outside_temp() <= -38.0 and not _ach.has("hard"):
		_award("hard", "ЗАКАЛЁННЫЙ", "выжил в −40")
	if w.outside_temp() >= 38.0 and not _ach.has("summer"):
		_award("summer", "ЛЕТНИЙ", "пережил +40 в жару")
	if w.beaufort >= 11.5 and not _ach.has("meteo"):
		_award("meteo", "МЕТЕОРОЛОГ", "устоял в ураган 12 баллов")
	if w.seen_count() >= PechWeather.KIND_NAMES.size() and not _ach.has("atmo"):
		_award("atmo", "АТМОСФЕРНЫЙ", "застал всю погоду, какая тут бывает")


## Достижение выдаётся один раз и не перебивает предыдущее без нужды.
func _award(key: String, title: String, text: String) -> void:
	if _ach.has(key):
		return
	_ach[key] = true
	hud.achievement(title, text)
	sfx.flare(player.global_position, false)


func _on_struck(at: Vector3, distance: float, hit_pipe: bool) -> void:
	if not hit_pipe:
		return
	if _rod_built():
		hud.toast("молния ушла в громоотвод")
		_award("rod", "ГРОМООТВОД", "железо на коньке приняло удар на себя")
		return
	hud.toast("молния в трубу!")
	_soot = maxf(0.0, _soot - 0.25)
	# разряд поджигает всё, что рядом с устьем, и раскаляет кладку
	for p in _pieces:
		if p.is_flammable() and p.global_position.distance_to(_flue_mouth()) < 2.2:
			p.burning = true
			p.heat = 1.0
	stove_temp = maxf(stove_temp, 420.0)
	sfx.crash(at, 1.0)


## Громоотвод: железный прут выше трубы. Считаем по трубам с флюгером —
## достаточно положить кусок трубы на конёк, выше устья.
func _rod_built() -> bool:
	for p in _pieces:
		if p.kind == Piece.Kind.PIPE and p.global_position.y > PechWorld.EAVE_Y:
			return true
	return false


func _on_gust(force: float) -> void:
	# шквал раскачивает пламя, задувает дым обратно и хлопает всем, что лежит
	var k := clampf((force - 5.0) / 7.0, 0.0, 1.0)
	if k <= 0.0:
		return
	var dir := world.sky.wind_vec()
	for p in _pieces:
		if p.freeze or p.mass > 4.0:
			continue
		p.apply_impulse(dir * k * p.mass * 0.9 + Vector3.UP * k * p.mass * 0.2)
	if k > 0.5:
		sfx.crash(Vector3(0, 2.4, 0), k * 0.4)


## Пожар догорает сам: через несколько секунд сарай встаёт как стоял, огонь
## гаснет, небо светлеет — играть дальше, а не любоваться пепелищем.
func _update_reich(delta: float) -> void:
	if not _reichstag:
		return
	_reich_t -= delta
	if _reich_t > 0.0:
		return
	_reichstag = false
	_reich_t = 0.0
	fire.stop_inferno()
	world.restore_roof()
	world.set_calm()
	hud.hide_achievement()
	for p in _pieces:
		if p.burning:
			p.burning = false
			p.heat = 0.0
	_coals = 0.0
	_soot = minf(_soot, 0.3)
	_flue_fire = 0.0
	_roof_scorch = 0.0
	fire.set_flue_fire(Vector3.ZERO, false)
	stove_temp = 320.0
	sfx.hiss(Vector3(0, 1.0, 0))
	hud.toast("сарай отстроили заново — печка остыла до %d °C" % roundi(stove_temp))


## Сколько жара даёт каждое топливо. Трава горит ярко, но пусто.
func _heat_power(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.COAL: return 2.4
		Piece.Kind.PROP: return 1.6
		Piece.Kind.CHIP: return 0.55
		Piece.Kind.DUST: return 0.5
		Piece.Kind.HAY: return 0.35
		_: return 0.0


## Как быстро прогорает каждое топливо.
func _burn_rate(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.HAY: return 2.6
		Piece.Kind.DUST: return 1.15
		Piece.Kind.CHIP: return 0.9
		Piece.Kind.COAL: return 0.3
		_: return 0.5


## Насколько охотно топливо занимается от соседнего огня.
func _catch_speed(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.HAY: return 3.2
		Piece.Kind.CHIP: return 1.8
		Piece.Kind.DUST: return 1.4
		Piece.Kind.COAL: return 0.22   # от одной спички не займётся, нужен жар
		_: return 1.0


## Сколько дыма и насколько яркое пламя даёт горящее топливо.
func _smoke_of(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.HAY: return 1.0
		Piece.Kind.COAL: return 0.55
		Piece.Kind.CHIP: return 0.45
		Piece.Kind.PROP: return 0.4
		_: return 0.3


func _flame_of(kind: Piece.Kind) -> float:
	match kind:
		Piece.Kind.HAY: return 0.45
		Piece.Kind.COAL: return 0.8
		Piece.Kind.CHIP: return 0.9
		_: return 1.0


func _burn_out(p: Piece) -> void:
	var pos := p.global_position
	var kind := p.kind
	_pieces.erase(p)
	p.queue_free()
	var n := 8 if kind == Piece.Kind.PROP else 2
	if kind == Piece.Kind.HAY:
		n = 3
	elif kind == Piece.Kind.CHIP:
		n = 1
	elif kind == Piece.Kind.COAL:
		n = 5
	for i in n:
		var a := Piece.create(Piece.Kind.ASH)
		pieces_root.add_child(a)
		a.global_position = pos + Vector3(randf_range(-0.07, 0.07), randf_range(-0.02, 0.06), randf_range(-0.07, 0.07))
		a.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		a.linear_velocity = Vector3(randf_range(-0.15, 0.15), 0.1, randf_range(-0.15, 0.15))
		_pieces.append(a)


## Угольная пыль. Летящий и катящийся уголь трёт сам себя и пылит; пыль
## висит в воздухе, медленно оседает — и от открытого огня рвёт.
func _update_coal_dust(delta: float) -> void:
	if _settle > 0.0:
		# стартовые кучи ещё укладываются, это не игрок их ворошит
		_settle -= delta
		return
	if _stir > 0.0:
		# облако тянется к тому месту, где уголь шевелят сейчас
		_dust_at = _dust_at.lerp(_stir_at, clampf(delta * 3.0, 0.0, 1.0)) if _coal_dust > 0.01 else _stir_at
	# рассыпанную кучу целиком не считаем: иначе один толчок сразу даёт предел
	_coal_dust = clampf(_coal_dust + delta * (minf(_stir, 2.0) * 0.35 - 0.05), 0.0, 1.0)
	fire.set_coal_dust(_dust_at + Vector3(0, 0.35, 0), _coal_dust)

	_blast_cd = maxf(0.0, _blast_cd - delta)
	if _coal_dust < DUST_FIRE or _blast_cd > 0.0:
		return
	# хватит одной искры в облаке — и пошло
	for p in _burning:
		if p.global_position.distance_to(_dust_at) < 1.8:
			_coal_blast(_dust_at + Vector3(0, 0.3, 0), _coal_dust)
			return


## Взрыв облака пыли: вспышка, разлёт всего вокруг и пожар.
func _coal_blast(at: Vector3, power: float) -> void:
	fire.blast(at, 0.7 + power * 1.3)
	sfx.boom(at)
	var radius := 1.4 + power * 1.4
	var near: Array[Piece] = []
	for p in _pieces:
		var d := p.global_position.distance_to(at)
		if d > radius:
			continue
		if p.cemented:
			near.append(p)
			continue
		var dir := ((p.global_position - at).normalized() + Vector3(0, 0.55, 0)).normalized()
		var push := power * 2.5 / (d + 0.5)
		p.apply_central_impulse(dir * push * p.mass)
		p.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * push * 0.04)
		if p.is_flammable() and d < radius * 0.5 and not p.burning:
			p.burning = true
			p.heat = 1.0

	# утварь и чайник сносит ударной волной наравне с остальным
	var loose: Array[RigidBody3D] = world.props.duplicate()
	if kettle:
		loose.append(kettle)
	for rb in loose:
		var d := rb.global_position.distance_to(at)
		if d > radius * 1.6:
			continue
		var dir := ((rb.global_position - at).normalized() + Vector3(0, 0.4, 0)).normalized()
		rb.apply_central_impulse(dir * power * 6.0 / (d + 0.6) * sqrt(rb.mass))

	# в кладке взрыв выбивает дыру вокруг очага, а не разбирает печку целиком
	near.sort_custom(func(a, b): return a.global_position.distance_to(at) < b.global_position.distance_to(at))
	var hole := mini(int(4 + power * 10.0), near.size())
	for i in hole:
		var p: Piece = near[i]
		if p.global_position.distance_to(at) > 0.35 + power * 0.35:
			break
		p.cracked = true
		p.unfreeze()
		p.apply_central_impulse((p.global_position - at).normalized() * power * 1.6 * p.mass)

	# взрывом поднимает и сажу со всего сарая
	_haze = clampf(_haze + 0.2 + power * 0.2, 0.0, 1.0)
	_coal_dust = 0.0
	_blast_cd = 4.0
	_settle = 1.2   # воздух выбило, пыли какое-то время взяться неоткуда
	fire.set_coal_dust(Vector3.ZERO, 0.0)
	hud.toast("угольная пыль рванула!")


## Перегрев рвёт кладку. Первыми уходят кирпичи, которые лежат насухо, потом
## сквозные швы — те, что положены без перевязки, точно один над другим.
func _stress(delta: float) -> void:
	if _reichstag or stove_temp < CRACK_TEMP:
		_crack_cd = 1.0
		return
	var over := clampf((stove_temp - CRACK_TEMP) / (TEMP_MAX - CRACK_TEMP), 0.0, 1.0)
	_crack_cd -= delta * (0.15 + 1.1 * over)
	if _crack_cd > 0.0:
		return
	_crack_cd = 1.0

	var victim: Piece = null
	var worst := 1e9
	for p in _pieces:
		# дрова в топке не кладка, их трогать нечего
		if p.kind != Piece.Kind.BRICK and p.kind != Piece.Kind.PIPE:
			continue
		if p.cracked or p.global_position.y < BASE_Y:
			continue
		var d := p.global_position.distance_to(_fire_center)
		if d > 1.2:
			continue
		# рвётся там, где шов слабее, жар ближе и падать выше
		var score: float = p.bond * 2.0 + d - p.global_position.y * 0.5
		if score < worst:
			worst = score
			victim = p
	if victim == null:
		return

	var dry := not victim.cemented
	victim.cracked = true
	victim.unfreeze()
	victim.apply_central_impulse(Vector3(randf_range(-0.6, 0.6), 0.5, randf_range(-0.6, 0.6)))
	sfx.crash(victim.global_position, 0.5 if dry else 0.7)
	hud.toast("кирпич поехал — он лежал насухо" if dry else "шов лопнул от жара")


## Тепло в сарае. Печка отдаёт его тем щедрее, чем больше прогретой кладки и
## чем круче в ней дымообороты; уходит оно через щели, и на ветру быстрее.
func _update_room(delta: float) -> void:
	var outside: float = world.outside_temp()
	var mass := clampf(float(_n_cemented) / 120.0, 0.0, 1.5)
	var give := maxf(0.0, stove_temp - room_temp) * mass * 0.0016 * (0.45 + 0.55 * _retain)
	var leak := (room_temp - outside) * (0.02 + world.wind * 0.012)
	room_temp = clampf(room_temp + delta * (give - leak), minf(outside, room_temp), 60.0)
	world.set_thermo(room_temp)

	if not _warm_done and room_temp >= 20.0 and outside < 5.0:
		_warm_done = true
		hud.achievement("САРАЙ ПРОТОПЛЕН", "+20 °C при %+d °C на дворе" % roundi(outside))
	elif _warm_done and room_temp < 14.0:
		_warm_done = false


## Дымообороты. Кирпичи, положенные внутри печки, заставляют дым петлять и
## отдавать тепло кладке. Прямая труба над топкой всё тепло выбрасывает.
func _update_retain(delta: float) -> void:
	_retain_cd -= delta
	if _retain_cd > 0.0:
		return
	_retain_cd = 0.7

	# перегородка — это кирпич, у которого кладка со всех четырёх сторон и
	# перекрыша сверху: наружная стенка и плита такими быть не могут,
	# а вот через внутренний простенок дым обязан петлять
	_rebuild_bins()
	var cols: Dictionary = {}
	for p in _pieces:
		if p.kind != Piece.Kind.BRICK or not p.cemented:
			continue
		var key := Vector2i(roundi(p.global_position.x / CELL.x), roundi(p.global_position.z / CELL.z))
		cols[key] = maxf(cols.get(key, -99.0), p.global_position.y)

	var floor_y := BASE_Y + 0.42
	var baffles := 0
	for p in _pieces:
		if p.kind != Piece.Kind.BRICK or not p.cemented or p.global_position.y < floor_y:
			continue
		var key := Vector2i(roundi(p.global_position.x / CELL.x), roundi(p.global_position.z / CELL.z))
		if float(cols[key]) < p.global_position.y + CELL.y * 0.5:
			continue    # сверху открыто, это перекрыша или верхний ряд
		if _walled_in(p):
			baffles += 1
	_retain = clampf(float(baffles) / 12.0, 0.0, 1.0)


func _walled_in(p: Piece) -> bool:
	var at := p.global_position
	var mates := _neighbors(at)
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var found := false
		for q in mates:
			if q == p or q.kind != Piece.Kind.BRICK or not q.cemented:
				continue
			var d := q.global_position - at
			if absf(d.y) > 0.07:
				continue
			var along := d.dot(axis)
			var side := absf(d.x * axis.z + d.z * axis.x)
			if along > 0.05 and along < 0.48 and side < 0.2:
				found = true
				break
		if not found:
			return false
	return true


## Угарный газ. Пока топливо горит, а воздуху идти некуда, в сарае набирается
## угар. Он не виден, но валит с ног — спасает только открытая заслонка.
func _update_gas(delta: float) -> void:
	var power := 0.0
	for p in _burning:
		power += _heat_power(p.kind)
	# считаем не по числу горящих щепок, а по загрузке топки: иначе горсть
	# травы травит быстрее, чем полная топка дров
	var load := clampf(power / 6.0, 0.0, 1.0)
	var choke := clampf(0.85 - _air, 0.0, 1.0)
	_co = clampf(_co + delta * (load * choke * 0.075 - 0.035 - _air * 0.12), 0.0, 1.0)

	# травит только того, кто стоит в сарае
	var inside := mode == Mode.WALK and _player_inside()
	var dose := _co if inside else 0.0
	hud.set_gas(clampf((dose - 0.2) / 0.8, 0.0, 1.0))
	player.set_shake(clampf((dose - 0.35) / 0.65, 0.0, 1.0))
	# насмерть не валит сразу: пара секунд на то, чтобы открыть заслонку
	if dose >= 0.98:
		_co_hold += delta
		if _co_hold > 2.5:
			_faint()
	else:
		_co_hold = maxf(0.0, _co_hold - delta)


func _player_inside() -> bool:
	var at := player.global_position
	return absf(at.x) < PechWorld.SHED_HX and absf(at.z) < PechWorld.SHED_HZ and at.y < 3.2


## Отравился — вынесло на воздух. Игра не кончается, но час работы стоит.
func _faint() -> void:
	player.global_position = Vector3(0.4, Player.HEIGHT * 0.5 + 0.02, PechWorld.SHED_HZ + 2.2)
	player.velocity = Vector3.ZERO
	player.pitch = 0.0
	_co = 0.15
	_co_hold = 0.0
	hud.set_gas(0.0)
	sfx.hiss(player.global_position)
	hud.toast("угорел — тебя вынесло на воздух, открывай заслонку")


## Сажа. Копится от смолистого дыма и душит тягу, а на большом жару вспыхивает
## в трубе факелом — тогда её либо душат заслонкой, либо горит крыша.
func _update_soot(delta: float, smoke: float, tone: float) -> void:
	if _flue_fire > 0.0:
		_flue_fire -= delta
		_soot = maxf(0.0, _soot - delta * 0.12)
		var mouth := _flue_mouth()
		fire.set_flue_fire(mouth, true)
		sfx.set_flue(mouth, 1.0)
		if _air > 0.5 and _flue_fire > 3.0 and not _reichstag:
			# распахнутая заслонка кормит факел, и он достаёт до крыши
			_roof_scorch += delta
			if _roof_scorch > 5.0:
				_trigger_reichstag()
		if _soot <= 0.02 or _flue_fire <= 0.0:
			_flue_fire = 0.0
			_roof_scorch = 0.0
			fire.set_flue_fire(Vector3.ZERO, false)
			hud.toast("труба прогорела дочиста")
		return

	_soot = clampf(_soot + delta * smoke * (0.6 + tone * 0.5) * 0.0055 * (1.3 - _air * 0.6), 0.0, 1.0)
	if _soot > 0.75 and stove_temp > 420.0 and _pipe_top != null:
		_flue_fire = 14.0
		_roof_scorch = 0.0
		sfx.flare(_flue_mouth(), true)
		hud.toast("сажа в трубе вспыхнула! души заслонкой")


func _flue_mouth() -> Vector3:
	if _pipe_top == null:
		return Vector3(0, 2.0, 0)
	return _pipe_top.global_position + Vector3(0, Piece.PIPE_H * 0.5 + 0.1, 0)


## Поклажа висит перед глазами, чуть ниже прицела, чтобы не закрывать вид.
func _update_carry() -> void:
	if carried == null:
		return
	var b := cam.global_transform.basis
	var hold := cam.global_position - b.z * 0.62 - b.y * 0.26 + b.x * 0.16
	carried.global_transform = Transform3D(Basis.IDENTITY, hold)


## Чугунок доходит от плиты под собой, хлеб — от жара остывающей топки.
## Открытый огонь под хлебом его только сожжёт.
func _update_cooking(delta: float) -> void:
	for c: Cookware in [pot, bread]:
		if c == null or c == carried:
			continue
		var heat := _heat_at(c.global_position, c.kind == Cookware.Kind.BREAD)
		var event: String = c.simmer(delta, heat)
		if event == "":
			continue
		if c.kind == Cookware.Kind.POT:
			hud.toast("картошка готова" if event == "готово" else "картошка сгорела")
		else:
			hud.toast("хлеб испёкся" if event == "готово" else "хлеб сгорел")


## Сколько жара достаётся посуде в этом месте. На плите — температура кладки
## под ней, в топке — она же, но открытое пламя рядом жарит куда сильнее.
func _heat_at(at: Vector3, inside: bool) -> float:
	var q := PhysicsRayQueryParameters3D.create(at, at - Vector3(0, 0.22, 0), Piece.LAYER_SOLID)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var on_stove := not hit.is_empty() and (hit.get("collider") as Piece) != null
	var heat := stove_temp if on_stove else 20.0
	if inside:
		for p in _burning:
			if p.global_position.distance_to(at) < 0.5:
				heat = maxf(heat, stove_temp) + 260.0   # рядом с огнём хлебу конец
				break
	return heat


## Чайник греется не от воздуха, а от плиты под собой: проверяем, стоит ли он
## на кладке, и тянем воду к температуре печки. Сняли с печки — остывает.
func _update_kettle(delta: float) -> void:
	if kettle == null:
		return
	var on_stove := false
	var q := PhysicsRayQueryParameters3D.create(
		kettle.global_position, kettle.global_position - Vector3(0, Kettle.H * 0.5 + 0.06, 0),
		Piece.LAYER_SOLID
	)
	q.exclude = [kettle.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and (hit.get("collider") as Piece) != null:
		on_stove = true

	if on_stove and stove_temp > kettle.water:
		kettle.water = minf(kettle.water + delta * (stove_temp - kettle.water) * 0.02, 100.0)
	else:
		kettle.water = maxf(kettle.water - delta * (kettle.water - 20.0) * 0.012, 20.0)

	var steam := clampf((kettle.water - 55.0) / 45.0, 0.0, 1.0)
	var whistle := clampf((kettle.water - 97.0) / 3.0, 0.0, 1.0)
	kettle.set_steam(steam)
	sfx.set_kettle(kettle.spout_tip(), steam, whistle)
	if whistle > 0.5 and not kettle.boiled:
		kettle.boiled = true
		hud.toast("чайник закипел")
	elif kettle.water < 90.0:
		kettle.boiled = false


## Тяга — высота трубы над топкой: короткий огрызок почти не тянет, столб под
## крышу гудит. Заслонка эту тягу душит.
func _update_draught() -> void:
	# без трубы воздух идёт через открытое устье — кое-как, но горит
	if _pipe_top == null:
		_draught = 0.22
	else:
		var top := _pipe_top.global_position.y + Piece.PIPE_H * 0.5
		_draught = clampf((top - BASE_Y - 0.5) / 1.3, 0.12, 1.0)
	# ветер над трубой подсасывает дым, а сажа внутри душит тягу
	_draught = clampf(_draught * (0.82 + world.wind * 0.36) * (1.0 - _soot * 0.65), 0.05, 1.2)
	_air = _draught * DAMPER_AIR[damper]


func _sync_fire(delta: float) -> void:
	# Охапка в топке — это один костёр, а не десять. Накладывать десяток
	# аддитивных эмиттеров друг на друга бессмысленно: ядро выгорает в белое
	# пятно, и никакого градиента в пламени уже не видно.
	var clusters: Array = []
	var smoke_total := 0.0
	var tone_sum := 0.0
	var lit := 0
	for p in _burning:
		var sm := _smoke_of(p.kind)
		var tone := _smoke_tone(p.kind)
		smoke_total += sm
		tone_sum += tone
		lit += 1
		var at := p.global_position + Vector3(0, p.half_height() * 0.5, 0)
		var host: Dictionary = {}
		for c in clusters:
			if (c["pos"] as Vector3).distance_to(at) < FIRE_MERGE:
				host = c
				break
		if host.is_empty():
			# в общем пожаре свои огоньки у каждой доски уже не видны, а кадр
			# они съедают, поэтому оставляем горстку и полагаемся на зарево
			var cap: int = 3 if _reichstag else FireSystem.MAX_FIRES
			if clusters.size() >= cap:
				continue
			clusters.append({
				"pos": at, "sum": at, "n": 1, "width": 0.0,
				"height": _flame_height(p.kind), "speed": _flame_speed(p.kind),
				"flame": _flame_of(p.kind), "smoke": sm, "tone_sum": tone,
			})
			continue
		host["n"] += 1
		host["sum"] = host["sum"] + at
		host["pos"] = host["sum"] / float(host["n"])
		host["width"] = maxf(host["width"], Vector2(at.x, at.z).distance_to(
			Vector2((host["pos"] as Vector3).x, (host["pos"] as Vector3).z)))
		host["smoke"] = minf(host["smoke"] + sm * 0.5, 1.0)
		host["tone_sum"] += tone
		host["flame"] = maxf(host["flame"], _flame_of(p.kind))
		if _flame_height(p.kind) > host["height"]:
			# тон пламени задаёт самое рослое полено в куче
			host["height"] = _flame_height(p.kind)
			host["speed"] = _flame_speed(p.kind)

	var space := get_world_3d().direct_space_state
	var loudest := 0.0
	var loud_at := cam_target
	for c in clusters:
		c["height"] = minf(c["height"], _headroom(space, c["pos"]))
		c["tone"] = c["tone_sum"] / float(c["n"])
		var loud: float = clampf(0.3 + 0.16 * float(c["n"]), 0.0, 1.0)
		if loud > loudest:
			loudest = loud
			loud_at = c["pos"]
	# голос у огня один, но громкость — от всей топки, а не от одного очага
	sfx.set_fire(loud_at, minf(loudest + 0.05 * float(maxi(clusters.size() - 1, 0)), 1.0))
	if not clusters.is_empty():
		_fire_center = loud_at
	fire.set_fires(clusters)

	# дым делится: сколько тянет труба — столько уходит вверх, остальное в сарай
	var top := _pipe_top
	var vented: float = clampf(_air, 0.0, 1.0) if top != null else 0.0
	if top != null and lit > 0:
		var mouth := top.global_position + Vector3(0, Piece.PIPE_H * 0.5 + 0.05, 0)
		fire.set_chimney(mouth, true,
			clampf(0.18 + smoke_total * vented * 0.32, 0.12, 1.0), tone_sum / float(lit))
		sfx.set_flue(mouth, clampf(0.15 + smoke_total * vented * 0.3, 0.0, 1.0))
	else:
		fire.set_chimney(Vector3.ZERO, false)
		sfx.set_flue(Vector3.ZERO, 0.0)

	_update_soot(delta, smoke_total, tone_sum / float(maxi(lit, 1)))

	var spill := smoke_total * (1.0 - vented)
	fire.set_room_smoke(loud_at + Vector3(0, 0.3, 0), clampf(spill * 0.4, 0.0, 1.0) if lit > 0 else 0.0)
	# мгла копится, пока дыму некуда деваться, и медленно вытягивает через щели
	_haze = clampf(_haze + delta * (spill * 0.17 - 0.05), 0.0, 1.0)
	if not _reichstag:
		world.set_haze(_haze)


# ---------------------------------------------------------------- статистика

func _aabb(p: Piece) -> AABB:
	var local: AABB = p.mi.mesh.get_aabb()
	return p.global_transform * local


func _count(kind: Piece.Kind) -> int:
	var n := 0
	for p in _pieces:
		if p.kind == kind:
			n += 1
	return n


func _count_cemented() -> int:
	var n := 0
	for p in _pieces:
		if p.cemented:
			n += 1
	return n


func _count_burning() -> int:
	var n := 0
	for p in _pieces:
		if p.burning:
			n += 1
	return n


## Сохранение. Пишем только то, что игрок сложил руками: кладку, топливо,
## погоду и состояние топки. Утварь и сарай каждый раз строятся заново.
const SAVE_PATH := "user://pechka_save.json"


func _save_game() -> void:
	var rows: Array = []
	for p in _pieces:
		if p.kind == Piece.Kind.ASH:
			continue    # золу не храним, её после загрузки нанесёт заново
		var t := p.global_transform
		rows.append({
			"k": int(p.kind), "f": snappedf(p.frac, 0.01),
			"p": [snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001)],
			"r": [snappedf(t.basis.get_euler().x, 0.001), snappedf(t.basis.get_euler().y, 0.001),
				snappedf(t.basis.get_euler().z, 0.001)],
			"c": p.cemented, "b": snappedf(p.bond, 0.01),
			"u": snappedf(p.fuel, 0.01), "g": p.burning,
		})
	var data := {
		"ver": 1, "pieces": rows,
		"temp": stove_temp, "room": room_temp, "soot": _soot, "co": _co,
		"damper": damper, "time": time_of_day, "weather": world.weather,
		"player": [player.global_position.x, player.global_position.y, player.global_position.z],
		"yaw": player.yaw, "pitch": player.pitch,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		hud.toast("не смог записать сохранение")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	hud.toast("сохранено: кладки %d" % rows.size())


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		hud.toast("сохранения нет — сложи печку и нажми F5")
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		hud.toast("сохранение испорчено")
		return
	var data: Dictionary = parsed

	sfx.muted = true
	_clear_all()
	for row in data.get("pieces", []):
		var r: Dictionary = row
		var pos: Array = r["p"]
		var rot: Array = r["r"]
		var p := Piece.create(r["k"] as Piece.Kind, _variant, float(r.get("f", 1.0)))
		_variant += 1
		pieces_root.add_child(p)
		p.global_transform = Transform3D(
			Basis.from_euler(Vector3(rot[0], rot[1], rot[2])),
			Vector3(pos[0], pos[1], pos[2]))
		if bool(r.get("c", false)):
			p.cement()
			p.bond = float(r.get("b", 1.0))
		p.fuel = float(r.get("u", p.fuel))
		p.burning = bool(r.get("g", false))
		if p.burning:
			p.heat = 1.0
		_pieces.append(p)
		if p.cemented and p.kind == Piece.Kind.BRICK:
			_mortar_bed(p.global_position, p.global_transform.basis, p.frac)

	stove_temp = float(data.get("temp", 20.0))
	room_temp = float(data.get("room", 17.0))
	_soot = float(data.get("soot", 0.0))
	_co = float(data.get("co", 0.0))
	damper = int(data.get("damper", 2))
	time_of_day = int(data.get("time", 0))
	world.set_time_of_day(time_of_day)
	world.set_weather(int(data.get("weather", 0)))
	var pp: Array = data.get("player", [0.1, 0.9, 2.45])
	player.global_position = Vector3(pp[0], pp[1], pp[2])
	player.yaw = float(data.get("yaw", 0.0))
	player.pitch = float(data.get("pitch", 0.0))
	_settle = 1.2
	sfx.muted = false
	hud.toast("загружено: кладки %d" % _pieces.size())


func _save_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://pechka_%d.png" % Time.get_unix_time_from_system()
	img.save_png(path)
	hud.toast("снимок: %s" % ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- стартовая печка

## Ставим уже сложенную топку. Кладка — настоящая перевязка: чётные слои
## длинными стенками держат углы, нечётные — короткими, поэтому вертикальные
## швы сдвинуты на полкирпича, как в живой кладке.
func _build_demo_stove() -> void:
	var bt := Piece.BRICK_SIZE.z      # толщина стенки
	var pitch := CELL.x               # шаг с учётом шва
	var n_long := 5
	var n_short := 4
	var layers := 9
	var half_l := n_long * pitch * 0.5
	var half_s := n_short * pitch * 0.5
	var turn := Basis.from_euler(Vector3(0, PI * 0.5, 0))

	for layer in layers:
		var y := BASE_Y + layer * CELL.y + Piece.BRICK_SIZE.y * 0.5
		var long_owns_corner := layer % 2 == 0

		# длинные стенки вдоль X, спереди и сзади
		var lc := n_long if long_owns_corner else n_long - 1
		for sz in [-1.0, 1.0]:
			var z: float = sz * (half_s - bt * 0.5)
			for i in lc:
				var x := -(lc - 1) * pitch * 0.5 + i * pitch
				# устье топки в передней стенке
				if sz > 0.0 and layer >= 1 and layer <= 3 and absf(x) < 0.33:
					continue
				_lay_brick(Vector3(x, y, z), Basis.IDENTITY, true)

		# короткие стенки вдоль Z, слева и справа
		var sc := n_short if not long_owns_corner else n_short - 1
		for sx in [-1.0, 1.0]:
			var x2: float = sx * (half_l - bt * 0.5)
			for j in sc:
				var z2 := -(sc - 1) * pitch * 0.5 + j * pitch
				_lay_brick(Vector3(x2, y, z2), turn, true)

	# плита сверху, в ней отверстие под трубу
	var flue := Vector3(pitch, 0, -pitch * 1.0)
	var slab_y := BASE_Y + layers * CELL.y + Piece.BRICK_SIZE.y * 0.5
	var cols := n_long
	var rows := int((half_s * 2.0) / CELL.z)
	for c in cols:
		for r in rows:
			var x3 := -(cols - 1) * pitch * 0.5 + c * pitch
			var z3 := -(rows - 1) * CELL.z * 0.5 + r * CELL.z
			if absf(x3 - flue.x) < 0.2 and absf(z3 - flue.z) < 0.22:
				continue
			_lay_brick(Vector3(x3, slab_y, z3), Basis.IDENTITY, false)

	# труба из двух звеньев над отверстием
	for i in 2:
		var p := Piece.create(Piece.Kind.PIPE)
		pieces_root.add_child(p)
		p.global_position = Vector3(flue.x,
			slab_y + Piece.BRICK_SIZE.y * 0.5 + Piece.PIPE_H * 0.5 + i * (Piece.PIPE_H - 0.012),
			flue.z)
		p.cement()
		p.bond = 1.0
		_pieces.append(p)

	# чайник на плите, подальше от трубы
	var plate_y := slab_y + Piece.BRICK_SIZE.y * 0.5
	kettle = Kettle.create()
	add_child(kettle)
	kettle.global_position = Vector3(-pitch * 1.2, plate_y + Kettle.H * 0.5 + 0.004, pitch * 0.35)

	# чугунок рядом с чайником, хлеб и ведро пока в стороне
	pot = Cookware.create(Cookware.Kind.POT)
	add_child(pot)
	pot.global_position = Vector3(pitch * 0.1, plate_y + 0.1, pitch * 0.4)

	bread = Cookware.create(Cookware.Kind.BREAD)
	add_child(bread)
	bread.global_position = Vector3(-3.1, 0.99, -2.0)

	bucket = Bucket.create()
	add_child(bucket)
	bucket.global_position = Vector3(3.6, Bucket.H * 0.5 + 0.02, -1.95)

	# дрова и опилки в топке
	var fb := Vector3(0, BASE_Y + 0.02, 0.05)
	for i in 2:
		var log_piece := Piece.create(Piece.Kind.PROP)
		pieces_root.add_child(log_piece)
		log_piece.global_transform = Transform3D(
			Basis.from_euler(Vector3(0, randf_range(-0.35, 0.35), PI * 0.5)),
			fb + Vector3(0, Piece.PROP_R + i * 0.1, -0.06 + i * 0.12)
		)
		_pieces.append(log_piece)
	_pour_dust(fb + Vector3(0, 0.06, 0))
	_pour_hay(fb + Vector3(0, 0.2, 0.04), 4)
	_pour_chips(fb + Vector3(-0.05, 0.3, -0.02), 7)

	# запасы топлива в сарае — настоящими предметами: их можно расшвырять,
	# перетаскать в топку и сжечь
	_pour_hay(PechWorld.HAY_STOCK + Vector3(0, 0.12, 0), 16, 0.22)
	_pour_chips(PechWorld.CHIP_STOCK + Vector3(0, 0.1, 0), 26, 0.2)
	_pour_coal(PechWorld.COAL_STOCK + Vector3(0, 0.14, 0), 26, 0.24)

	# запас кирпича рядом с фундаментом
	for layer2 in 4:
		for k in 2:
			var pos3 := Vector3(1.28 + k * pitch, BASE_Y + layer2 * CELL.y + Piece.BRICK_SIZE.y * 0.5, -0.62)
			_lay_brick(pos3, Basis.IDENTITY, layer2 > 0)


func _lay_brick(pos: Vector3, rot: Basis, bed: bool) -> void:
	var p := Piece.create(Piece.Kind.BRICK, _variant)
	_variant += 1
	pieces_root.add_child(p)
	p.global_transform = Transform3D(
		rot * Basis.from_euler(Vector3(0, randf_range(-0.011, 0.011), 0)),
		pos + Vector3(randf_range(-0.004, 0.004), 0, randf_range(-0.004, 0.004))
	)
	p.cement()
	p.bond = 1.0        # демо-печка сложена как надо, с перевязкой
	_pieces.append(p)
	if not bed:
		return
	_mortar_bed(pos, rot, 1.0)


## Постель раствора под кирпичом: чуть выпирает по бокам, как выдавленный шов.
func _mortar_bed(pos: Vector3, rot: Basis, frac: float) -> void:
	var seam := CELL.y - Piece.BRICK_SIZE.y
	_add_seam(pos - Vector3(0, Piece.BRICK_SIZE.y * 0.5 + seam * 0.5, 0), rot,
		Vector3(Piece.BRICK_SIZE.x * frac * 1.01, seam, Piece.BRICK_SIZE.z * 1.02))


## Костёр на открытом месте — там, где свода нет, пламя ничем не ограничено.
func _light_bonfire() -> void:
	var at := Vector3(0, BASE_Y + 0.02, 2.2)
	for i in 3:
		var log_piece := Piece.create(Piece.Kind.PROP)
		pieces_root.add_child(log_piece)
		log_piece.global_transform = Transform3D(
			Basis.from_euler(Vector3(0, float(i) * 1.1, PI * 0.5)),
			at + Vector3(0, Piece.PROP_R + float(i) * 0.09, float(i) * 0.05 - 0.05)
		)
		log_piece.freeze = true
		log_piece.burning = true
		log_piece.heat = 1.0
		_pieces.append(log_piece)


func _ignite_demo() -> void:
	for kind in [Piece.Kind.HAY, Piece.Kind.DUST]:
		for p in _pieces:
			if p.kind == kind:
				p.burning = true
				p.heat = 1.0
				return
