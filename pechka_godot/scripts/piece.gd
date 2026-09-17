class_name Piece
extends RigidBody3D

## Один физический предмет: кирпич, труба, подпорка, щепотка опилок или зола.
## Горение и нагрев считает game.gd, здесь только состояние и внешний вид.

enum Kind { BRICK, PIPE, PROP, DUST, ASH, HAY, CHIP, COAL }

const BRICK_SIZE := Vector3(0.25, 0.09, 0.12)
const PIPE_R := 0.088
const PIPE_R_IN := 0.058
const PIPE_H := 0.42
const PROP_R := 0.052
const PROP_H := 0.62
const DUST_S := 0.034
const ASH_S := 0.024
const HAY_SIZE := Vector3(0.15, 0.032, 0.085)
const CHIP_SIZE := Vector3(0.088, 0.008, 0.026)
const COAL_S := 0.062

const LAYER_WORLD := 1
const LAYER_SOLID := 2
const LAYER_DEBRIS := 4
const LAYER_PLAYER := 8

var kind: Kind = Kind.BRICK
var fuel := 0.0
var heat := 0.0
var burning := false
var cemented := false
var bond := 0.0                 ## прочность шва: 1 — перевязка, 0.35 — стык в стык
var cracked := false            ## шов уже лопнул, второй раз рвать нечего
var frac := 1.0                 ## доля целого кирпича по длине
var mi: MeshInstance3D
var base_mat: StandardMaterial3D

var _glow_mat: StandardMaterial3D
var _shown_glow := -1.0


