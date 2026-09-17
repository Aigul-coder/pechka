class_name PechWeather
extends Node3D

## Погода целиком: время года, что на дворе, сила ветра, небо с облаками,
## звёзды и луна, осадки, гроза, туман, радуга и лужи.
##
## Всё живёт данными: у каждого сезона свой список погод и своя палитра,
## у каждой погоды — тип осадков, плотность облаков, ветер и температура.
## Свет собирается в одном месте из трёх слагаемых: время суток, сезон и
## погода, — иначе они начинают спорить и картинка плывёт.

# ------------------------------------------------------------------ данные

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Kind {
	CLEAR, FAIR, DRIZZLE, RAIN, DOWNPOUR, STORM, SUNSHOWER,
	SNOW, BLIZZARD, WHITEOUT, HAIL, SLEET, FOG,
}
enum Drop { NONE, RAIN, SNOW, HAIL }

const SEASON_NAMES := ["весна", "лето", "осень", "зима"]
const KIND_NAMES := [
	"ясно", "облачно", "морось", "дождь", "ливень", "гроза", "грибной дождь",
	"снег", "метель", "пурга", "град", "ледяной дождь", "туман",
]

## Из чего складывается погода. Всё в долях 0..1, кроме температуры и Бофорта.
##   drop     — что сыплется с неба
##   power    — сколько сыплется
##   cloud    — плотность облачного слоя
##   dark     — насколько облака тяжёлые и тёмные
##   beaufort — базовая сила ветра по шкале Бофорта
##   fog      — низовой туман
##   temp     — поправка к температуре сезона
const KINDS := {
	Kind.CLEAR:     {"drop": Drop.NONE, "power": 0.0, "cloud": 0.12, "dark": 0.0, "beaufort": 2.0, "fog": 0.0, "temp": 2.0},
	Kind.FAIR:      {"drop": Drop.NONE, "power": 0.0, "cloud": 0.55, "dark": 0.25, "beaufort": 3.0, "fog": 0.05, "temp": 0.0},
	Kind.DRIZZLE:   {"drop": Drop.RAIN, "power": 0.18, "cloud": 0.85, "dark": 0.45, "beaufort": 2.0, "fog": 0.35, "temp": -2.0},
	Kind.RAIN:      {"drop": Drop.RAIN, "power": 0.5, "cloud": 0.95, "dark": 0.6, "beaufort": 4.0, "fog": 0.2, "temp": -4.0},
	Kind.DOWNPOUR:  {"drop": Drop.RAIN, "power": 1.0, "cloud": 1.0, "dark": 0.8, "beaufort": 6.0, "fog": 0.3, "temp": -5.0},
	Kind.STORM:     {"drop": Drop.RAIN, "power": 0.9, "cloud": 1.0, "dark": 1.0, "beaufort": 8.0, "fog": 0.25, "temp": -3.0},
	Kind.SUNSHOWER: {"drop": Drop.RAIN, "power": 0.35, "cloud": 0.4, "dark": 0.2, "beaufort": 2.0, "fog": 0.1, "temp": 0.0},
	Kind.SNOW:      {"drop": Drop.SNOW, "power": 0.45, "cloud": 0.9, "dark": 0.35, "beaufort": 3.0, "fog": 0.25, "temp": -2.0},
	Kind.BLIZZARD:  {"drop": Drop.SNOW, "power": 0.85, "cloud": 1.0, "dark": 0.5, "beaufort": 8.0, "fog": 0.45, "temp": -7.0},
	Kind.WHITEOUT:  {"drop": Drop.SNOW, "power": 1.0, "cloud": 1.0, "dark": 0.6, "beaufort": 11.0, "fog": 0.85, "temp": -12.0},
	Kind.HAIL:      {"drop": Drop.HAIL, "power": 0.7, "cloud": 1.0, "dark": 0.9, "beaufort": 6.0, "fog": 0.15, "temp": -6.0},
	Kind.SLEET:     {"drop": Drop.RAIN, "power": 0.55, "cloud": 1.0, "dark": 0.7, "beaufort": 5.0, "fog": 0.3, "temp": -1.0},
	Kind.FOG:       {"drop": Drop.NONE, "power": 0.0, "cloud": 0.7, "dark": 0.3, "beaufort": 0.0, "fog": 1.0, "temp": -3.0},
}

## Какая погода когда бывает. Град и гроза — летние, пурга — зимняя.
const SEASON_KINDS := {
	Season.SPRING: [Kind.CLEAR, Kind.FAIR, Kind.DRIZZLE, Kind.RAIN, Kind.SUNSHOWER, Kind.FOG, Kind.SLEET],
	Season.SUMMER: [Kind.CLEAR, Kind.FAIR, Kind.RAIN, Kind.DOWNPOUR, Kind.STORM, Kind.SUNSHOWER, Kind.HAIL],
	Season.AUTUMN: [Kind.CLEAR, Kind.FAIR, Kind.DRIZZLE, Kind.RAIN, Kind.DOWNPOUR, Kind.FOG, Kind.SLEET, Kind.SNOW],
	Season.WINTER: [Kind.CLEAR, Kind.FAIR, Kind.SNOW, Kind.BLIZZARD, Kind.WHITEOUT, Kind.FOG, Kind.SLEET],
}

## Базовая температура сезона и цвет травы.
const SEASON_TEMP := [8.0, 26.0, 7.0, -16.0]
## Тон умножается на зелёную фотографию травы, поэтому осень приходится
## задавать с запасом по красному — иначе поле так и остаётся летним.
const SEASON_GRASS := [
	Color(0.52, 0.66, 0.34), Color(0.46, 0.54, 0.38),
	Color(0.80, 0.62, 0.28), Color(0.80, 0.92, 1.10),
]

## Время суток. Высота солнца над горизонтом и поворот — по дуге, как надо.
const PHASE_NAMES := ["рассвет", "утро", "день", "вечер", "ночь"]
const SUN_PITCH := [-8.0, -34.0, -62.0, -14.0, -46.0]
const SUN_YAW := [118.0, 140.0, 165.0, -24.0, -30.0]

## Шкала Бофорта — как её называют и что с ней делать.
const BEAUFORT_NAMES := [
	"штиль", "тихий", "лёгкий", "слабый", "умеренный", "свежий", "сильный",
	"крепкий", "очень крепкий", "шторм", "сильный шторм", "жестокий шторм", "ураган",
]

# ------------------------------------------------------------------ состояние

var season := Season.SUMMER
var kind := Kind.CLEAR
var phase := 2                       ## индекс в PHASE_NAMES
var beaufort := 2.0                  ## текущая сила ветра, 0..12
var wind_dir := 0.6                  ## откуда дует, радианы вокруг Y
var wet := 0.0                       ## сколько воды налилось во двор, 0..1
var snow_pack := 0.0                 ## сколько снега лежит, 0..1
var lightning_at := Vector3.ZERO     ## куда ударило в последний раз
var moon_phase := 2                  ## 0 новолуние, 1 растущая, 2 полная, 3 убывающая

