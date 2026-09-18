class_name PechWorld
extends Node3D

## Окружение и сарай. Всё строится кодом: небо, солнце, тени, доски со щелями,
## через которые в объёмном тумане пробиваются лучи.

const SHED_HX := 4.5        # половина ширины сарая по X
const SHED_HZ := 3.5        # половина глубины по Z
const WALL_H := 3.4
const RIDGE_Y := 5.0
const EAVE_Y := 3.35
const BASE_Y := 0.18        # верх бетонного фундамента — на нём растёт печка

# где в сарае лежат запасы топлива
const HAY_STOCK := Vector3(-2.55, 0.0, 1.45)
const CHIP_STOCK := Vector3(2.25, 0.0, 1.35)
const COAL_STOCK := Vector3(-1.5, 0.0, 2.55)   # уголь чёрный, в тёмном углу его не видно

enum Weather { CLEAR, RAIN, SNOW }

const WEATHER_NAMES := ["ясно", "дождь", "снег"]
const QUALITY_NAMES := ["максимум", "высокое", "среднее", "низкое"]
const OUTSIDE_TEMP := [17.0, 8.0, -18.0]   # что на улице при каждой погоде

var props: Array[RigidBody3D] = []   # утварь сарая: её можно толкать и разбрасывать
var barrel: RigidBody3D              # из неё черпают воду
var lamp: OmniLight3D                # подсвет под коньком
var thermo: Label3D                  # термометр на стене
var sky: PechWeather                 # всё небо и погода живут там
var weather := 0
var wind := 0.3                      # 0..1, качает тягу в трубе
var quality := 1                     # пресет картинки, QUALITY_NAMES

var _phase := 2                      # день, индекс в PechWeather.PHASE_NAMES
var _sky_clear: Material
var _grass_mat: StandardMaterial3D   # трава перекрашивается по сезону
var _hill_mat: StandardMaterial3D
var _meshes: Dictionary = {}         # общие меши по размеру, чтобы движок их группировал
var _wall_xf: Array[Transform3D] = []   # доски обшивки до сборки в один меш
var _wall_col: Array[Color] = []
var _wind_noise: FastNoiseLite
var _wind_t := 0.0
var sun: DirectionalLight3D
var env: Environment
var _statics: Node3D
var _roof_boards: Array[MeshInstance3D] = []
var _roof_fixed: Array[Transform3D] = []
var _roof_broken: Array[Transform3D] = []
var _roof_tween: Tween
var _calm: Dictionary = {}
var _haze_vol: FogVolume = null
var fill: DirectionalLight3D
var _day_fog := Color(0.62, 0.66, 0.70)


func _ready() -> void:
	_wind_noise = FastNoiseLite.new()
	_wind_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_wind_noise.seed = 9091
	_statics = Node3D.new()
	_statics.name = "Static"
	add_child(_statics)
	_build_env()
	_build_sun()
	_day_fog = env.fog_light_color
	_build_terrain()
	_build_shed()
	_build_clutter()
	_build_thermo()

	sky = PechWeather.new()
	sky.name = "Weather"
	add_child(sky)
	sky.setup(env, sun, fill, _sky_clear)
	set_quality(quality)
	set_time_of_day(_phase)   # заодно зажигает лампу под коньком


# ---------------------------------------------------------------- окружение

func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var hdr := Mats.tex("res://assets/sky.hdr")
	if hdr:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdr
		pano.energy_multiplier = 1.0
		sky.sky_material = pano
	else:
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.24, 0.42, 0.72)
		proc.sky_horizon_color = Color(0.72, 0.74, 0.70)
		proc.ground_bottom_color = Color(0.18, 0.16, 0.13)
		proc.ground_horizon_color = Color(0.55, 0.50, 0.42)
		proc.sun_angle_max = 6.0
		proc.sun_curve = 0.08
		sky.sky_material = proc
	_sky_clear = sky.sky_material
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72
	env.tonemap_white = 4.0

	env.ssao_enabled = true
	env.ssao_radius = 0.55
	env.ssao_intensity = 3.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.7
	env.ssao_light_affect = 0.25
	env.ssao_ao_channel_affect = 0.3

	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 1.1
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0

	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.15
	env.sdfgi_min_cell_size = 0.09
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.5
	env.glow_hdr_scale = 2.0
	env.set("glow_levels/2", 0.4)
	env.set("glow_levels/3", 0.8)
	env.set("glow_levels/4", 1.0)
	env.set("glow_levels/5", 0.7)
	env.set("glow_levels/6", 0.35)

	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.71, 0.74)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.14
	env.fog_density = 0.0004
	env.fog_aerial_perspective = 0.18
	env.fog_sky_affect = 0.05
	env.fog_height = 6.0
	env.fog_height_density = 0.006

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color(0.90, 0.88, 0.84)
	env.volumetric_fog_emission = Color(0, 0, 0)
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_gi_inject = 0.5
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 42.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.08

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 1.12
	env.adjustment_brightness = 1.0

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env

	var cam_attr := CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 16.0
	cam_attr.dof_blur_far_transition = 10.0
	cam_attr.dof_blur_amount = 0.05
	cam_attr.auto_exposure_enabled = false
	we.camera_attributes = cam_attr

	add_child(we)


