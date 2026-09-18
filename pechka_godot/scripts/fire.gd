class_name FireSystem
extends Node3D

## Огонь, дым, искры и живой свет от пламени. Эмиттеры берём из пула и
## навешиваем на горящие предметы, лишние просто гасим.

const MAX_FIRES := 12
const FLAME_H := 0.30       # высота пламени «по умолчанию», под неё настроен эмиттер
const BLAST_TIME := 0.55    # сколько живёт вспышка от взрыва

var _flames: Array[GPUParticles3D] = []
var _sparks: Array[GPUParticles3D] = []
var _smokes: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _energy: Array[float] = []
var _chimney: GPUParticles3D
var _inferno: Node3D = null
var _room: GPUParticles3D = null
var _wind := Vector3.ZERO
var _dust: GPUParticles3D = null
var _steam: GPUParticles3D = null
var _torch: GPUParticles3D = null
var _torch_light: OmniLight3D = null
var _blast: GPUParticles3D = null
var _blast_light: OmniLight3D = null
var _blast_t := 0.0
var _blast_peak := 0.0

static var _ramps: Dictionary = {}
var _noise: FastNoiseLite
var _t := 0.0
var _active := 0
var _tones: Array[float] = []
var _quality := 0
var _max_on := MAX_FIRES
var _dense := 1.0           # общая поправка к плотности частиц


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.9
	_noise.seed = 4242

	for i in MAX_FIRES:
		var f := _make_flame()
		add_child(f)
		_flames.append(f)

		var s := _make_sparks()
		add_child(s)
		_sparks.append(s)

		var sm := _make_smoke(0.9)
		add_child(sm)
		_smokes.append(sm)

		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.56, 0.20)
		l.light_energy = 0.0
		l.light_specular = 0.6
		l.omni_range = 5.0
		l.omni_attenuation = 2.0
		l.shadow_bias = 0.05
		l.shadow_normal_bias = 1.2
		# огонь мерцает, и глобальное освещение честно пересчитывает от него
		# отражённый свет каждый кадр. Стоит это половины кадра, а видно
		# только дрожь в углах, поэтому в расчёт переотражений огонь не берём.
		l.light_bake_mode = Light3D.BAKE_DISABLED
		# кубическая тень от точечного света — это шесть проходов по сцене на
		# каждый огонёк; параболоид рисует то же самое за два
		l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		l.visible = false
		add_child(l)
		_lights.append(l)
		_energy.append(2.0)
		_tones.append(-1.0)

	_chimney = _make_smoke(2.2)
	_chimney.amount = 130
	_chimney.amount_ratio = 0.35
	_chimney.lifetime = 4.8
	_chimney.emitting = false
	add_child(_chimney)
	set_quality(_quality)


## Цена огня складывается из трёх вещей: теней от живых источников, шума
## завихрений в шейдере частиц и числа самих частиц. На среднем и низком
## режем всё три, на высоком оставляем как было.
func set_quality(q: int) -> void:
	_quality = clampi(q, 0, 2)
	var shadows: int = [2, 1, 0][_quality]
	var fog: int = [2, 0, 0][_quality]
	_max_on = [MAX_FIRES, 8, 5][_quality]
	_dense = [1.0, 0.8, 0.55][_quality]
	for i in MAX_FIRES:
		_lights[i].shadow_enabled = i < shadows
		# каждый источник в объёмном тумане — отдельный проход по сетке
		_lights[i].light_volumetric_fog_energy = 2.4 if i < fog else 0.0
		# завихрения дороги, но без них дым идёт ровным столбом: оставляем
		# их пламени, у которого форма и читается, а дыму и искрам гасим
		_turbulence(_smokes[i], _quality == 0)
		_turbulence(_sparks[i], _quality < 2)
	if _chimney:
		_turbulence(_chimney, _quality == 0)
	# мягкое врезание дыма в кладку требует чтения глубины на каждый пиксель:
	# на высоком это того стоит, ниже — нет
	_smoke_mat().proximity_fade_enabled = _quality == 0