signal struck(at: Vector3, distance: float, hit_pipe: bool)
signal thunder(power: float, at: Vector3)
signal rainbow_out()
signal gust(force: float)

var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D

var _sky_day: Material
var _sky_grey: ProceduralSkyMaterial
var _sky_warm: Dictionary = {}       ## рассветное и закатное небо
var _sky_night: PanoramaSkyMaterial
var _clouds: MultiMeshInstance3D
var _cloud_mat: StandardMaterial3D
var _cloud_home: PackedVector3Array = PackedVector3Array()
var _cloud_drift := Vector3.ZERO
var _moon: MeshInstance3D
var _moon_mats: Array[StandardMaterial3D] = []
var _twinkle: MultiMeshInstance3D
var _twinkle_t := 0.0

var _precip: Array[GPUParticles3D] = []
var _splash: GPUParticles3D           ## отскок капель от земли
var _leaves: GPUParticles3D           ## осенний лист по ветру
var _snow_fields: Array[MeshInstance3D] = []
var _puddles: Array[MeshInstance3D] = []
var _rainbow: MeshInstance3D
var _rainbow_k := 0.0
var _rainbow_seen := false

var _bolt: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _flash: DirectionalLight3D
var _flash_k := 0.0
var _strike_cd := 4.0
var _thunder: Array = []              ## отложенные раскаты: [время, сила, место]

var _noise: FastNoiseLite
var _t := 0.0
var _gust_t := 0.0
var _rng := RandomNumberGenerator.new()
var _fog_vol: FogVolume
var _quality := 1
var _seen: Dictionary = {}            ## какие погоды игрок уже застал


# ------------------------------------------------------------------ сборка

func setup(e: Environment, s: DirectionalLight3D, f: DirectionalLight3D, day_sky: Material) -> void:
	env = e
	sun = s
	fill = f
	_sky_day = day_sky
	_rng.seed = 20260917
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 4471
	_build_clouds()
	_build_moon()
	_build_precip()
	_build_puddles()
	_build_rainbow()
	_build_bolt()
	apply()


## Сколько на дворе градусов: сезон плюс поправка погоды плюс ночной холод.
func outside_temp() -> float:
	var t: float = SEASON_TEMP[season] + float(KINDS[kind]["temp"])
	t += [-3.0, -1.0, 1.5, -1.0, -5.0][phase]
	return t


func kind_name() -> String:
	return KIND_NAMES[kind]


func season_name() -> String:
	return SEASON_NAMES[season]


func phase_name() -> String:
	return PHASE_NAMES[phase]


func wind_name() -> String:
	return BEAUFORT_NAMES[clampi(roundi(beaufort), 0, 12)]


## Ветер как вектор: пригодится дыму, осадкам и тяге в трубе.
func wind_vec() -> Vector3:
	return Vector3(sin(wind_dir), 0.0, cos(wind_dir)) * (beaufort / 12.0)


## Старое поле wind в 0..1 — им меряется тяга.
func wind01() -> float:
	return clampf(beaufort / 12.0, 0.0, 1.0)


## Насколько далеко видно, метры. Нужно и туману, и подсказке в углу.
func visibility() -> float:
	var d: float = float(KINDS[kind]["fog"])
	if phase == 0:
		d = maxf(d, 0.55)
	# видно ровно столько, сколько пропускает туман: втрое меньше его плотности
	var far := 3.0 / maxf(lerpf(0.00015, 0.035, pow(d, 2.0)), 0.0003)
	if kind == Kind.WHITEOUT:
		far = 10.0
	return clampf(far, 10.0, 10000.0)


func seen_count() -> int:
	return _seen.size()


func set_season(s: int) -> void:
	season = clampi(s, 0, 3) as Season
	var list: Array = SEASON_KINDS[season]
	if not list.has(kind):
		kind = list[0]
	apply()


func next_season() -> void:
	set_season((season + 1) % 4)


func set_kind(k: int) -> void:
	kind = clampi(k, 0, KIND_NAMES.size() - 1) as Kind
	apply()


## Следующая погода из тех, что бывают в этом сезоне.
func next_kind() -> void:
	var list: Array = SEASON_KINDS[season]
	var i := list.find(kind)
	set_kind(list[(i + 1) % list.size()])


func set_phase(p: int) -> void:
	phase = clampi(p, 0, PHASE_NAMES.size() - 1)
	apply()


func next_phase() -> void:
	set_phase((phase + 1) % PHASE_NAMES.size())


func set_quality(q: int) -> void:
	_quality = clampi(q, 0, 2)
	_apply_precip()
	if _clouds:
		var mm := _clouds.multimesh
		mm.visible_instance_count = roundi(mm.instance_count * _cloud_share())


# ------------------------------------------------------------------ применение

## Пересобрать всю картину: небо, свет, туман, осадки, снег во дворе.
func apply() -> void:
	_seen[kind] = true
	beaufort = float(KINDS[kind]["beaufort"])
	_apply_sky()
	_apply_light()
	_apply_fog()
	_apply_precip()
	_apply_ground()
	# листопад зависит от ветра, а он гуляет каждую секунду
	if _leaves:
		_leaves.emitting = season == Season.AUTUMN
	if _moon:
		_moon.visible = phase == 4 and float(KINDS[kind]["cloud"]) < 0.8


func _cloud_share() -> float:
	var c: float = float(KINDS[kind]["cloud"])
	return c * [1.0, 0.75, 0.45][_quality]


func _apply_sky() -> void:
	if env.sky == null:
		return
	var want: Material = _sky_day
	if phase == 4:
		want = _night_sky()
	elif float(KINDS[kind]["dark"]) > 0.3:
		want = _grey_sky()
	elif phase == 0 or phase == 3:
		# на рассвете и закате готовая панорама с полуденным небом врёт:
		# нужен тёплый горизонт и глубокая синь наверху
		want = _warm_sky(phase == 0)
	if env.sky.sky_material != want:
		env.sky.sky_material = want

	# яркость неба: время суток, приглушённое облаками
	var e: float = [0.45, 0.9, 1.0, 0.5, 0.11][phase]
	e *= lerpf(1.0, 0.35, float(KINDS[kind]["dark"]))
	env.sky.sky_material.set("energy_multiplier", e)

	if _clouds:
		var mm := _clouds.multimesh
		mm.visible_instance_count = roundi(mm.instance_count * _cloud_share())
		_clouds.visible = mm.visible_instance_count > 0
		# облака красятся под время суток и тяжесть погоды
		var tint: Color = [
			Color(1.0, 0.74, 0.58), Color(1.0, 0.96, 0.92), Color(1.0, 1.0, 1.0),
			Color(1.0, 0.64, 0.44), Color(0.10, 0.12, 0.18),
		][phase]
		var dark: float = float(KINDS[kind]["dark"])
		_cloud_mat.albedo_color = tint.lerp(Color(0.20, 0.21, 0.24), dark * 0.8)
		# пуховок в облаке много и они лежат друг на друге, поэтому каждая
		# почти прозрачна — плотность набирается наложением, как в природе
		_cloud_mat.albedo_color.a = lerpf(0.13, 0.26, dark) * (0.45 if phase == 4 else 1.0)
	if _twinkle:
		_twinkle.visible = phase == 4 and float(KINDS[kind]["cloud"]) < 0.7