func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.9
	sun.light_specular = 0.6
	sun.light_angular_distance = 0.55
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.14
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.9
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.1
	sun.rotation_degrees = Vector3(-27.0, 152.0, 0.0)
	add_child(sun)

	# слабый холодный контровой свет с неба, чтобы тени не были чёрными
	fill = DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.light_color = Color(0.60, 0.71, 0.88)
	fill.light_energy = 0.3
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-58.0, -40.0, 0.0)
	add_child(fill)


## Время суток. Днём огонь в печке теряется на солнце, а вечером и ночью он
## наконец начинает работать как свет: отсветы на досках, тени от стропил.
## Небо и свет считает погода, сараю остаётся только своя лампа.
func set_time_of_day(phase: int) -> void:
	_phase = phase
	if sky:
		sky.set_phase(phase)
	_lamp_for_phase(phase)


# ---------------------------------------------------------------- качество

## Четыре пресета. Замеры на GeForce RTX 2070 Super, 1920×1080, гроза с
## топящейся печкой — самый тяжёлый кадр в игре:
##   максимум 31 · высокое 60 · среднее 60 · низкое 60 (до правок было 36)
## Максимум честно назван максимумом: SDFGI пересчитывает переотражения на
## каждый шевелящийся огонёк и стоит вдвое дороже всего остального вместе.
## Играют на «высоком», а «максимум» — для скриншотов и мощных машин.
func next_quality() -> void:
	set_quality((quality + 1) % QUALITY_NAMES.size())


func quality_name() -> String:
	return QUALITY_NAMES[quality]


func set_quality(q: int) -> void:
	quality = clampi(q, 0, QUALITY_NAMES.size() - 1)
	match quality:
		0:   # максимум: всё включено, кадры не жалеем
			env.ssil_enabled = true
			env.ssao_enabled = true
			env.sdfgi_enabled = true
			env.sdfgi_cascades = 4
			env.volumetric_fog_enabled = true
			env.volumetric_fog_length = 48.0
			env.glow_enabled = true
			sun.directional_shadow_max_distance = 55.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		1:   # высокое: без переотражений, но с мягкими тенями и лучами в тумане
			env.ssil_enabled = false
			env.ssao_enabled = true
			env.sdfgi_enabled = false
			env.sdfgi_cascades = 2
			env.volumetric_fog_enabled = true
			env.volumetric_fog_length = 28.0
			env.glow_enabled = true
			sun.directional_shadow_max_distance = 42.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		2:   # среднее: туман короче, тени проще
			env.ssil_enabled = false
			env.ssao_enabled = true
			env.sdfgi_enabled = false
			env.sdfgi_cascades = 2
			env.volumetric_fog_enabled = true
			env.volumetric_fog_length = 22.0
			env.glow_enabled = true
			sun.directional_shadow_max_distance = 34.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:   # низкое: только прямой свет и тени
			env.ssil_enabled = false
			env.ssao_enabled = false
			env.sdfgi_enabled = false
			env.volumetric_fog_enabled = false
			env.glow_enabled = true
			env.volumetric_fog_length = 16.0
			sun.directional_shadow_max_distance = 26.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	if sky:
		sky.set_quality(fx_level())


## Погода и огонь знают три ступени, а пресетов четыре: максимум и высокое
## делят между собой верхнюю.
func fx_level() -> int:
	return [0, 1, 1, 2][quality]


# ---------------------------------------------------------------- погода

## Погода целиком живёт в PechWeather, снаружи остаются только эти ручки.
func set_weather(w: int) -> void:
	if sky == null:
		return
	sky.set_kind(w)
	weather = sky.kind
	set_time_of_day(_phase)


func set_season(s: int) -> void:
	if sky == null:
		return
	sky.set_season(s)
	weather = sky.kind
	_season_look()
	set_time_of_day(_phase)


func weather_name() -> String:
	return sky.kind_name() if sky else "ясно"


func outside_temp() -> float:
	return sky.outside_temp() if sky else 17.0


## Сезон перекрашивает траву и холмы: осенью рыжие, зимой седые.
func _season_look() -> void:
	if _grass_mat == null:
		return
	var tint: Color = PechWeather.SEASON_GRASS[sky.season]
	_grass_mat.albedo_color = tint
	if _hill_mat:
		# зимой холмы стоят в том же снегу, что и двор: зелёные бугры на белом
		# поле выдают подделку сразу, поэтому холмы выбеливаем целиком
		_hill_mat.albedo_color = (Color(1.45, 1.55, 1.7)
			if sky.season == PechWeather.Season.WINTER else tint.darkened(0.12))


