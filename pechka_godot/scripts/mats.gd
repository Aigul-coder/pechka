class_name Mats
extends RefCounted

## Библиотека PBR-материалов. Текстуры лежат в res://assets/textures/
## с именами <набор>_color.jpg, _normal.jpg, _rough.jpg, _ao.jpg, _height.jpg.
## Если какой-то карты нет — материал спокойно обходится без неё.

const DIR := "res://assets/textures/"

static var _cache: Dictionary = {}

static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = ResourceLoader.load(path) as Texture2D
	_cache[path] = t
	return t


static func make(set_name: String, uv: Vector3 = Vector3.ONE, opts: Dictionary = {}) -> StandardMaterial3D:
	var key := "mat:%s:%s:%s" % [set_name, uv, opts]
	if _cache.has(key):
		return _cache[key]

	var m := StandardMaterial3D.new()
	var color := tex(DIR + set_name + "_color.jpg")
	if color:
		m.albedo_texture = color
	m.albedo_color = opts.get("tint", Color.WHITE)

	var nrm := tex(DIR + set_name + "_normal.jpg")
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = opts.get("normal", 1.0)

	var rgh := tex(DIR + set_name + "_rough.jpg")
	if rgh:
		m.roughness_texture = rgh
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		m.roughness = opts.get("rough_mul", 1.0)
	else:
		m.roughness = opts.get("rough", 0.85)

	var ao := tex(DIR + set_name + "_ao.jpg")
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		m.ao_light_affect = opts.get("ao", 0.75)

	var hgt: Texture2D = tex(DIR + set_name + "_height.jpg")
	if hgt and opts.get("parallax", false):
		m.heightmap_enabled = true
		m.heightmap_texture = hgt
		m.heightmap_scale = opts.get("parallax_depth", 3.0)
		m.heightmap_deep_parallax = true
		m.heightmap_min_layers = 8
		m.heightmap_max_layers = 32

	m.metallic = opts.get("metallic", 0.0)
	m.metallic_specular = opts.get("specular", 0.5)
	m.uv1_scale = uv
	m.uv1_triplanar = opts.get("triplanar", false)
	if m.uv1_triplanar:
		m.uv1_world_triplanar = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.texture_repeat = true

	_cache[key] = m
	return m


## --- конкретные материалы мира ---

const BRICK_VARIANTS := 14

## Отдельный кирпич — обожжённая глина: гладкая поверхность со своим оттенком
## и мелким рельефом. У каждого кирпича свой вариант, поэтому кладка не выглядит
## штампованной.
## Мягкое круглое пятно для частиц. Без него пар и снег рисуются жёсткими
## квадратами — самая заметная дешёвка в кадре.
static func soft_dot() -> ImageTexture:
	if _cache.has("softdot"):
		return _cache["softdot"]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBAF)
	for y in n:
		for x in n:
			var d := Vector2(float(x) / n - 0.5, float(y) / n - 0.5).length() * 2.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var t := ImageTexture.create_from_image(img)
	_cache["softdot"] = t
	return t