## Свет — три слоя разом: солнце по дуге, заполняющий с неба и общий фон.
func _apply_light() -> void:
	var dark: float = float(KINDS[kind]["dark"])
	var night := phase == 4

	sun.rotation_degrees = Vector3(SUN_PITCH[phase], SUN_YAW[phase], 0.0)
	# закат красит косые лучи в апельсин, но не в чистый красный: на зелёной
	# траве чистый красный даёт чёрное поле, и вечер превращается в ночь
	var sun_c: Color = [
		Color(1.0, 0.68, 0.42), Color(1.0, 0.88, 0.72), Color(1.0, 0.94, 0.84),
		Color(1.0, 0.60, 0.33), Color(0.62, 0.74, 1.0),
	][phase]
	var sun_e: float = [1.9, 1.8, 2.0, 1.8, 0.6][phase]
	if night:
		# ночью светит луна, и чем она полнее, тем светлее двор
		sun_e *= [0.25, 0.7, 1.4, 0.7][moon_phase]
	# облака съедают прямой свет и делают его плоским
	sun_e *= lerpf(1.0, 0.16, dark)
	sun_c = sun_c.lerp(Color(0.74, 0.78, 0.84), dark * 0.7)
	if season == Season.WINTER:
		sun_c = sun_c.lerp(Color(0.86, 0.92, 1.0), 0.35)
	sun.light_color = sun_c
	sun.light_energy = sun_e
	sun.light_angular_distance = lerpf(0.55, 4.0, dark)

	fill.light_color = [
		Color(0.60, 0.66, 0.90), Color(0.62, 0.72, 0.90), Color(0.60, 0.71, 0.88),
		Color(0.48, 0.52, 0.80), Color(0.38, 0.48, 0.82),
	][phase]
	fill.light_energy = [0.22, 0.28, 0.30, 0.14, 0.035][phase] * lerpf(1.0, 2.4, dark)

	env.ambient_light_sky_contribution = lerpf(1.0, 0.35, dark) * (0.25 if night else 1.0)
	env.ambient_light_color = [
		Color(0.40, 0.34, 0.36), Color(0.62, 0.66, 0.72), Color(0.66, 0.70, 0.74),
		Color(0.54, 0.40, 0.33), Color(0.16, 0.21, 0.34),
	][phase]
	# в пасмурный день света не меньше, он просто ровный и без теней
	var amb: float = [0.90, 0.88, 0.95, 0.85, 0.75][phase]
	env.ambient_light_energy = amb * lerpf(1.0, 1.45, dark)
	# вечером и ночью глаз привыкает: поднимаем выдержку, иначе двор уходит
	# в чёрный лист и вся работа с небом пропадает зря
	env.tonemap_exposure = [0.92, 0.76, 0.72, 0.95, 1.35][phase] * lerpf(1.0, 1.25, dark)


## Туман: дальний по горизонту и низовой объёмный. Утром и в мороз — гуще.
func _apply_fog() -> void:
	var f: float = float(KINDS[kind]["fog"])
	if phase == 0:
		f = maxf(f, 0.55)          # рассветный туман в низине
	elif phase == 3:
		f = maxf(f, 0.2)
	if season == Season.WINTER and phase == 0:
		f = maxf(f, 0.7)           # морозная дымка стоит стеной

	var night := phase == 4
	var col := Color(0.70, 0.74, 0.78)
	if season == Season.WINTER:
		col = Color(0.74, 0.80, 0.88)
	elif season == Season.AUTUMN:
		col = Color(0.66, 0.64, 0.60)
	col = col.lerp(Color(0.09, 0.11, 0.18), 0.82 if night else 0.0)
	col = col.lerp(Color(0.40, 0.28, 0.22), 0.5 if phase == 3 else 0.0)

	env.fog_light_color = col
	# плотность растёт медленно: даже густой туман должен оставлять двор видимым,
	# иначе сарай пропадает в молоке уже с десяти шагов
	env.fog_density = lerpf(0.00015, 0.035, pow(f, 2.0))
	env.fog_sky_affect = lerpf(0.03, 0.7, pow(f, 2.0))
	env.fog_aerial_perspective = lerpf(0.10, 0.45, f)
	# низовой слой: молоко стелется по земле, выше человеческого роста чисто
	env.fog_height = lerpf(6.0, 4.0, f)
	env.fog_height_density = lerpf(0.0012, 0.018, f)
	if env.volumetric_fog_enabled:
		# объёмный туман считается вдоль взгляда и набирает плотность очень
		# быстро: выше сотых долей он превращает двор в молоко за десять шагов
		env.volumetric_fog_density = lerpf(0.0035, 0.006, f)
		env.volumetric_fog_albedo = col.lightened(0.25)


func _apply_ground() -> void:
	var snowy: bool = season == Season.WINTER or KINDS[kind]["drop"] == Drop.SNOW
	snow_pack = clampf(snow_pack, 0.0, 1.0)
	if snowy:
		snow_pack = maxf(snow_pack, 0.8 if season == Season.WINTER else 0.0)
	for s in _snow_fields:
		s.visible = snow_pack > 0.05
		# лежалый снег кроет землю почти насухо, свежий ещё просвечивает траву
		(s.material_override as StandardMaterial3D).albedo_color.a = clampf(snow_pack * 1.2, 0.0, 1.0)


# ------------------------------------------------------------------ небо