## Ракетный след: из улетающей трубы бьёт вниз пламя и остаётся столб дыма.
## Частицы живут в мировых координатах, поэтому за трубой тянется хвост, а
## не едет вместе с ней облачко.
func attach_trail(target: Node3D, life := 5.0) -> void:
	var f := _make_flame()
	f.amount = 170
	f.lifetime = 0.8
	f.local_coords = false
	f.visibility_aabb = AABB(Vector3(-6, -40, -6), Vector3(12, 80, 12))
	var fpm := f.process_material as ParticleProcessMaterial
	fpm.direction = Vector3(0, -1, 0)
	fpm.spread = 11.0
	fpm.initial_velocity_min = 3.5
	fpm.initial_velocity_max = 8.0
	fpm.gravity = Vector3(0, -1.5, 0)
	fpm.scale_min = 0.09
	fpm.scale_max = 0.26
	f.emitting = true
	target.add_child(f)

	var sm := _make_smoke(1.1)
	sm.amount = 200
	sm.amount_ratio = 1.0
	sm.lifetime = 2.8
	sm.preprocess = 0.0
	sm.local_coords = false
	sm.visibility_aabb = AABB(Vector3(-8, -40, -8), Vector3(16, 80, 16))
	var spm := sm.process_material as ParticleProcessMaterial
	spm.direction = Vector3(0, -1, 0)
	spm.spread = 16.0
	spm.initial_velocity_min = 1.2
	spm.initial_velocity_max = 3.4
	spm.gravity = Vector3(0, 0.2, 0)
	spm.scale_min = 0.28
	spm.scale_max = 0.62
	# белый след виден и против яркого неба, серый дым там теряется
	spm.color_ramp = _steam_ramp()
	sm.emitting = true
	target.add_child(sm)

	# хвост гаснет сам: дальше трубе лететь уже некуда
	var t := get_tree().create_timer(life)
	t.timeout.connect(func() -> void:
		if is_instance_valid(f):
			f.emitting = false
			f.queue_free()
		if is_instance_valid(sm):
			sm.emitting = false
			sm.queue_free())


## Отладка скорости: спрятать часть огня и посмотреть, что стоит кадров.
func debug_off(what: String) -> void:
	for i in MAX_FIRES:
		match what:
			"fire":
				_flames[i].visible = false
				_sparks[i].visible = false
			"smoke":
				_smokes[i].visible = false
			"light":
				_lights[i].light_energy = 0.0
				_lights[i].shadow_enabled = false
	if what == "smoke" and _chimney:
		_chimney.visible = false


func _turbulence(p: GPUParticles3D, on: bool) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	if pm:
		pm.turbulence_enabled = on


## Расставить огонь по горящим предметам. Каждый очаг описывается словарём:
##   pos    — где горит
##   height — высота языков в метрах (у щепок коротко, у кругляка высоко)
##   speed  — насколько шустро пламя рвётся вверх
##   flame  — яркость пламени, smoke — густота дыма
##   tone   — 0 тёмно-серый дым от дерева, 1 светло-серый от опилок
func set_fires(fires: Array) -> void:
	_active = mini(fires.size(), _max_on)
	# Десяток очагов рядом — это всё равно один костёр, а не десять солнц:
	# гасим вклад каждого, иначе свет и аддитивное пламя выжигают кадр.
	var norm := 1.0 / sqrt(maxf(1.0, float(_active)))
	var dense := clampf(3.0 / maxf(1.0, float(_active)), 0.3, 1.0)
	for i in MAX_FIRES:
		var on := i < _active
		_flames[i].emitting = on
		_sparks[i].emitting = on
		_smokes[i].emitting = on
		_lights[i].visible = on
		if not on:
			continue
		var f: Dictionary = fires[i]
		var pos: Vector3 = f["pos"]
		var h: float = f.get("height", FLAME_H)
		var fl: float = f.get("flame", 1.0)
		var sm: float = f.get("smoke", 0.3)

		# куча из нескольких поленьев горит широким костром, одно полено — язычком
		var vs := h / FLAME_H
		var hs: float = maxf(vs, clampf(f.get("width", 0.0) / 0.09, 0.0, 3.0))
		_flames[i].position = pos
		_flames[i].scale = Vector3(hs, vs, hs)
		_flames[i].speed_scale = f.get("speed", 1.0)
		_sparks[i].position = pos
		_sparks[i].scale = Vector3.ONE * clampf(h / FLAME_H, 0.5, 1.6)
		_smokes[i].position = pos + Vector3(0, h * 0.7, 0)
		_lights[i].position = pos + Vector3(0, h * 0.6, 0)

		# дым не должен тонуть в пламени, поэтому его нижний порог высокий
		_smokes[i].amount_ratio = clampf(sm * (0.55 + 0.45 * dense) * _dense, 0.1, 1.0)
		_flames[i].amount_ratio = clampf(fl * dense * _dense, 0.08, 1.0)
		_sparks[i].amount_ratio = clampf(fl * dense * 0.7 * _dense, 0.05, 1.0)
		_energy[i] = 2.0 * fl * norm
		_set_smoke_tone(i, f.get("tone", 0.0))