## Лампа под коньком. Сарай внутри глухой, и от первого лица без этого
## подсвета в нём просто ничего не разглядеть.
func _lamp_for_phase(phase: int) -> void:
	if lamp == null:
		lamp = OmniLight3D.new()
		lamp.name = "ShedFill"
		lamp.position = Vector3(0, 2.75, 0.2)
		lamp.omni_range = 11.0
		lamp.omni_attenuation = 0.8
		lamp.shadow_enabled = false
		lamp.light_specular = 0.15
		add_child(lamp)
	match phase:
		1:
			lamp.light_color = Color(1.0, 0.82, 0.62)
			lamp.light_energy = 0.5
		2:
			lamp.light_color = Color(0.68, 0.76, 1.0)
			lamp.light_energy = 0.16
		_:
			lamp.light_color = Color(0.86, 0.90, 1.0)
			# в непогоду на дворе темнее, и лампе приходится стараться сильнее
			var dim: float = float(PechWeather.KINDS[sky.kind]["dark"]) if sky else 0.0
			lamp.light_energy = lerpf(0.95, 1.3, dim)


## Термометр на стене: единственная цифра, за которой тут вообще следят.
func set_thermo(room: float) -> void:
	if thermo == null:
		return
	thermo.text = "%+d" % roundi(room)
	thermo.modulate = Color(0.6, 0.78, 1.0) if room < 8.0 else (
		Color(0.95, 0.9, 0.8) if room < 20.0 else Color(0.6, 0.95, 0.55))


func _build_thermo() -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.34, 0.03)
	board.mesh = bm
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.86, 0.84, 0.78)
	paint.roughness = 0.6
	board.material_override = paint
	board.position = Vector3(1.75, 1.62, -SHED_HZ + 0.09)
	_statics.add_child(board)

	thermo = Label3D.new()
	thermo.text = "+17"
	thermo.font_size = 96
	thermo.pixel_size = 0.0022
	thermo.outline_size = 14
	thermo.outline_modulate = Color(0, 0, 0, 0.85)
	thermo.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	thermo.no_depth_test = false
	thermo.position = board.position + Vector3(0, 0.0, 0.021)
	_statics.add_child(thermo)


## Ветер берём у погоды: тяга в трубе меряется этой же цифрой.
func _process(_delta: float) -> void:
	if sky:
		wind = sky.wind01()


# ---------------------------------------------------------------- земля

func _build_terrain() -> void:
	# трава до горизонта
	_grass_mat = Mats.grass().duplicate() as StandardMaterial3D
	var grass := _plane(Vector2(240, 240), Vector3(0, -0.02, 0), _grass_mat, 12)
	grass.name = "Grass"
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# мягкие холмы по краям, чтобы горизонт не был плоским как стол
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	_hill_mat = Mats.grass(Vector3(0.14, 0.14, 0.14)).duplicate() as StandardMaterial3D
	var hill_mat := _hill_mat
	# все холмы — один шар, растянутый по-разному: движку хватает одной пачки
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 1.0
	hill_mesh.height = 1.0
	hill_mesh.radial_segments = 20
	hill_mesh.rings = 8
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(34.0, 105.0)
		var s := rng.randf_range(10.0, 34.0)
		var h := s * rng.randf_range(0.30, 0.62)
		var mi := MeshInstance3D.new()
		mi.mesh = hill_mesh
		mi.material_override = hill_mat
		mi.scale = Vector3(s, h, s)
		mi.position = Vector3(cos(a) * r, -h * 0.5 + rng.randf_range(-1.0, 0.6), sin(a) * r)
		# за горизонт тени всё равно не достают, а в проход они лезут
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_statics.add_child(mi)

	_build_yard()

	# коллизия земли
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 4.0, 300)
	shape.shape = box
	shape.position = Vector3(0, -2.0, 0)
	body.add_child(shape)
	body.physics_material_override = _pmat(0.9, 0.0)
	add_child(body)

	# бетонный фундамент — площадка под печку
	var slab := Mats.make("concrete", Vector3(0.8, 0.8, 0.8), {
		"tint": Color(0.62, 0.60, 0.57), "normal": 1.3, "rough": 0.95, "triplanar": true,
	})
	_box(Vector3(3.6, BASE_Y, 2.8), Vector3(0, BASE_Y * 0.5, 0), slab, Vector3.ZERO, true, 0.92)
	# бортик фундамента
	var edge := Mats.make("concrete", Vector3(1.1, 1.1, 1.1), {
		"tint": Color(0.50, 0.48, 0.45), "normal": 1.2, "rough": 1.0, "triplanar": true,
	})
	_box(Vector3(3.72, 0.05, 2.92), Vector3(0, 0.025, 0), edge, Vector3.ZERO, false)