## Облачный слой: пять ярусов, каждый своего роста и плотности. Все пуховки
## сидят в одном MultiMesh, поэтому весь небосвод стоит один вызов отрисовки.
func _build_clouds() -> void:
	var clouds: Array = []       ## каждое облако — свой список пуховок
	var tiers := [
		# высота, радиус кольца, число облаков, пуховок в облаке, размер, рост
		[46.0, 120.0, 16, 22, 15.0, 0.55],   # кучевые: комковатые, с боками
		[86.0, 190.0, 12, 14, 26.0, 0.10],   # перистые: тонкая рваная вуаль
		[32.0, 110.0, 14, 20, 20.0, 0.16],   # слоистые: низкая плоская пелена
		[24.0, 95.0, 10, 24, 14.0, 0.75],    # кучево-дождевые: башни
		[60.0, 150.0, 9, 20, 18.0, 0.45],    # грозовые наковальни
	]
	for t in tiers:
		var y: float = t[0]
		var ring: float = t[1]
		var span: float = float(t[4])
		var tall: float = float(t[5])
		for c in int(t[2]):
			var a := _rng.randf() * TAU
			var r := ring * _rng.randf_range(0.25, 1.0)
			var at := Vector3(cos(a) * r, y + _rng.randf_range(-6.0, 6.0), sin(a) * r)
			var one: Array[Transform3D] = []
			# облако набирается из комков разного калибра, поэтому край рваный,
			# а середина плотная — один ровный диск так не выглядит никогда
			for p in int(t[3]):
				var k := _rng.randf()
				var s: float = span * lerpf(0.9, 0.3, k)
				var reach := lerpf(0.5, 1.5, k)
				var off := Vector3(
					_rng.randf_range(-1.0, 1.0),
					_rng.randf_range(-0.35, 0.85) * tall,
					_rng.randf_range(-1.0, 1.0) * 0.7) * span * reach
				var b := Basis.from_scale(Vector3(s, s * _rng.randf_range(0.55, 0.85), s))
				one.append(Transform3D(b, at + off))
			clouds.append(one)

	# облака перетасовываем целиком: при малой облачности мы показываем только
	# начало списка, и без перемешивания пропадали бы целые яруса неба
	_rng.seed = 90210
	for i in range(clouds.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Array = clouds[i]
		clouds[i] = clouds[j]
		clouds[j] = tmp
	var puffs: Array[Transform3D] = []
	for c2 in clouds:
		for tr in c2:
			puffs.append(tr)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = puffs.size()
	_cloud_home.resize(puffs.size())
	for i in puffs.size():
		mm.set_instance_transform(i, puffs[i])
		_cloud_home[i] = puffs[i].origin

	_cloud_mat = StandardMaterial3D.new()
	_cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_cloud_mat.billboard_keep_scale = true
	_cloud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloud_mat.disable_receive_shadows = true
	_cloud_mat.no_depth_test = false
	_cloud_mat.albedo_texture = _puff_tex()

	_clouds = MultiMeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.multimesh = mm
	_clouds.material_override = _cloud_mat
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_clouds)


## Пуховка облака: мягкое пятно с рваным краем, иначе получаются шарики.
func _puff_tex() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBAF)
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 4
	fn.frequency = 0.012
	fn.seed = 771
	for y in n:
		for x in n:
			var u := (float(x) / float(n - 1) - 0.5) * 2.0
			var v := (float(y) / float(n - 1) - 0.5) * 2.0
			var d := sqrt(u * u + v * v)
			# мягкое ядро с плавным сходом в ноль: резкий край выдаёт билборд
			var edge := clampf(1.0 - d, 0.0, 1.0)
			var core := edge * edge * (3.0 - 2.0 * edge)
			# шум не режет пятно на лепестки, а только шевелит его плотность
			var wob := fn.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a := core * lerpf(0.55, 1.0, wob) * 0.85
			# верх облака светлее низа — это и читается как объём
			var lift := 0.70 + 0.30 * clampf(-v * 0.5 + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(lift, lift, lift, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Ночная панорама: десять тысяч звёзд, млечный путь полосой и Полярная
## на севере. Рисуем один раз в картинку — это дешевле любых частиц.
func _night_sky() -> PanoramaSkyMaterial:
	if _sky_night != null:
		return _sky_night
	var w := 2048
	var h := 1024
	var img := Image.create(w, h, false, Image.FORMAT_RGBF)
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.frequency = 0.004
	fn.seed = 1917
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fine.frequency = 0.02
	fine.seed = 33

	# фон: к горизонту небо чуть светлее, вверху почти чёрное
	for y in h:
		var v := float(y) / float(h - 1)
		var horizon := pow(v, 2.2)
		var base := Color(0.012, 0.018, 0.042).lerp(Color(0.05, 0.07, 0.12), horizon)
		# млечный путь — наклонная полоса шума поперёк небосвода
		for x in w:
			var u := float(x) / float(w - 1)
			var band := absf((v - 0.42) - sin(u * TAU) * 0.10)
			var c := base
			if band < 0.14:
				var k := pow(1.0 - band / 0.14, 2.0)
				var n := fn.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var n2 := fine.get_noise_2d(float(x) * 2.0, float(y) * 2.0) * 0.5 + 0.5
				var glow := k * (0.35 + n * 0.8) * (0.5 + n2 * 0.7)
				c = c + Color(0.30, 0.33, 0.42) * glow * 0.55
			img.set_pixel(x, y, c)

	# сами звёзды: много мелких и горсть заметных
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 11000:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		# к млечному пути звёзды жмутся плотнее
		var v2 := float(y) / float(h - 1)
		if absf(v2 - 0.42) > 0.2 and rng.randf() < 0.45:
			continue
		var b := pow(rng.randf(), 3.0)
		var warm := rng.randf()
		var col := Color(0.75 + warm * 0.25, 0.80, 1.0 - warm * 0.3) * (0.25 + b * 1.6)
		img.set_pixel(x, y, img.get_pixel(x, y) + col)
		if b > 0.6:
			# у ярких звёзд размытый ореол, иначе они теряются в мипмапах
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px := clampi(x + d.x, 0, w - 1)
				var py := clampi(y + d.y, 0, h - 1)
				img.set_pixel(px, py, img.get_pixel(px, py) + col * 0.35)

	# Полярная звезда: на севере, высоко, заметно ярче прочих
	var nx := int(w * 0.5)
	var ny := int(h * 0.22)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var k := 1.0 - sqrt(float(dx * dx + dy * dy)) / 3.0
			if k <= 0.0:
				continue
			var px2 := clampi(nx + dx, 0, w - 1)
			var py2 := clampi(ny + dy, 0, h - 1)
			img.set_pixel(px2, py2, img.get_pixel(px2, py2) + Color(0.9, 0.95, 1.0) * k * 2.2)

	_sky_night = PanoramaSkyMaterial.new()
	_sky_night.panorama = ImageTexture.create_from_image(img)
	_sky_night.energy_multiplier = 1.0
	_build_twinkle()
	return _sky_night


## Рассвет и закат: рассеивание кладёт красное по горизонту, синее вверху.
func _warm_sky(dawn: bool) -> ProceduralSkyMaterial:
	var key := 0 if dawn else 1
	if _sky_warm.has(key):
		return _sky_warm[key]
	var m := ProceduralSkyMaterial.new()
	if dawn:
		m.sky_top_color = Color(0.13, 0.22, 0.46)
		m.sky_horizon_color = Color(0.95, 0.62, 0.42)
		m.ground_horizon_color = Color(0.42, 0.34, 0.30)
		m.ground_bottom_color = Color(0.12, 0.12, 0.13)
	else:
		m.sky_top_color = Color(0.10, 0.16, 0.40)
		m.sky_horizon_color = Color(1.0, 0.46, 0.20)
		m.ground_horizon_color = Color(0.40, 0.24, 0.18)
		m.ground_bottom_color = Color(0.10, 0.09, 0.09)
	m.sky_curve = 0.12
	m.sun_angle_max = 12.0
	m.sun_curve = 0.06
	_sky_warm[key] = m
	return m


func _grey_sky() -> ProceduralSkyMaterial:
	if _sky_grey == null:
		_sky_grey = ProceduralSkyMaterial.new()
		_sky_grey.sky_top_color = Color(0.26, 0.29, 0.34)
		_sky_grey.sky_horizon_color = Color(0.54, 0.56, 0.59)
		_sky_grey.ground_bottom_color = Color(0.24, 0.24, 0.23)
		_sky_grey.ground_horizon_color = Color(0.46, 0.46, 0.45)
		_sky_grey.sun_angle_max = 30.0
		_sky_grey.sun_curve = 0.6
	return _sky_grey


## Полсотни ярких звёзд отдельными точками — они мерцают, панорама не умеет.
func _build_twinkle() -> void:
	if _twinkle != null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	mm.mesh = quad
	mm.instance_count = 60
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var e := rng.randf_range(0.12, 1.3)
		var r := 180.0
		var at := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)) * r
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.7, 2.1)), at))
		mm.set_instance_color(i, Color(1, 1, 1, 1))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.albedo_texture = Mats.soft_dot()
	_twinkle = MultiMeshInstance3D.new()
	_twinkle.name = "Twinkle"
	_twinkle.multimesh = mm
	_twinkle.material_override = m
	_twinkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_twinkle.visible = false
	add_child(_twinkle)