## frac — доля кирпича по длине: 1 целый, 0.75 трёхчетвертка, 0.5 половинка.
## Без них кладку по-настоящему не перевязать.
static func create(k: Kind, variant: int = 0, frac: float = 1.0) -> Piece:
	var p := Piece.new()
	p.kind = k
	p.mi = MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	p.collision_layer = LAYER_SOLID
	p.collision_mask = LAYER_WORLD | LAYER_SOLID | LAYER_DEBRIS
	p.continuous_cd = true
	p.max_contacts_reported = 0
	p.contact_monitor = false
	p.can_sleep = true

	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.0
	p.physics_material_override = pm

	match k:
		Kind.BRICK:
			p.frac = clampf(frac, 0.25, 1.0)
			var size := Vector3(BRICK_SIZE.x * p.frac, BRICK_SIZE.y, BRICK_SIZE.z)
			p.mi.mesh = _box_mesh(size)
			cs.shape = _box_shape(size)
			p.base_mat = Mats.brick_variant(variant)
			p.mass = 3.4 * p.frac
			p.angular_damp = 1.2
			p.linear_damp = 0.15

		Kind.PIPE:
			p.mi.mesh = _shared("pipe", func(): return _tube_mesh(PIPE_R, PIPE_R_IN, PIPE_H, 28))
			cs.shape = _cyl_shape(PIPE_R, PIPE_H)
			p.base_mat = Mats.make("concrete", Vector3(2.0, 1.2, 1.0), {
				"tint": Color(0.58, 0.55, 0.52), "normal": 1.2, "rough": 0.88, "ao": 0.8,
			})
			p.mass = 9.0
			p.angular_damp = 1.4
			p.linear_damp = 0.2

		Kind.PROP:
			p.mi.mesh = _shared("prop", func():
				var cm := CylinderMesh.new()
				cm.top_radius = PROP_R * 0.88
				cm.bottom_radius = PROP_R
				cm.height = PROP_H
				cm.radial_segments = 18
				cm.rings = 3
				return cm)
			cs.shape = _cyl_shape(PROP_R, PROP_H)
			p.base_mat = Mats.wood(Vector3(1.6, 1.0, 1.0))
			p.mass = 2.2
			p.fuel = 30.0
			p.angular_damp = 1.0
			p.linear_damp = 0.15

		Kind.DUST:
			var dsize := Vector3(DUST_S, DUST_S * 0.55, DUST_S)
			p.mi.mesh = _box_mesh(dsize)
			cs.shape = _box_shape(dsize)
			p.base_mat = Mats.make("wood", Vector3(6, 6, 6), {
				"tint": Color(1.25, 1.05, 0.72), "rough": 0.95,
			})
			p.mass = 0.06
			p.collision_layer = LAYER_DEBRIS
			p.continuous_cd = false
			p.fuel = 3.2
			p.angular_damp = 2.0
			p.linear_damp = 0.6

		Kind.HAY:
			p.mi.mesh = _box_mesh(HAY_SIZE)
			cs.shape = _box_shape(HAY_SIZE)
			p.base_mat = Mats.dry_grass()
			p.mass = 0.08
			p.collision_layer = LAYER_DEBRIS
			p.continuous_cd = false
			p.fuel = 1.7
			p.angular_damp = 2.4
			p.linear_damp = 0.9

		Kind.CHIP:
			p.mi.mesh = _box_mesh(CHIP_SIZE)
			cs.shape = _box_shape(CHIP_SIZE)
			p.base_mat = Mats.chip()
			p.mass = 0.14
			p.collision_layer = LAYER_DEBRIS
			p.continuous_cd = false
			p.fuel = 6.5
			p.angular_damp = 1.8
			p.linear_damp = 0.4

		Kind.COAL:
			# кусок угля: неровный, приплюснутый, каждый чуть своей формы
			var ksize := Vector3(COAL_S, COAL_S * 0.72, COAL_S * 0.86)
			p.mi.mesh = _box_mesh(ksize)
			cs.shape = _box_shape(ksize)
			p.base_mat = Mats.coal()
			p.mass = 0.34
			p.collision_layer = LAYER_DEBRIS
			p.continuous_cd = false
			p.fuel = 34.0
			p.angular_damp = 1.6
			p.linear_damp = 0.3

		Kind.ASH:
			var asize := Vector3(ASH_S, ASH_S * 0.6, ASH_S)
			p.mi.mesh = _box_mesh(asize)
			cs.shape = _box_shape(asize)
			p.base_mat = Mats.make("concrete", Vector3(8, 8, 8), {
				"tint": Color(0.16, 0.15, 0.15), "rough": 1.0,
			})
			p.mass = 0.03
			p.collision_layer = LAYER_DEBRIS
			p.continuous_cd = false
			p.angular_damp = 2.5
			p.linear_damp = 0.8

	p.mi.material_override = p.base_mat
	p.mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	if k == Kind.DUST or k == Kind.ASH or k == Kind.CHIP:
		p.mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		p.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif k == Kind.HAY or k == Kind.COAL:
		# мелочь тени почти не даёт, а в проход по теневым картам лезет наравне
		# со стеной — на сотне кусков это заметные кадры
		p.mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		p.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(p.mi)
	p.add_child(cs)
	return p


func is_flammable() -> bool:
	return kind == Kind.PROP or kind == Kind.DUST or kind == Kind.HAY \
		or kind == Kind.CHIP or kind == Kind.COAL


func is_solid() -> bool:
	return kind == Kind.BRICK or kind == Kind.PIPE or kind == Kind.PROP


func half_height() -> float:
	match kind:
		Kind.BRICK: return BRICK_SIZE.y * 0.5
		Kind.PIPE: return PIPE_H * 0.5
		Kind.PROP: return PROP_H * 0.5
		Kind.DUST: return DUST_S * 0.3
		Kind.HAY: return HAY_SIZE.y * 0.5
		Kind.CHIP: return CHIP_SIZE.y * 0.5
		Kind.COAL: return COAL_S * 0.36
		_: return ASH_S * 0.3


## Приклеить цементом: предмет становится частью печки и больше не шатается.
func cement() -> void:
	if cemented:
		return
	cemented = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func unfreeze() -> void:
	cemented = false
	bond = 0.0
	freeze = false