## Утоптанный двор вокруг сарая. Ровный прямоугольник земли на траве виден
## за километр, поэтому край размываем прозрачностью и ведём его по шуму —
## так земля переходит в траву проплешинами, как её и вытаптывают.
func _build_yard() -> void:
	var hx := 17.0
	var hz := 15.0
	var nx := 44
	var nz := 40
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.frequency = 0.09
	fn.seed = 3312

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz + 1:
		for ix in nx + 1:
			var u := float(ix) / float(nx)
			var v := float(iz) / float(nz)
			var x := lerpf(-hx, hx, u)
			var z := lerpf(-hz, hz, v)
			# эллипс с рваным краем: внутри земля плотная, к краю сходит в ноль
			var d := sqrt(pow(x / hx, 2.0) + pow(z / hz, 2.0))
			var wob := fn.get_noise_2d(x, z) * 0.16
			var a := clampf((0.86 - d + wob) / 0.30, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			st.set_color(Color(1, 1, 1, a))
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(x, 0.0, z))
	for iz2 in nz:
		for ix2 in nx:
			var i0 := iz2 * (nx + 1) + ix2
			var i1 := i0 + 1
			var i2 := i0 + nx + 1
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)

	var mat := Mats.ground(Vector3(0.22, 0.22, 0.22)).duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	# плоскость лежит на земле, и сторону обхода тут проще не угадывать
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.name = "Yard"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = Vector3(0, 0.005, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_statics.add_child(mi)


# ---------------------------------------------------------------- сарай

func _build_shed() -> void:
	var plank_mat := Mats.planks(Vector3(0.55, 0.55, 0.55))
	var beam_mat := Mats.planks(Vector3(0.8, 0.8, 0.8), Color(0.82, 0.78, 0.72))
	var post_mat := Mats.wood(Vector3(0.7, 0.7, 0.7))

	# задняя стена
	_plank_wall(Vector3(0, 0, -SHED_HZ), Vector3.RIGHT, SHED_HX * 2.0, WALL_H, plank_mat, [])
	# левая стена с окном
	_plank_wall(Vector3(-SHED_HX, 0, 0), Vector3.BACK, SHED_HZ * 2.0, WALL_H, plank_mat,
		[Rect2(-0.85, 1.45, 1.7, 1.15)])
	# правая стена
	_plank_wall(Vector3(SHED_HX, 0, 0), Vector3.BACK, SHED_HZ * 2.0, WALL_H, plank_mat, [])
	# передняя стена с широким проёмом
	_plank_wall(Vector3(0, 0, SHED_HZ), Vector3.RIGHT, SHED_HX * 2.0, WALL_H, plank_mat,
		[Rect2(-2.3, 0.0, 4.6, 2.75)])
	_flush_walls(plank_mat)

	# рама окна и стекло
	var frame := Mats.planks(Vector3(1.2, 1.2, 1.2), Color(0.68, 0.64, 0.58))
	for d in [Vector3(0, 1.40, 0), Vector3(0, 2.65, 0)]:
		_box(Vector3(0.09, 0.10, 1.95), Vector3(-SHED_HX, 0, 0) + d, frame, Vector3.ZERO, false)
	for d in [Vector3(0, 2.02, -0.95), Vector3(0, 2.02, 0.95)]:
		_box(Vector3(0.09, 1.35, 0.10), Vector3(-SHED_HX, 0, 0) + d, frame, Vector3.ZERO, false)
	_box(Vector3(0.05, 1.15, 0.08), Vector3(-SHED_HX, 2.02, 0), frame, Vector3.ZERO, false)
	_box(Vector3(0.02, 1.12, 1.66), Vector3(-SHED_HX + 0.01, 2.02, 0), Mats.glass(), Vector3.ZERO, false)

	# угловые столбы
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.18, WALL_H + 0.1, 0.18),
				Vector3(sx * (SHED_HX - 0.05), (WALL_H + 0.1) * 0.5, sz * (SHED_HZ - 0.05)),
				post_mat, Vector3.ZERO, false)
	# столбы у проёма
	for sx in [-2.42, 2.42]:
		_box(Vector3(0.17, WALL_H + 0.1, 0.2), Vector3(sx, (WALL_H + 0.1) * 0.5, SHED_HZ), post_mat, Vector3.ZERO, false)
	# перекладина над проёмом
	_box(Vector3(5.0, 0.22, 0.2), Vector3(0, 2.86, SHED_HZ), beam_mat, Vector3.ZERO, false)

	# геометрия ската
	var slope_dy := RIDGE_Y - EAVE_Y
	var slope_dx := SHED_HX + 0.45
	var slope_len := sqrt(slope_dx * slope_dx + slope_dy * slope_dy)
	var slope_ang := atan2(slope_dy, slope_dx)

	# фронтоны: вертикальные доски, обрезанные ровно по линии ската
	var gable_pitch := 0.185 + 0.028
	var gable_n := int((SHED_HX * 2.0) / gable_pitch)
	for sz in [-1.0, 1.0]:
		var z: float = sz * SHED_HZ
		for i in gable_n:
			var x := -SHED_HX + (SHED_HX * 2.0 - gable_n * gable_pitch) * 0.5 + gable_pitch * 0.5 + i * gable_pitch
			var y_top := RIDGE_Y - absf(x) / slope_dx * slope_dy - 0.08
			var h := y_top - WALL_H
			if h < 0.07:
				continue
			_box(Vector3(0.185, h, 0.05), Vector3(x, WALL_H + h * 0.5, z), plank_mat, Vector3.ZERO, false)

	# коньковый брус
	_box(Vector3(0.2, 0.24, SHED_HZ * 2.0 + 0.9), Vector3(0, RIDGE_Y - 0.16, 0), beam_mat, Vector3.ZERO, false)
	# затяжки
	for i in 5:
		var z2 := -SHED_HZ + 0.7 + i * ((SHED_HZ * 2.0 - 1.4) / 4.0)
		_box(Vector3(SHED_HX * 2.0 + 0.2, 0.16, 0.14), Vector3(0, WALL_H + 0.12, z2), beam_mat, Vector3.ZERO, false)
		for sx2 in [-1.0, 1.0]:
			# стропило прижимаем под плоскость кровли, иначе брус лезет наружу
			var normal := Vector3(sin(slope_ang) * sx2, cos(slope_ang), 0.0)
			var mid := Vector3(sx2 * slope_dx * 0.5, EAVE_Y + slope_dy * 0.5, z2) - normal * 0.11
			_box(Vector3(slope_len, 0.14, 0.12), mid, beam_mat,
				Vector3(0, 0, rad_to_deg(slope_ang) * -sx2), false)

	# кровля: доски со щелями, сквозь них в тумане бьют лучи солнца
	var roof_mat := Mats.roof(Vector3(0.5, 0.5, 0.5))
	var board_w := 0.34
	var gap := 0.035
	var n := int(slope_len / (board_w + gap))
	for sx3 in [-1.0, 1.0]:
		# скат идёт от конька вниз к свесу
		var along := Vector3(sx3 * slope_dx, -slope_dy, 0.0).normalized()
		# а вот так доски задирались вверх, пока крыша была сломана: держим
		# эти позиции наготове — на них крыша встаёт обратно в пасхалке
		var wrong := Vector3(sx3 * slope_dx, slope_dy, 0.0).normalized()
		for i in n:
			var t2 := (float(i) + 0.5) * (board_w + gap) / slope_len
			var pos := Vector3(0, RIDGE_Y, 0) + along * (t2 * slope_len)
			var mi := _box(Vector3(board_w, 0.055, SHED_HZ * 2.0 + 0.9), pos, roof_mat,
				Vector3(0, 0, rad_to_deg(slope_ang) * -sx3), false)
			_roof_boards.append(mi)
			_roof_fixed.append(mi.transform)
			var broken := mi.transform
			broken.origin = Vector3(0, RIDGE_Y - 0.04, 0) + wrong * (t2 * slope_len)
			_roof_broken.append(broken)

	# коньковая планка накрывает стык двух скатов
	for sx4 in [-1.0, 1.0]:
		_box(Vector3(0.36, 0.05, SHED_HZ * 2.0 + 0.9), Vector3(sx4 * 0.15, RIDGE_Y + 0.05, 0), roof_mat,
			Vector3(0, 0, rad_to_deg(slope_ang) * -sx4), false)

	# коллизия стен одним куском на стену — так физике спокойнее
	_collider(Vector3(SHED_HX * 2.0 + 0.4, WALL_H, 0.12), Vector3(0, WALL_H * 0.5, -SHED_HZ))
	_collider(Vector3(0.12, WALL_H, SHED_HZ * 2.0), Vector3(-SHED_HX, WALL_H * 0.5, 0))
	_collider(Vector3(0.12, WALL_H, SHED_HZ * 2.0), Vector3(SHED_HX, WALL_H * 0.5, 0))
	_collider(Vector3(2.2, WALL_H, 0.12), Vector3(-3.4, WALL_H * 0.5, SHED_HZ))
	_collider(Vector3(2.2, WALL_H, 0.12), Vector3(3.4, WALL_H * 0.5, SHED_HZ))