## Луна с четырьмя фазами: диск с кратерами, тень нарастает с краю.
func _build_moon() -> void:
	for ph in 4:
		_moon_mats.append(_moon_mat(ph))
	_moon = MeshInstance3D.new()
	_moon.name = "Moon"
	var quad := QuadMesh.new()
	quad.size = Vector2(22.0, 22.0)
	_moon.mesh = quad
	_moon.material_override = _moon_mats[moon_phase]
	_moon.position = Vector3(-90.0, 78.0, -120.0)
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon.visible = false
	add_child(_moon)


func _moon_mat(ph: int) -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBAF)
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.frequency = 0.06
	fn.seed = 606 + ph
	for y in n:
		for x in n:
			var u := (float(x) / float(n - 1) - 0.5) * 2.0
			var v := (float(y) / float(n - 1) - 0.5) * 2.0
			var d := sqrt(u * u + v * v)
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var shade := 0.78 + fn.get_noise_2d(float(x), float(y)) * 0.22
			# моря на диске — тёмные пятна пониженной яркости
			if fn.get_noise_2d(float(x) * 0.5, float(y) * 0.5) > 0.25:
				shade *= 0.78
			var a := clampf((1.0 - d) * 6.0, 0.0, 1.0)
			# фаза: тень идёт серпом от края
			var lit := 1.0
			match ph:
				0: lit = 0.06
				1: lit = clampf((u + 0.35) * 2.2, 0.05, 1.0)
				2: lit = 1.0
				3: lit = clampf((-u + 0.35) * 2.2, 0.05, 1.0)
			var c := Color(shade, shade * 0.98, shade * 0.92) * lit
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	m.albedo_texture = ImageTexture.create_from_image(img)
	return m


func set_moon_phase(p: int) -> void:
	moon_phase = clampi(p, 0, 3)
	if _moon:
		_moon.material_override = _moon_mats[moon_phase]
	_apply_light()


# ------------------------------------------------------------------ осадки

const FAR := 26.0
const SHED_HX := 4.5
const SHED_HZ := 3.5