func set_chimney(pos: Vector3, active: bool, thickness: float = 0.35, tone: float = 0.0) -> void:
	_chimney.emitting = active
	if active:
		_chimney.position = pos
		_chimney.amount_ratio = clampf(thickness, 0.1, 1.0)
		var pm := _chimney.process_material as ParticleProcessMaterial
		pm.color_ramp = _smoke_ramp(snappedf(clampf(tone, 0.0, 1.0), 0.5))


## Дым, который не ушёл в трубу, валит из устья в сарай: медленно, широко и
## низко над полом. Создаём эмиттер по первой надобности.
func set_room_smoke(pos: Vector3, amount: float) -> void:
	if _room == null:
		_room = _make_smoke(3.4)
		_room.amount = 70
		_room.lifetime = 6.0
		var pm := _room.process_material as ParticleProcessMaterial
		pm.emission_sphere_radius = 0.22
		pm.spread = 60.0
		pm.initial_velocity_min = 0.12
		pm.initial_velocity_max = 0.5
		pm.gravity = Vector3(0.1, 0.3, 0.04)
		pm.color_ramp = _smoke_ramp(0.5)
		add_child(_room)
	_room.emitting = amount > 0.02
	if _room.emitting:
		_room.position = pos
		_room.amount_ratio = clampf(amount, 0.05, 1.0)


## Угольная пыль, поднятая в воздух. Чёрная, мелкая, висит и медленно
## оседает — и именно она потом и рвёт.
func set_coal_dust(pos: Vector3, amount: float) -> void:
	if _dust == null:
		if amount <= 0.0:
			return
		_dust = _make_smoke(1.5)
		_dust.amount = 110
		_dust.lifetime = 3.6
		var pm := _dust.process_material as ParticleProcessMaterial
		pm.emission_sphere_radius = 0.38
		pm.spread = 80.0
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.45
		pm.gravity = Vector3(0, 0.12, 0)
		pm.color_ramp = _dust_ramp()
		add_child(_dust)
	_dust.emitting = amount > 0.02
	if _dust.emitting:
		_dust.position = pos
		_dust.amount_ratio = clampf(amount, 0.05, 1.0)


## Взрыв: короткая вспышка огня и света на месте.
func blast(pos: Vector3, power: float) -> void:
	if _blast == null:
		_blast = _make_flame()
		_blast.amount = 320
		_blast.lifetime = 0.85
		_blast.one_shot = true
		_blast.explosiveness = 0.95
		_blast.preprocess = 0.0
		_blast.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 9, 12))
		var pm := _blast.process_material as ParticleProcessMaterial
		pm.emission_sphere_radius = 0.35
		pm.spread = 180.0
		pm.initial_velocity_min = 2.5
		pm.initial_velocity_max = 8.0
		pm.gravity = Vector3(0, 1.6, 0)
		pm.scale_min = 0.12
		pm.scale_max = 0.5
		add_child(_blast)

		_blast_light = OmniLight3D.new()
		_blast_light.light_color = Color(1.0, 0.72, 0.36)
		_blast_light.omni_range = 14.0
		_blast_light.shadow_enabled = false
		_blast_light.light_bake_mode = Light3D.BAKE_DISABLED
		_blast_light.visible = false
		add_child(_blast_light)

	_blast.position = pos
	_blast.scale = Vector3.ONE * clampf(power, 0.4, 2.0)
	_blast.restart()
	_blast.emitting = true
	_blast_light.position = pos + Vector3(0, 0.3, 0)
	_blast_peak = 14.0 * clampf(power, 0.4, 2.0)
	_blast_t = BLAST_TIME