# --------------------------------------------------------- пасхалка: пекло

## Крыша встаёт обратно ровно в то сломанное положение, в котором была до
## починки: доски задираются вверх двумя крыльями, будто сарай развернуло.
func blow_roof() -> void:
	if _roof_boards.is_empty():
		return
	if _roof_tween:
		_roof_tween.kill()
	_roof_tween = create_tween().set_parallel(true)
	for i in _roof_boards.size():
		# от конька к свесу — волной, а не всё разом
		var delay := absf(_roof_broken[i].origin.x) * 0.06
		_roof_tween.tween_property(_roof_boards[i], "transform", _roof_broken[i], 0.9) \
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func restore_roof() -> void:
	if _roof_tween:
		_roof_tween.kill()
	for i in _roof_boards.size():
		_roof_boards[i].transform = _roof_fixed[i]


## Небо затягивает гарью, солнце глохнет, всё тонет в оранжевом.
func set_apocalypse() -> void:
	if _calm.is_empty():
		_calm = {
			"amb_c": env.ambient_light_color, "amb_e": env.ambient_light_energy,
			"fog_c": env.fog_light_color, "fog_d": env.fog_density,
			"fog_sky": env.fog_sky_affect, "vf_d": env.volumetric_fog_density,
			"vf_em": env.volumetric_fog_emission, "vf_ee": env.volumetric_fog_emission_energy,
			"exp": env.tonemap_exposure,
			"sun_c": sun.light_color, "sun_e": sun.light_energy,
		}
	env.ambient_light_color = Color(1.0, 0.48, 0.22)
	env.ambient_light_energy = 0.75
	env.fog_light_color = Color(0.34, 0.17, 0.09)
	env.fog_density = 0.005
	env.fog_sky_affect = 0.3
	env.volumetric_fog_density = 0.011
	env.volumetric_fog_emission = Color(0.72, 0.24, 0.06)
	env.volumetric_fog_emission_energy = 0.55
	# на таком огне любая камера прикрывает диафрагму — иначе кадр белый
	env.tonemap_exposure = _calm["exp"] * 0.6
	sun.light_color = Color(1.0, 0.46, 0.20)
	sun.light_energy = 0.45