## Кольцо эмиттеров вокруг сарая: сквозь крышу осадки идти не должны.
func _build_precip() -> void:
	for f in _frames():
		var p := GPUParticles3D.new()
		p.amount = 500
		p.lifetime = 2.0
		p.preprocess = 2.0
		p.randomness = 0.3
		p.emitting = false
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		p.position = (f[0] as Vector3) + Vector3(0, 7.6, 0)
		p.visibility_aabb = AABB(Vector3(-FAR, -10, -FAR), Vector3(FAR * 2, 20, FAR * 2))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = (f[1] as Vector3) * 0.5
		pm.direction = Vector3(0, -1, 0)
		pm.spread = 3.0
		p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		p.draw_pass_1 = quad
		add_child(p)
		_precip.append(p)

	# снежное поле теми же вырезками — под крышей снега быть не должно
	# мелкий шаг текстуры: на крупном снег выходит белым листом без фактуры
	var snow_mat := Mats.make("concrete", Vector3(26, 26, 26), {
		"tint": Color(0.92, 0.95, 1.0), "normal": 1.4, "rough": 0.72, "triplanar": true,
	}).duplicate() as StandardMaterial3D
	snow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# вокруг сарая — вырезки, чтобы под крышей снега не было; дальше двора
	# снег идёт до горизонта, иначе за спиной виден зелёный луг в январе
	var fields := _frames() + [
		[Vector3(-(220.0 + FAR) * 0.5, 0, 0), Vector3(220.0 - FAR, 1, 440.0)],
		[Vector3((220.0 + FAR) * 0.5, 0, 0), Vector3(220.0 - FAR, 1, 440.0)],
		[Vector3(0, 0, -(220.0 + FAR) * 0.5), Vector3(FAR * 2.0, 1, 220.0 - FAR)],
		[Vector3(0, 0, (220.0 + FAR) * 0.5), Vector3(FAR * 2.0, 1, 220.0 - FAR)],
	]
	for f in fields:
		var size: Vector3 = f[1]
		var mi := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(size.x, size.z)
		mi.mesh = pl
		mi.material_override = snow_mat
		mi.position = (f[0] as Vector3) + Vector3(0, 0.014, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_snow_fields.append(mi)

	# осенние листья: летят по ветру через весь двор, кувыркаясь
	_leaves = GPUParticles3D.new()
	_leaves.name = "Leaves"
	_leaves.amount = 700
	_leaves.lifetime = 9.0
	_leaves.preprocess = 4.0
	_leaves.randomness = 0.6
	_leaves.emitting = false
	_leaves.position = Vector3(0, 5.0, 0)
	_leaves.visibility_aabb = AABB(Vector3(-30, -8, -30), Vector3(60, 20, 60))
	var lm := ParticleProcessMaterial.new()
	lm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	lm.emission_box_extents = Vector3(24, 5, 24)
	lm.direction = Vector3(1, -0.2, 0)
	lm.spread = 40.0
	lm.initial_velocity_min = 1.0
	lm.initial_velocity_max = 3.0
	lm.gravity = Vector3(1.0, -0.8, 0.4)
	lm.damping_min = 0.2
	lm.damping_max = 0.6
	lm.scale_min = 0.05
	lm.scale_max = 0.11
	lm.angle_min = -180.0
	lm.angle_max = 180.0
	lm.angular_velocity_min = -220.0
	lm.angular_velocity_max = 220.0
	lm.turbulence_enabled = true
	lm.turbulence_noise_strength = 2.6
	lm.turbulence_noise_scale = 1.4
	var lramp := Gradient.new()
	lramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	lramp.colors = PackedColorArray([
		Color(0.78, 0.45, 0.12), Color(0.85, 0.62, 0.16), Color(0.62, 0.24, 0.10)])
	var lgt := GradientTexture1D.new()
	lgt.gradient = lramp
	lm.color_ramp = lgt
	_leaves.process_material = lm
	var lq := QuadMesh.new()
	lq.size = Vector2(1.0, 0.6)
	_leaves.draw_pass_1 = lq
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.vertex_color_use_as_albedo = true
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lmat.albedo_texture = Mats.soft_dot()
	lmat.roughness = 0.9
	_leaves.material_override = lmat
	add_child(_leaves)

	# брызги от капель по двору
	_splash = GPUParticles3D.new()
	_splash.name = "Splash"
	_splash.amount = 160
	_splash.lifetime = 0.34
	_splash.emitting = false
	_splash.position = Vector3(0, 0.02, 3.0)
	_splash.visibility_aabb = AABB(Vector3(-14, -1, -14), Vector3(28, 3, 28))
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(12, 0.02, 10)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 34.0
	sm.initial_velocity_min = 0.6
	sm.initial_velocity_max = 1.7
	sm.gravity = Vector3(0, -9.0, 0)
	sm.scale_min = 0.006
	sm.scale_max = 0.018
	_splash.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE
	_splash.draw_pass_1 = sq
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.billboard_keep_scale = true
	smat.albedo_color = Color(0.82, 0.88, 0.95, 0.22)
	smat.albedo_texture = Mats.soft_dot()
	smat.disable_receive_shadows = true
	_splash.material_override = smat
	add_child(_splash)


func _frames() -> Array:
	return [
		[Vector3(-(FAR + SHED_HX) * 0.5, 0, 0), Vector3(FAR - SHED_HX, 1, FAR * 2.0)],
		[Vector3((FAR + SHED_HX) * 0.5, 0, 0), Vector3(FAR - SHED_HX, 1, FAR * 2.0)],
		[Vector3(0, 0, -(FAR + SHED_HZ) * 0.5), Vector3(SHED_HX * 2.0, 1, FAR - SHED_HZ)],
		[Vector3(0, 0, (FAR + SHED_HZ) * 0.5), Vector3(SHED_HX * 2.0, 1, FAR - SHED_HZ)],
	]


## Осадки настраиваются одним куском: тип, сила и ветер задают всё остальное.
func _apply_precip() -> void:
	var drop: int = KINDS[kind]["drop"]
	var power: float = float(KINDS[kind]["power"])
	var w := wind_vec() * 14.0
	var budget: float = [1.0, 0.65, 0.35][_quality]

	for p in _precip:
		p.emitting = drop != Drop.NONE and power > 0.01
		if not p.emitting:
			continue
		var pm := p.process_material as ParticleProcessMaterial
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		m.albedo_texture = Mats.soft_dot()
		var quad := p.draw_pass_1 as QuadMesh
		pm.turbulence_enabled = false

		match drop:
			Drop.RAIN:
				var fast := kind == Kind.DOWNPOUR or kind == Kind.STORM
				# капель много и они тонкие: струя дождя — это волосок, а не
				# белая колбаса, поэтому размер задаём прямо в метрах
				p.amount = roundi(lerpf(900.0, 3000.0, power) * budget)
				p.lifetime = 1.2
				pm.initial_velocity_min = lerpf(7.0, 16.0, power)
				pm.initial_velocity_max = lerpf(10.0, 21.0, power)
				pm.gravity = Vector3(w.x, -lerpf(8.0, 18.0, power), w.z)
				pm.scale_min = 0.75
				pm.scale_max = 1.25
				quad.size = Vector2(lerpf(0.006, 0.012, power), lerpf(0.10, 0.60, power))
				m.albedo_color = Color(0.72, 0.80, 0.90, lerpf(0.28, 0.46, power))
				if kind == Kind.SLEET:
					# ледяной дождь: капля короче и заметно белее
					m.albedo_color = Color(0.86, 0.92, 1.0, 0.6)
					quad.size = Vector2(0.014, 0.2)
				if fast:
					pm.turbulence_enabled = true
					pm.turbulence_noise_strength = 0.6
					pm.turbulence_noise_scale = 0.8
			Drop.SNOW:
				p.amount = roundi(lerpf(900.0, 3600.0, power) * budget)
				p.lifetime = lerpf(9.0, 4.0, power)
				pm.initial_velocity_min = lerpf(0.4, 2.0, power)
				pm.initial_velocity_max = lerpf(1.2, 4.0, power)
				# в метель снег летит почти горизонтально
				pm.gravity = Vector3(w.x * 1.8, -lerpf(0.9, 2.4, power), w.z * 1.8)
				pm.scale_min = lerpf(0.5, 0.7, power)
				pm.scale_max = lerpf(1.2, 1.8, power)
				pm.turbulence_enabled = true
				pm.turbulence_noise_strength = lerpf(1.2, 3.6, power)
				pm.turbulence_noise_scale = 1.1
				# хлопья: от пушинки в два сантиметра до мокрого хлопка в пять
				quad.size = Vector2.ONE * lerpf(0.022, 0.045, power)
				m.albedo_color = Color(1, 1, 1, lerpf(0.8, 1.0, power))
			Drop.HAIL:
				p.amount = roundi(3600.0 * power * budget)
				p.lifetime = 1.0
				pm.initial_velocity_min = 14.0
				pm.initial_velocity_max = 19.0
				pm.gravity = Vector3(w.x * 0.6, -22.0, w.z * 0.6)
				pm.scale_min = 0.6
				pm.scale_max = 1.5
				# от горошины до грецкого ореха: четыре сантиметра плотного льда
				quad.size = Vector2.ONE * 0.06
				m.albedo_color = Color(0.9, 0.95, 1.0, 1.0)
		p.material_override = m

	if _splash:
		# град скачет по земле не хуже дождя, только отскок выше и белее
		_splash.emitting = (drop == Drop.RAIN or drop == Drop.HAIL) and power > 0.3
		_splash.amount = maxi(1, roundi(200.0 * power * budget))
		var sm2 := _splash.process_material as ParticleProcessMaterial
		var ice := drop == Drop.HAIL
		sm2.initial_velocity_min = 1.4 if ice else 0.6
		sm2.initial_velocity_max = 3.2 if ice else 1.7
		(_splash.material_override as StandardMaterial3D).albedo_color = (
			Color(0.92, 0.96, 1.0, 0.45) if ice else Color(0.82, 0.88, 0.95, 0.22))
	if _leaves:
		# листопад тем гуще, чем сильнее дует: в штиль лист висит на ветке
		_leaves.emitting = season == Season.AUTUMN
		_leaves.amount = maxi(1, roundi(lerpf(120.0, 900.0, clampf(beaufort / 9.0, 0.0, 1.0)) * budget))
		var lm2 := _leaves.process_material as ParticleProcessMaterial
		var wv := wind_vec() * 9.0
		lm2.gravity = Vector3(wv.x, -0.8, wv.z)


# ------------------------------------------------------------------ лужи

## Лужи наливаются от дождя и отражают небо. Мелкие — просто мокрые пятна.
func _build_puddles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8712
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.08, 0.10, 0.0)
	mat.roughness = 0.04
	mat.metallic = 0.5
	mat.metallic_specular = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = Mats.soft_dot()
	for i in 14:
		var mi := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		var s := rng.randf_range(0.8, 2.6)
		pl.size = Vector2(s, s * rng.randf_range(0.6, 1.3))
		mi.mesh = pl
		mi.material_override = mat
		var a := rng.randf() * TAU
		var r := rng.randf_range(5.0, 13.0)
		mi.position = Vector3(cos(a) * r, 0.013, sin(a) * r)
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_puddles.append(mi)