## Горящая сажа: из трубы бьёт длинный ревущий факел.
func set_flue_fire(pos: Vector3, on: bool) -> void:
	if _torch == null:
		if not on:
			return
		_torch = _make_flame()
		_torch.amount = 260
		_torch.lifetime = 0.9
		_torch.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 6, 4))
		var pm := _torch.process_material as ParticleProcessMaterial
		pm.emission_sphere_radius = 0.07
		pm.spread = 14.0
		pm.initial_velocity_min = 4.5
		pm.initial_velocity_max = 9.0
		pm.gravity = Vector3(0, 3.0, 0)
		pm.scale_min = 0.05
		pm.scale_max = 0.16
		add_child(_torch)

		_torch_light = OmniLight3D.new()
		_torch_light.light_color = Color(1.0, 0.55, 0.22)
		_torch_light.omni_range = 9.0
		_torch_light.light_energy = 4.0
		_torch_light.shadow_enabled = false
		_torch_light.light_bake_mode = Light3D.BAKE_DISABLED
		add_child(_torch_light)
	_torch.emitting = on
	_torch_light.visible = on
	if on:
		_torch.position = pos
		_torch_light.position = pos + Vector3(0, 0.6, 0)


## Клуб пара: вода на раскалённой кладке уходит вверх белой стеной.
func steam_burst(pos: Vector3, power: float) -> void:
	if _steam == null:
		_steam = _make_smoke(1.2)
		_steam.amount = 180
		_steam.lifetime = 1.9
		_steam.one_shot = true
		_steam.explosiveness = 0.85
		_steam.preprocess = 0.0
		var pm := _steam.process_material as ParticleProcessMaterial
		pm.emission_sphere_radius = 0.22
		pm.spread = 75.0
		pm.initial_velocity_min = 1.2
		pm.initial_velocity_max = 3.4
		pm.gravity = Vector3(0, 1.1, 0)
		pm.color_ramp = _steam_ramp()
		add_child(_steam)
	_steam.position = pos
	_steam.scale = Vector3.ONE * clampf(power, 0.5, 1.6)
	_steam.restart()
	_steam.emitting = true


static func _steam_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(0.97, 0.97, 0.98, 0.62),
		Color(0.9, 0.91, 0.93, 0.3),
		Color(0.86, 0.88, 0.9, 0.0),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


static func _dust_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(0.20, 0.185, 0.18, 0.0),
		Color(0.20, 0.185, 0.18, 0.62),
		Color(0.23, 0.213, 0.205, 0.42),
		Color(0.25, 0.232, 0.225, 0.0),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


## Цвет дыма меняем только когда в топке действительно сменилось топливо —
## пересобирать градиент каждый кадр было бы расточительно.
func _set_smoke_tone(i: int, tone: float) -> void:
	var t := snappedf(clampf(tone, 0.0, 1.0), 0.5)
	if is_equal_approx(_tones[i], t):
		return
	_tones[i] = t
	var pm := _smokes[i].process_material as ParticleProcessMaterial
	pm.color_ramp = _smoke_ramp(t)


## Пожар на всю площадь сарая: сетка широких очагов плюс общий оранжевый свет.
func start_inferno(hx: float, hz: float, y: float) -> void:
	if _inferno != null:
		return
	_inferno = Node3D.new()
	add_child(_inferno)

	# крупных очагов мало, но каждый разбрасывает частицы по своей клетке —
	# иначе финал съедает половину кадров
	var cols := 3
	var rows := 2
	var cell := Vector3(hx / float(cols), 0.12, hz / float(rows))
	for ix in cols:
		for iz in rows:
			var at := Vector3(
				-hx + (float(ix) + 0.5) * (hx * 2.0 / float(cols)),
				y,
				-hz + (float(iz) + 0.5) * (hz * 2.0 / float(rows))
			)
			var f := _make_flame()
			f.amount = 90
			f.amount_ratio = _dense
			f.lifetime = 1.5
			f.visibility_aabb = AABB(Vector3(-4, -0.5, -4), Vector3(8, 12, 8))
			var fpm := f.process_material as ParticleProcessMaterial
			fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			fpm.emission_box_extents = cell
			fpm.initial_velocity_min = 1.8
			fpm.initial_velocity_max = 5.0
			fpm.gravity = Vector3(0, 3.8, 0)
			# мелкие частицы читаются как языки огня, крупные — как оранжевые шары
			fpm.scale_min = 0.2
			fpm.scale_max = 0.58
			f.position = at
			f.emitting = true
			_inferno.add_child(f)

			var sm := _make_smoke(3.2)
			sm.amount = 44
			sm.amount_ratio = _dense
			_turbulence(sm, _quality == 0)
			sm.lifetime = 5.5
			sm.visibility_aabb = AABB(Vector3(-6, -0.5, -6), Vector3(12, 16, 12))
			var spm := sm.process_material as ParticleProcessMaterial
			spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			spm.emission_box_extents = cell
			sm.position = at + Vector3(0, 1.3, 0)
			sm.emitting = true
			_inferno.add_child(sm)

	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.44, 0.13)
		l.light_energy = 1.6
		l.omni_range = 12.0
		l.omni_attenuation = 1.6
		l.light_bake_mode = Light3D.BAKE_DISABLED
		l.light_volumetric_fog_energy = 1.8 if _quality == 0 else 0.0
		l.position = Vector3(
			hx * (0.6 if i % 2 == 0 else -0.6),
			1.7,
			hz * (0.6 if i < 2 else -0.6)
		)
		_inferno.add_child(l)