## Дым, которому некуда деваться, повисает в сарае: сизая мгла от 0 до 1.
## Держим её объёмом ровно по стенам, иначе глобальный туман затягивает и улицу.
func set_haze(x: float) -> void:
	var k := clampf(x, 0.0, 1.0)
	if _haze_vol == null:
		if k <= 0.0:
			return
		var fm := FogMaterial.new()
		fm.albedo = Color(0.60, 0.59, 0.58)
		# без подсвета дым в сарае выходит чёрной ватой: света внутрь попадает мало
		fm.emission = Color(0.12, 0.115, 0.108)
		fm.height_falloff = 0.4
		_haze_vol = FogVolume.new()
		_haze_vol.name = "Haze"
		_haze_vol.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		_haze_vol.size = Vector3(SHED_HX * 2.0 - 0.1, 2.7, SHED_HZ * 2.0 - 0.1)
		_haze_vol.position = Vector3(0, 1.35, 0)
		_haze_vol.material = fm
		add_child(_haze_vol)
	var fm2 := _haze_vol.material as FogMaterial
	fm2.density = k * 0.3
	_haze_vol.visible = k > 0.002


func set_calm() -> void:
	if _calm.is_empty():
		return
	env.ambient_light_color = _calm["amb_c"]
	env.ambient_light_energy = _calm["amb_e"]
	env.fog_light_color = _calm["fog_c"]
	env.fog_density = _calm["fog_d"]
	env.fog_sky_affect = _calm["fog_sky"]
	env.volumetric_fog_density = _calm["vf_d"]
	env.volumetric_fog_emission = _calm["vf_em"]
	env.volumetric_fog_emission_energy = _calm["vf_ee"]
	env.tonemap_exposure = _calm["exp"]
	sun.light_color = _calm["sun_c"]
	sun.light_energy = _calm["sun_e"]
	if sky:
		sky.apply()


# ---------------------------------------------------------------- утварь