# ------------------------------------------------------------------ радуга

## Радуга двойная: главная дуга и над ней слабая с обратным порядком цветов.
func _build_rainbow() -> void:
	var w := 512
	var h := 256
	var img := Image.create(w, h, true, Image.FORMAT_RGBAF)
	# цвета берём приглушённые: радуга — это плёнка света, а не малярная лента
	var bands := [
		Color(0.42, 0.20, 0.62), Color(0.28, 0.24, 0.72), Color(0.28, 0.54, 0.82),
		Color(0.40, 0.74, 0.44), Color(0.92, 0.88, 0.42), Color(0.94, 0.62, 0.30),
		Color(0.88, 0.36, 0.30),
	]
	for y in h:
		for x in w:
			var u := (float(x) / float(w - 1) - 0.5) * 2.0
			var v := 1.0 - float(y) / float(h - 1)
			var d := sqrt(u * u + v * v)
			var c := Color(0, 0, 0, 0)
			# главная дуга: полосы перетекают друг в друга без ступенек
			var t := (d - 0.72) / 0.15
			if t >= 0.0 and t <= 1.0:
				var fi := t * float(bands.size() - 1)
				var i0 := clampi(int(fi), 0, bands.size() - 1)
				var i1 := clampi(i0 + 1, 0, bands.size() - 1)
				var band: Color = (bands[i0] as Color).lerp(bands[i1], fi - float(i0))
				var soft := pow(sin(t * PI), 1.4)
				c = Color(band.r, band.g, band.b, soft * 0.55)
			# побочная, бледнее и цвета наоборот
			var t2 := (d - 0.91) / 0.12
			if t2 >= 0.0 and t2 <= 1.0:
				var fj := (1.0 - t2) * float(bands.size() - 1)
				var j0 := clampi(int(fj), 0, bands.size() - 1)
				var j1 := clampi(j0 + 1, 0, bands.size() - 1)
				var band2: Color = (bands[j0] as Color).lerp(bands[j1], fj - float(j0))
				var soft2 := pow(sin(t2 * PI), 1.4) * 0.19
				if soft2 > c.a:
					c = Color(band2.r, band2.g, band2.b, soft2)
			# у земли дуга тает в дымке, в небе так и бывает
			if v < 0.18:
				c.a *= clampf(v / 0.18, 0.0, 1.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# не сложение, а обычное смешение: на светлом небе аддитивная радуга
	# просто исчезает, а настоящая видна именно как цветная плёнка
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color(1, 1, 1, 0)

	_rainbow = MeshInstance3D.new()
	_rainbow.name = "Rainbow"
	var quad := QuadMesh.new()
	quad.size = Vector2(150.0, 75.0)
	_rainbow.mesh = quad
	_rainbow.material_override = m
	_rainbow.position = Vector3(30.0, 14.0, -95.0)
	_rainbow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rainbow.visible = false
	add_child(_rainbow)


# ------------------------------------------------------------------ молния

func _build_bolt() -> void:
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.vertex_color_use_as_albedo = true
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.disable_receive_shadows = true

	_bolt = MeshInstance3D.new()
	_bolt.name = "Bolt"
	_bolt.mesh = ImmediateMesh.new()
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)

	# вспышка: короткий резкий свет сверху, от него тени прыгают
	_flash = DirectionalLight3D.new()
	_flash.name = "Flash"
	_flash.light_color = Color(0.86, 0.92, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = true
	_flash.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_flash.directional_shadow_max_distance = 40.0
	_flash.rotation_degrees = Vector3(-70, 30, 0)
	_flash.visible = false
	add_child(_flash)


## Ударить молнией. Три вида: в землю, разветвлённая и внутриоблачная.
func _strike(close: bool = false) -> void:
	var a := _rng.randf() * TAU
	if close:
		# по заказу бьём туда, куда смотрит игрок: разряд за спиной не считается
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera:
			var look := -camera.global_transform.basis.z
			if absf(look.x) + absf(look.z) > 0.01:
				a = atan2(look.z, look.x) + _rng.randf_range(-0.28, 0.28)
	var far := _rng.randf_range(80.0, 130.0) if close else _rng.randf_range(18.0, 150.0)
	var ground := close or _rng.randf() < 0.55
	var top := Vector3(cos(a) * far, _rng.randf_range(45.0, 70.0), sin(a) * far)
	var bottom := Vector3(top.x, 0.0, top.z) if ground else top + Vector3(_rng.randf_range(-40, 40), -8.0, _rng.randf_range(-40, 40))

	# бьёт ли в трубу: редко, но метко — рядом с сараем и точно в землю
	var hit_pipe := ground and far < 24.0 and _rng.randf() < 0.25
	if hit_pipe:
		bottom = Vector3(0, 0, 0)
		top = Vector3(_rng.randf_range(-6, 6), 60.0, _rng.randf_range(-6, 6))

	var im := _bolt.mesh as ImmediateMesh
	im.clear_surfaces()
	# толщина ленты растёт с расстоянием: иначе далёкий разряд выходит в
	# полпикселя и пропадает, а близкий заливает полкадра
	var wide := 0.2 + bottom.distance_to(Vector3.ZERO) * 0.007
	# колен много и они широкие: ровный светящийся столб на молнию не похож
	_ribbon(im, top, bottom, 26, 5.5, wide)
	# ветки от главного ствола
	var branches := _rng.randi_range(3, 6)
	for i in branches:
		var k := _rng.randf_range(0.15, 0.8)
		var from := top.lerp(bottom, k)
		var to := from + Vector3(
			_rng.randf_range(-16, 16), -_rng.randf_range(8, 22), _rng.randf_range(-16, 16))
		_ribbon(im, from, to, 10, 3.0, wide * 0.55)

	_bolt.visible = true
	_flash.visible = true
	_flash_k = 1.0
	lightning_at = bottom

	var dist := bottom.length()
	# гром догоняет через треть секунды на сотню метров
	_thunder.append([dist / 330.0 + 0.05, clampf(1.0 - dist / 200.0, 0.12, 1.0), bottom])
	struck.emit(bottom, dist, hit_pipe)


## Молния — не линия в пиксель, а лента: две полосы крест-накрест, чтобы
## разряд было видно с любой стороны, а не только сбоку.
func _ribbon(im: ImmediateMesh, from: Vector3, to: Vector3, steps: int,
		jitter: float, width: float) -> void:
	var pts: Array[Vector3] = []
	for i in steps + 1:
		var k := float(i) / float(steps)
		var p := from.lerp(to, k)
		if i > 0 and i < steps:
			# излом тем шире, чем дальше от концов: у земли и в туче разряд
			# приколот на месте, а в середине его мотает
			var sway := jitter * sin(k * PI)
			p += Vector3(
				_rng.randf_range(-sway, sway), _rng.randf_range(-sway, sway) * 0.25,
				_rng.randf_range(-sway, sway))
		pts.append(p)

	for axis in [Vector3.RIGHT, Vector3.FORWARD]:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in pts.size():
			var k := float(i) / float(pts.size() - 1)
			# к земле разряд сужается и гаснет
			var w := width * (1.0 - k * 0.55)
			var glow := 1.0 - k * 0.3
			im.surface_set_color(Color(1.0, 0.98, 0.92, glow))
			im.surface_add_vertex(pts[i] - axis * w)
			im.surface_set_color(Color(0.72, 0.82, 1.0, glow * 0.8))
			im.surface_add_vertex(pts[i] + axis * w)
		im.surface_end()


# ------------------------------------------------------------------ жизнь

func _process(delta: float) -> void:
	_t += delta
	_wind(delta)
	_drift(delta)
	_storm(delta)
	_water(delta)
	if phase == 4:
		_stars(delta)


## Ветер гуляет вокруг своей погоды: порывы, шквалы и смена направления.
func _wind(delta: float) -> void:
	var base: float = float(KINDS[kind]["beaufort"])
	var n := _noise.get_noise_1d(_t * 0.22)
	var fast := _noise.get_noise_1d(_t * 1.7 + 100.0)
	# шквал добавляет до трёх баллов поверх ровного ветра
	var want := clampf(base + n * 1.6 + maxf(fast, 0.0) * base * 0.35, 0.0, 12.0)
	var was := beaufort
	beaufort = lerpf(beaufort, want, 1.0 - exp(-delta * 1.4))
	wind_dir += delta * _noise.get_noise_1d(_t * 0.09 + 50.0) * 0.25

	_gust_t -= delta
	if beaufort - was > 0.06 and beaufort > 5.0 and _gust_t <= 0.0:
		_gust_t = _rng.randf_range(2.5, 6.0)
		gust.emit(beaufort)


## Облака едут по ветру и заворачиваются обратно, чтобы небо не кончалось.
func _drift(delta: float) -> void:
	if _clouds == null or not _clouds.visible:
		return
	_cloud_drift += wind_vec() * delta * 2.6
	var span := 240.0
	if absf(_cloud_drift.x) > span:
		_cloud_drift.x -= sign(_cloud_drift.x) * span * 2.0
	if absf(_cloud_drift.z) > span:
		_cloud_drift.z -= sign(_cloud_drift.z) * span * 2.0
	_clouds.position = _cloud_drift


## Гроза: молнии с паузами, гром с задержкой по расстоянию, затухание вспышки.
func _storm(delta: float) -> void:
	if _flash_k > 0.0:
		# вспышка живёт мгновение и успевает мигнуть дважды
		_flash_k = maxf(0.0, _flash_k - delta * 5.5)
		var flick := 1.0 if fmod(_flash_k, 0.25) > 0.1 else 0.25
		_flash.light_energy = _flash_k * 7.0 * flick
		_bolt_mat.albedo_color = Color(1, 1, 1, clampf(_flash_k * 1.6, 0.0, 1.0))
		if _flash_k <= 0.0:
			_bolt.visible = false
			_flash.visible = false

	for i in range(_thunder.size() - 1, -1, -1):
		var row: Array = _thunder[i]
		row[0] -= delta
		if row[0] <= 0.0:
			_thunder.remove_at(i)
			thunder.emit(float(row[1]), row[2] as Vector3)

	if kind != Kind.STORM:
		return
	_strike_cd -= delta
	if _strike_cd <= 0.0:
		_strike_cd = _rng.randf_range(2.5, 9.0)
		_strike()


## Ударить прямо сейчас — для проверки и для «молния в трубу» по сюжету.
## Здесь всегда разряд в землю неподалёку: именно его и хочется увидеть.
func strike_now() -> void:
	_strike(true)


## Дождь наливает лужи, солнце их сушит; после дождя с солнцем — радуга.
func _water(delta: float) -> void:
	var drop: int = KINDS[kind]["drop"]
	var power: float = float(KINDS[kind]["power"])
	if drop == Drop.RAIN:
		wet = clampf(wet + delta * power * 0.09, 0.0, 1.0)
	elif drop == Drop.SNOW:
		snow_pack = clampf(snow_pack + delta * power * 0.05, 0.0, 1.0)
		wet = maxf(0.0, wet - delta * 0.02)
	else:
		var dry := 0.02 + (0.05 if phase == 2 and float(KINDS[kind]["cloud"]) < 0.4 else 0.0)
		wet = maxf(0.0, wet - delta * dry)
		if season != Season.WINTER:
			snow_pack = maxf(0.0, snow_pack - delta * 0.03)

	for p in _puddles:
		p.visible = wet > 0.08
		if p.visible:
			var m := p.material_override as StandardMaterial3D
			m.albedo_color.a = clampf(wet * 0.9, 0.0, 0.85)
	_apply_ground()

	# радуга: солнце в спину и вода в воздухе
	var want := 0.0
	if kind == Kind.SUNSHOWER:
		want = 1.0
	elif wet > 0.25 and drop == Drop.NONE and float(KINDS[kind]["cloud"]) < 0.5 and phase != 4:
		want = clampf((wet - 0.25) * 2.4, 0.0, 1.0)
	_rainbow_k = lerpf(_rainbow_k, want, 1.0 - exp(-delta * 0.7))
	if _rainbow:
		_rainbow.visible = _rainbow_k > 0.02
		(_rainbow.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, _rainbow_k)
		if _rainbow.visible:
			# радуга всегда напротив солнца: центр дуги — под горизонтом,
			# в точке, куда уходит солнечный луч
			var l := -sun.global_transform.basis.z
			var away := Vector3(l.x, 0.0, l.z)
			if away.length() > 0.01:
				_rainbow.position = away.normalized() * 110.0 + Vector3(0, 6.0, 0)
		if _rainbow_k > 0.5 and not _rainbow_seen:
			_rainbow_seen = true
			rainbow_out.emit()


## Мерцание звёзд: шестьдесят точек хватает, чтобы небо перестало быть мёртвым.
func _stars(delta: float) -> void:
	_twinkle_t += delta
	if _twinkle == null or not _twinkle.visible or _twinkle_t < 0.05:
		return
	_twinkle_t = 0.0
	var mm := _twinkle.multimesh
	for i in mm.instance_count:
		var k := 0.55 + 0.45 * sin(_t * (1.1 + float(i % 7) * 0.31) + float(i))
		mm.set_instance_color(i, Color(0.85, 0.92, 1.0, k))