static func brick_variant(idx: int) -> StandardMaterial3D:
	var v := idx % BRICK_VARIANTS
	var key := "brickvar:%d" % v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + v * 137
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(DIR + "clay_color.jpg")
	m.albedo_color = Color.from_hsv(
		0.036 + rng.randf_range(-0.012, 0.014),
		0.40 + rng.randf_range(-0.12, 0.10),
		1.32 + rng.randf_range(-0.30, 0.16)
	)
	var nrm := tex(DIR + "concrete_normal.jpg")
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 0.3
	m.roughness = 0.9
	m.metallic = 0.0
	m.metallic_specular = 0.3
	m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	m.uv1_offset = Vector3(rng.randf(), rng.randf(), 0.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

static func brick(tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := brick_variant(0).duplicate() as StandardMaterial3D
	m.albedo_color = m.albedo_color * tint
	return m

static func brick_hot(base: StandardMaterial3D, heat: float) -> StandardMaterial3D:
	var m := base.duplicate() as StandardMaterial3D
	m.emission_enabled = true
	m.emission = Color(1.0, 0.30, 0.05)
	m.emission_energy_multiplier = heat
	return m

static func brickwall() -> StandardMaterial3D:
	return make("brickwall", Vector3(4.0, 2.0, 1.0), {"normal": 1.4, "ao": 0.9})

static func planks(uv: Vector3 = Vector3(1, 1, 1), tint: Color = Color.WHITE) -> StandardMaterial3D:
	return make("planks", uv, {
		"tint": tint * Color(1.35, 1.28, 1.18), "normal": 1.2, "ao": 0.8, "rough": 0.85, "triplanar": true,
	})

static func wood(uv: Vector3 = Vector3(1, 1, 1)) -> StandardMaterial3D:
	return make("wood", uv, {"normal": 1.5, "ao": 0.85, "rough": 0.9})

static func concrete(uv: Vector3 = Vector3(1, 1, 1), tint: Color = Color.WHITE) -> StandardMaterial3D:
	return make("concrete", uv, {"tint": tint, "normal": 1.1, "ao": 0.8, "rough": 0.92})

static func metal(uv: Vector3 = Vector3(1, 1, 1)) -> StandardMaterial3D:
	return make("metal", uv, {"normal": 1.0, "metallic": 0.9, "specular": 0.7, "rough": 0.4})

static func ground(uv: Vector3 = Vector3(0.35, 0.35, 0.35)) -> StandardMaterial3D:
	return make("ground", uv, {
		"normal": 1.2, "ao": 0.9, "rough": 0.98, "specular": 0.15,
		"tint": Color(0.52, 0.48, 0.42), "triplanar": true,
	})

static func grass(uv: Vector3 = Vector3(0.18, 0.18, 0.18)) -> StandardMaterial3D:
	return make("grass", uv, {
		"normal": 1.0, "ao": 0.9, "rough": 1.0, "specular": 0.1,
		"tint": Color(0.46, 0.54, 0.38), "triplanar": true,
	})

## Сухая трава: берём древесную текстуру — её волокна читаются как соломины,
## чего от зелёной травяной карты не добиться никаким тонированием.
static func dry_grass(uv: Vector3 = Vector3(5, 5, 5)) -> StandardMaterial3D:
	return make("planks", uv, {
		"normal": 1.5, "ao": 0.8, "rough": 1.0, "specular": 0.12,
		"tint": Color(1.32, 1.02, 0.48),
	})

static func chip(uv: Vector3 = Vector3(2.2, 2.2, 2.2)) -> StandardMaterial3D:
	return make("planks", uv, {
		"normal": 0.9, "ao": 0.8, "rough": 0.9, "tint": Color(1.05, 0.92, 0.72),
	})

## Уголь: почти чёрный, но с жирным блеском на изломах — этим он и отличается
## от золы, которая матовая насквозь.
static func coal(uv: Vector3 = Vector3(9, 9, 9)) -> StandardMaterial3D:
	return make("concrete", uv, {
		"normal": 1.8, "ao": 0.9, "rough": 0.44, "specular": 0.55,
		"tint": Color(0.085, 0.08, 0.088),
	})

static func roof(uv: Vector3 = Vector3(1, 1, 1)) -> StandardMaterial3D:
	return make("roof", uv, {
		"normal": 1.3, "ao": 0.85, "rough": 0.9, "specular": 0.3,
		"tint": Color(0.62, 0.60, 0.56),
	})

static func mortar() -> StandardMaterial3D:
	return make("concrete", Vector3(5, 5, 5), {"tint": Color(0.92, 0.88, 0.82), "rough": 1.0, "normal": 0.9, "ao": 0.9})

static func glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.85, 0.88, 0.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.1
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## --- процедурные текстуры для частиц ---

static func blob_tex(size: int = 128, power: float = 2.2) -> Texture2D:
	var key := "blob:%d:%f" % [size, power]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBAF)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func puff_tex(size: int = 256) -> Texture2D:
	var key := "puff:%d" % size
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.018
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	n.seed = 1337
	var img := Image.create(size, size, false, Image.FORMAT_RGBAF)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var fall: float = clampf(1.0 - d, 0.0, 1.0)
			fall = fall * fall * (3.0 - 2.0 * fall)
			var v := n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var a: float = clampf(fall * (0.45 + 0.75 * v), 0.0, 1.0)
			var lum: float = 0.72 + 0.28 * v
			img.set_pixel(x, y, Color(lum, lum, lum, a))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func spark_tex() -> Texture2D:
	return blob_tex(32, 1.4)