func _build_clutter() -> void:
	var plank_mat := Mats.planks(Vector3(0.7, 0.7, 0.7))
	var wood_mat := Mats.wood(Vector3(0.8, 0.8, 0.8))
	var metal_mat := Mats.metal(Vector3(0.6, 0.6, 0.6))

	var rng := RandomNumberGenerator.new()
	rng.seed = 777

	# верстак: столешница, четыре ножки и полка — всё одним телом
	var bench := _body(Vector3(-3.1, 0, -2.2), 26.0, 0.85)
	_part_box(bench, Vector3(2.0, 0.09, 0.8), Vector3(0, 0.86, 0), plank_mat)
	for dx in [-0.85, 0.85]:
		for dz in [-0.3, 0.3]:
			_part_box(bench, Vector3(0.10, 0.82, 0.10), Vector3(dx, 0.41, dz), wood_mat)
	_part_box(bench, Vector3(1.8, 0.06, 0.6), Vector3(0, 0.30, 0), plank_mat)

	# бочка с водой: полная, поэтому тяжёлая
	barrel = _body(Vector3(3.6, 0, -2.6), 70.0, 0.75)
	_part_cyl(barrel, 0.34, 0.9, Vector3(0, 0.45, 0), metal_mat)
	for y in [0.16, 0.74]:
		_part_cyl(barrel, 0.355, 0.06, Vector3(0, y, 0), Mats.metal(Vector3(1.4, 1.4, 1.4)), false)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.12, 0.17, 0.16)
	water.roughness = 0.04
	water.metallic = 0.2
	water.metallic_specular = 0.9
	_part_cyl(barrel, 0.325, 0.01, Vector3(0, 0.82, 0), water, false)

	# штабель досок: каждая доска сама по себе, чтобы штабель можно было раскатать
	for i in 9:
		var plank := _body(Vector3(2.9 + rng.randf_range(-0.05, 0.05), 0.0, 2.3), 7.0)
		_part_box(plank, Vector3(2.6, 0.055, 0.24), Vector3(0, 0.05 + i * 0.062, 0),
			plank_mat, Vector3(0, rng.randf_range(-1.2, 1.2), 0))

	# поддон с кирпичами: сдвинуть можно, но махина
	var pallet := _body(Vector3(-3.5, 0, 1.9), 160.0, 0.95)
	_part_box(pallet, Vector3(1.3, 0.11, 1.0), Vector3(0, 0.055, 0), wood_mat)
	for layer in 6:
		for i in 5:
			for j in 3:
				var p := Vector3(-0.4 + j * 0.27 + (0.135 if layer % 2 == 1 else 0.0),
					0.155 + layer * 0.10, -0.4 + i * 0.20)
				_part_box(pallet, Vector3(0.25, 0.09, 0.12), p,
					Mats.brick_variant(layer * 7 + i * 3 + j),
					Vector3(0, rng.randf_range(-1.5, 1.5), 0), layer == 5)

	# козлы
	var horse := _body(Vector3(4.0, 0, 1.4), 9.0)
	for sx in [-1.0, 1.0]:
		_part_box(horse, Vector3(0.08, 0.8, 0.08), Vector3(sx * 0.02, 0.4, sx * 0.35),
			wood_mat, Vector3(sx * 12.0, 0, 0))
	_part_box(horse, Vector3(0.1, 0.1, 1.1), Vector3(0, 0.82, 0), wood_mat)

	# куча опилок в углу: сыпучее, поэтому лежит мёртвым грузом
	var dust_mat := Mats.wood(Vector3(2.0, 2.0, 2.0))
	var heap := _body(Vector3(-4.0, 0, -0.4), 45.0, 1.0)
	for i in 3:
		var sm := SphereMesh.new()
		sm.radius = 0.42 - i * 0.07
		sm.height = 0.34 - i * 0.06
		sm.radial_segments = 20
		sm.rings = 8
		var mi2 := MeshInstance3D.new()
		mi2.mesh = sm
		mi2.material_override = dust_mat
		mi2.position = Vector3(i * 0.35, 0.02, i * 0.2)
		heap.add_child(mi2)
		var hs := SphereShape3D.new()
		hs.radius = sm.radius * 0.8
		var hcs := CollisionShape3D.new()
		hcs.shape = hs
		hcs.position = mi2.position
		heap.add_child(hcs)

	# подстилка под запасы топлива: сами запасы раскладывает game.gd настоящими
	# предметами, чтобы их можно было расшвырять и сжечь
	# плоские, иначе куски топлива утонут в собственной подстилке
	_cyl(0.42, 0.025, HAY_STOCK + Vector3(0, 0.012, 0), Mats.dry_grass(Vector3(4, 4, 4)), false)
	_cyl(0.5, 0.025, COAL_STOCK + Vector3(0, 0.012, 0), Mats.coal(Vector3(7, 7, 7)), false)


# ---------------------------------------------------------------- помощники

func _pmat(friction: float, bounce: float) -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = bounce
	return pm


## Пустое физическое тело под утварь. Части добавляются отдельно, потому что
## верстак или бочка должны валиться целиком, а не рассыпаться на ножки и обручи.
func _body(origin: Vector3, mass: float, friction := 0.9) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.position = origin
	b.collision_layer = Piece.LAYER_SOLID
	b.collision_mask = Piece.LAYER_WORLD | Piece.LAYER_SOLID | Piece.LAYER_DEBRIS
	b.physics_material_override = _pmat(friction, 0.0)
	b.angular_damp = 0.8
	b.linear_damp = 0.05
	b.can_sleep = true
	add_child(b)
	props.append(b)
	return b