## Обновить внешний вид по нагреву: дерево обугливается, кирпич начинает
## светиться изнутри как в настоящей топке.
func refresh_look() -> void:
	var glow := 0.0
	if burning:
		glow = 1.6
	elif heat > 0.08:
		glow = (heat - 0.08) * 0.55
	glow = snappedf(clampf(glow, 0.0, 2.0), 0.08)
	if is_equal_approx(glow, _shown_glow):
		return
	_shown_glow = glow
	if glow <= 0.001:
		mi.material_override = base_mat
		return
	if _glow_mat == null:
		_glow_mat = base_mat.duplicate() as StandardMaterial3D
		_glow_mat.emission_enabled = true
	var char_amount: float = 0.0
	if is_flammable() and burning:
		char_amount = 0.75
	_glow_mat.albedo_color = base_mat.albedo_color.lerp(Color(0.09, 0.07, 0.06), char_amount)
	_glow_mat.emission = Color(1.0, 0.34, 0.06)
	_glow_mat.emission_energy_multiplier = glow
	mi.material_override = _glow_mat


## Полая труба: внешняя и внутренняя стенки плюс кольцо сверху и снизу.
## Общие меши и формы. Двести кирпичей с одинаковым, но каждый со своим мешем
## движок рисует по одному; с общим — складывает в пачку.
static var _res: Dictionary = {}


static func _shared(key: String, make: Callable) -> Mesh:
	if not _res.has(key):
		_res[key] = make.call()
	return _res[key]


static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "bm:%.4f,%.4f,%.4f" % [size.x, size.y, size.z]
	if not _res.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_res[key] = bm
	return _res[key]


static func _box_shape(size: Vector3) -> BoxShape3D:
	var key := "bs:%.4f,%.4f,%.4f" % [size.x, size.y, size.z]
	if not _res.has(key):
		var bs := BoxShape3D.new()
		bs.size = size
		_res[key] = bs
	return _res[key]


static func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var key := "cs:%.4f,%.4f" % [radius, height]
	if not _res.has(key):
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		_res[key] = sh
	return _res[key]


static func _tube_mesh(r_out: float, r_in: float, h: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := -h * 0.5
	var y1 := h * 0.5

	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var u0 := float(i) / float(seg)
		var u1 := float(i + 1) / float(seg)

		# внешняя стенка
		_quad(st,
			Vector3(c0.x * r_out, y0, c0.y * r_out), Vector3(c1.x * r_out, y0, c1.y * r_out),
			Vector3(c1.x * r_out, y1, c1.y * r_out), Vector3(c0.x * r_out, y1, c0.y * r_out),
			Vector3(c0.x, 0, c0.y), Vector3(c1.x, 0, c1.y),
			u0, u1, 0.0, 1.0)
		# внутренняя стенка, нормали внутрь
		_quad(st,
			Vector3(c1.x * r_in, y0, c1.y * r_in), Vector3(c0.x * r_in, y0, c0.y * r_in),
			Vector3(c0.x * r_in, y1, c0.y * r_in), Vector3(c1.x * r_in, y1, c1.y * r_in),
			Vector3(-c1.x, 0, -c1.y), Vector3(-c0.x, 0, -c0.y),
			u1, u0, 0.0, 1.0)
		# кольцо сверху
		_quad(st,
			Vector3(c0.x * r_in, y1, c0.y * r_in), Vector3(c1.x * r_in, y1, c1.y * r_in),
			Vector3(c1.x * r_out, y1, c1.y * r_out), Vector3(c0.x * r_out, y1, c0.y * r_out),
			Vector3.UP, Vector3.UP, u0, u1, 0.0, 0.12)
		# кольцо снизу
		_quad(st,
			Vector3(c0.x * r_out, y0, c0.y * r_out), Vector3(c1.x * r_out, y0, c1.y * r_out),
			Vector3(c1.x * r_in, y0, c1.y * r_in), Vector3(c0.x * r_in, y0, c0.y * r_in),
			Vector3.DOWN, Vector3.DOWN, u0, u1, 0.0, 0.12)

	st.generate_tangents()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, u0: float, u1: float, v0: float, v1: float) -> void:
	var n0 := na.normalized()
	var n1 := nb.normalized()
	_vtx(st, a, n0, Vector2(u0, v0))
	_vtx(st, b, n1, Vector2(u1, v0))
	_vtx(st, c, n1, Vector2(u1, v1))
	_vtx(st, a, n0, Vector2(u0, v0))
	_vtx(st, c, n1, Vector2(u1, v1))
	_vtx(st, d, n0, Vector2(u0, v1))


static func _vtx(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)