func stop_inferno() -> void:
	if _inferno != null:
		_inferno.queue_free()
		_inferno = null


func _process(delta: float) -> void:
	_t += delta
	for i in _active:
		var n := _noise.get_noise_2d(_t * 2.6, float(i) * 31.0)
		var n2 := _noise.get_noise_2d(_t * 7.3, float(i) * 11.0)
		_lights[i].light_energy = maxf(0.08, _energy[i] + n * 0.2 + n2 * 0.08)
		_lights[i].omni_range = 5.0 + n * 0.15
		_lights[i].light_color = Color(1.0, 0.52 + n2 * 0.06, 0.18 + n * 0.05)

	if _blast_t > 0.0:
		_blast_t = maxf(0.0, _blast_t - delta)
		# вспышка гаснет резко, но не мгновенно — иначе кадр просто мигает
		var k := _blast_t / BLAST_TIME
		_blast_light.light_energy = _blast_peak * k * k
		_blast_light.visible = _blast_t > 0.0


# ---------------------------------------------------------------- эмиттеры

func _make_flame() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 72
	p.lifetime = 0.45
	p.preprocess = 0.3
	p.explosiveness = 0.0
	p.randomness = 0.45
	p.fixed_fps = 0
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-0.6, -0.2, -0.6), Vector3(1.2, 1.4, 1.2))
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.055
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	# скорость и тяга подобраны так, чтобы язык вырастал ровно на FLAME_H;
	# выше или ниже пламя делается масштабом эмиттера в set_fires
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.75
	pm.gravity = Vector3(0, 0.9, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.scale_min = 0.075
	pm.scale_max = 0.175
	pm.scale_curve = _curve([[0.0, 0.30], [0.18, 1.0], [0.62, 0.75], [1.0, 0.04]])
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -70.0
	pm.angular_velocity_max = 70.0
	# частица живёт снизу вверх, поэтому градиент по времени жизни — это и есть
	# градиент по высоте: у корня бело-жёлтое ядро, выше оранжевый, на излёте красный
	pm.color_ramp = _grad([
		[0.00, Color(1.00, 0.98, 0.90, 0.00)],
		[0.06, Color(1.00, 0.96, 0.76, 0.46)],
		[0.20, Color(1.00, 0.74, 0.26, 0.44)],
		[0.44, Color(1.00, 0.42, 0.09, 0.35)],
		[0.70, Color(0.88, 0.17, 0.03, 0.22)],
		[0.90, Color(0.46, 0.06, 0.02, 0.08)],
		[1.00, Color(0.12, 0.02, 0.01, 0.00)],
	])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.8
	pm.turbulence_noise_scale = 2.4
	pm.turbulence_noise_speed = Vector3(0.5, 1.1, 0.4)
	pm.turbulence_influence_min = 0.15
	pm.turbulence_influence_max = 0.55
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.draw_pass_1 = quad
	p.material_override = _flame_mat()
	return p


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.6
	p.randomness = 0.7
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-1.5, -0.3, -1.5), Vector3(3.0, 4.0, 3.0))
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 32.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 3.4
	pm.gravity = Vector3(0, 0.55, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.4
	pm.scale_min = 0.012
	pm.scale_max = 0.032
	pm.scale_curve = _curve([[0.0, 1.0], [0.7, 0.8], [1.0, 0.0]])
	pm.color_ramp = _grad([
		[0.00, Color(1.00, 0.95, 0.70, 1.00)],
		[0.35, Color(1.00, 0.55, 0.15, 0.95)],
		[0.75, Color(0.85, 0.22, 0.03, 0.45)],
		[1.00, Color(0.30, 0.05, 0.00, 0.00)],
	])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.6
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_noise_speed = Vector3(0.8, 1.4, 0.8)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.draw_pass_1 = quad
	p.material_override = _spark_mat()
	return p


## Ветер сносит дым: чем крепче дует, тем сильнее столб ложится набок.
## Слабый дымок гнётся охотнее густого — у него меньше своей тяги вверх.
func set_wind(v: Vector3) -> void:
	if v.distance_to(_wind) < 0.02:
		return                       # перебирать все очаги на каждый чих незачем
	_wind = v
	for p in _smokes:
		var pm := p.process_material as ParticleProcessMaterial
		pm.gravity = Vector3(0.35 + v.x * 7.0, 0.75, 0.12 + v.z * 7.0)
	if _room:
		var rm := _room.process_material as ParticleProcessMaterial
		rm.gravity = Vector3(v.x * 1.4, rm.gravity.y, v.z * 1.4)


func _make_smoke(scale: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 84
	p.amount_ratio = 0.3
	p.lifetime = 3.6
	p.preprocess = 1.2
	p.randomness = 0.5
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 9, 6))
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.09 * scale
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.95
	pm.gravity = Vector3(0.35, 0.75, 0.12)
	pm.damping_min = 0.1
	pm.damping_max = 0.4
	pm.scale_min = 0.22 * scale
	pm.scale_max = 0.48 * scale
	pm.scale_curve = _curve([[0.0, 0.25], [0.35, 0.7], [1.0, 1.0]])
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -22.0
	pm.angular_velocity_max = 22.0
	pm.color_ramp = _smoke_ramp(0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.1
	pm.turbulence_noise_scale = 1.4
	pm.turbulence_noise_speed = Vector3(0.3, 0.5, 0.25)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.draw_pass_1 = quad
	p.material_override = _smoke_mat()
	return p


# ---------------------------------------------------------------- материалы

func _flame_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Mats.blob_tex(128, 1.9)
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _spark_mat() -> StandardMaterial3D:
	var m := _flame_mat()
	m.albedo_texture = Mats.spark_tex()
	return m


## Материал дыма один на все клубы: и переключений состояния меньше, и
## качество настраивается разом. Дым — главный едок кадров, потому что
## полупрозрачные клубы лежат друг на друге в несколько слоёв, и каждый
## пиксель считается заново. Свет по вершинам вместо попиксельного и
## отказ от теней на дыме дают самый крупный выигрыш во всей игре.
static var _smoke_material: StandardMaterial3D = null


static func _smoke_mat() -> StandardMaterial3D:
	if _smoke_material != null:
		return _smoke_material
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Mats.puff_tex(256)
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = false
	m.proximity_fade_distance = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_smoke_material = m
	return m


# ---------------------------------------------------------------- утилиты

## Дым от дерева почти чёрный, от опилок — светло-серый. Непрозрачность
## заметная: дым должен читаться и на фоне яркого пламени.
static func _smoke_ramp(tone: float) -> GradientTexture1D:
	if _ramps.has(tone):
		return _ramps[tone]
	# альбедо нарочно очень низкое: дым висит в упор к огню и при обычных
	# значениях светится белым вместо того чтобы коптить
	var c := Color(0.045, 0.040, 0.036).lerp(Color(0.40, 0.385, 0.365), tone)
	var ramp := _grad([
		[0.00, Color(c.r, c.g, c.b, 0.00)],
		[0.10, Color(c.r, c.g, c.b, 0.58)],
		[0.45, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.36)],
		[1.00, Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, 0.00)],
	])
	_ramps[tone] = ramp
	return ramp


static func _grad(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, stops[0][0])
	g.set_color(0, stops[0][1])
	g.set_offset(1, stops[stops.size() - 1][0])
	g.set_color(1, stops[stops.size() - 1][1])
	for i in range(1, stops.size() - 1):
		g.add_point(stops[i][0], stops[i][1])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 128
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var t := CurveTexture.new()
	t.curve = c
	t.width = 128
	return t