## Коробка внутри тела: и меш, и форма столкновения в локальных координатах.
func _part_box(body: RigidBody3D, size: Vector3, pos: Vector3, mat: Material,
		rot_deg := Vector3.ZERO, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	body.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		cs.rotation_degrees = rot_deg
		body.add_child(cs)
	return mi


func _part_cyl(body: RigidBody3D, radius: float, height: float, pos: Vector3,
		mat: Material, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 28
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	body.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		cs.position = pos
		body.add_child(cs)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO,
		collide := false, friction := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_box(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	_statics.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		body.position = pos
		body.rotation_degrees = rot_deg
		body.physics_material_override = _pmat(friction, 0.0)
		add_child(body)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_cyl(radius, height)
	mi.material_override = mat
	mi.position = pos
	_statics.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		body.add_child(cs)
		body.position = pos
		body.physics_material_override = _pmat(0.8, 0.0)
		add_child(body)
	return mi


func _plane(size: Vector2, pos: Vector3, mat: Material, subdiv: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = subdiv
	pm.subdivide_depth = subdiv
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	_statics.add_child(mi)
	return mi


## Сарай набран из сотен одинаковых досок. Если у каждой свой меш, движок
## рисует их по одной; общий меш на одинаковый размер — и он складывает их
## в одну пачку. Это тут главная экономия кадров.
func _shared_box(size: Vector3) -> BoxMesh:
	var key := "b:%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var bm := BoxMesh.new()
	bm.size = size
	_meshes[key] = bm
	return bm


func _shared_cyl(radius: float, height: float) -> CylinderMesh:
	var key := "c:%.3f,%.3f" % [radius, height]
	if _meshes.has(key):
		return _meshes[key]
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 24
	cm.rings = 1
	_meshes[key] = cm
	return cm


func _collider(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = pos
	body.physics_material_override = _pmat(0.85, 0.0)
	add_child(body)


## Стена из вертикальных досок с зазорами. `holes` — прямоугольники в координатах
## (смещение вдоль стены, высота), например проём или окно.
func _plank_wall(center: Vector3, along: Vector3, width: float, height: float,
		mat: Material, holes: Array) -> void:
	var board_w := 0.185
	var gap := 0.028
	var thick := 0.05
	var pitch := board_w + gap
	var count := int(width / pitch)
	var start := -width * 0.5 + (width - count * pitch) * 0.5 + pitch * 0.5
	var normal := Vector3(along.z, 0, along.x).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs(center.x * 131.0 + center.z * 17.0)) + 5

	for i in count:
		var u := start + i * pitch
		var segments := [Vector2(0.0, height)]
		for h in holes:
			var r: Rect2 = h
			if u + board_w * 0.5 > r.position.x and u - board_w * 0.5 < r.position.x + r.size.x:
				var next: Array = []
				for s in segments:
					var seg: Vector2 = s
					var hy0: float = r.position.y
					var hy1: float = r.position.y + r.size.y
					if hy1 <= seg.x or hy0 >= seg.y:
						next.append(seg)
						continue
					if hy0 > seg.x:
						next.append(Vector2(seg.x, hy0))
					if hy1 < seg.y:
						next.append(Vector2(hy1, seg.y))
				segments = next
		var jitter := normal * rng.randf_range(-0.006, 0.006)
		for s2 in segments:
			var seg2: Vector2 = s2
			var h2: float = seg2.y - seg2.x
			if h2 < 0.08:
				continue
			var pos := center + along.normalized() * u + Vector3(0, seg2.x + h2 * 0.5, 0) + jitter
			var size := Vector3(
				abs(along.x) * board_w + abs(normal.x) * thick,
				h2,
				abs(along.z) * board_w + abs(normal.z) * thick
			)
			# доски копятся и уходят одним мешем: их под две сотни, и каждая
			# отдельным узлом стоила бы больше, чем вся остальная сцена
			var tint := 0.86 + rng.randf_range(-0.10, 0.14)
			if rng.randf() >= 0.35:
				tint = 1.0
			_wall_xf.append(Transform3D(Basis.from_scale(size), pos))
			_wall_col.append(Color(tint, tint * 0.985, tint * 0.96))


## Собрать накопленные доски в один MultiMesh: цвет каждой доски — в инстанс.
func _flush_walls(mat: StandardMaterial3D) -> void:
	if _wall_xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	mm.mesh = unit
	mm.instance_count = _wall_xf.size()
	for i in _wall_xf.size():
		mm.set_instance_transform(i, _wall_xf[i])
		mm.set_instance_color(i, _wall_col[i])

	var mi := MultiMeshInstance3D.new()
	mi.name = "Walls"
	mi.multimesh = mm
	var m := mat.duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	add_child(mi)
	_wall_xf.clear()
	_wall_col.clear()
