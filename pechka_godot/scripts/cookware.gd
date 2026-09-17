class_name Cookware
extends RigidBody3D

## Чугунок с картошкой и каравай хлеба. Оба доходят от жара, оба сгорают,
## если жар держать слишком долго: чугунок — на плите, хлеб — в горниле.

enum Kind { POT, BREAD }

## В каком пекле каждому хорошо. Чугунку нужна горячая плита, хлебу —
## остывающая топка без огня, как в настоящей русской печи.
const BEST := {Kind.POT: 220.0, Kind.BREAD: 230.0}
const BURN_AT := {Kind.POT: 400.0, Kind.BREAD: 330.0}

var kind: Kind = Kind.POT
var cook := 0.0                 ## 0 — сырое, 1 — готово
var char_level := 0.0           ## 0 — не горелое, 1 — уголёк
var announced := false

var _mi: MeshInstance3D
var _lid: MeshInstance3D
var _steam: GPUParticles3D
var _base: Color


static func create(k: Kind) -> Cookware:
	var c := Cookware.new()
	c.kind = k
	c.name = "Pot" if k == Kind.POT else "Bread"
	c.collision_layer = Piece.LAYER_SOLID
	c.collision_mask = Piece.LAYER_WORLD | Piece.LAYER_SOLID
	c.angular_damp = 1.4
	c.set_meta("carry", true)

	var cs := CollisionShape3D.new()
	if k == Kind.POT:
		c.mass = 6.5
		c._base = Color(0.1, 0.1, 0.105)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c._base
		mat.roughness = 0.52
		mat.metallic = 0.55
		mat.metallic_specular = 0.4

		c._mi = MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.115
		pm.height = 0.19
		pm.radial_segments = 24
		pm.rings = 12
		c._mi.mesh = pm
		c._mi.material_override = mat
		c.add_child(c._mi)

		c._lid = MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.072
		lm.bottom_radius = 0.086
		lm.height = 0.016
		lm.radial_segments = 20
		c._lid.mesh = lm
		c._lid.material_override = mat
		c._lid.position = Vector3(0, 0.094, 0)
		c.add_child(c._lid)

		var sh := CylinderShape3D.new()
		sh.radius = 0.1
		sh.height = 0.19
		cs.shape = sh
	else:
		c.mass = 0.9
		c._base = Color(0.52, 0.34, 0.16)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = c._base
		bmat.roughness = 0.85

		c._mi = MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.1
		bm.height = 0.12
		bm.radial_segments = 20
		bm.rings = 10
		c._mi.mesh = bm
		c._mi.material_override = bmat
		c.add_child(c._mi)

		var bs := SphereShape3D.new()
		bs.radius = 0.095
		cs.shape = bs
	c.add_child(cs)

	c._steam = _make_steam()
	c._steam.position = Vector3(0, 0.12, 0)
	c.add_child(c._steam)
	return c


## Довести до ума за кадр. Возвращает событие: "" / "готово" / "сгорело".
func simmer(delta: float, heat: float) -> String:
	var best: float = BEST[kind]
	var burn: float = BURN_AT[kind]
	var event := ""

	if heat > best * 0.5:
		# ниже полудороги до рабочего жара ничего не происходит вовсе
		var rate: float = clampf((heat - best * 0.5) / best, 0.0, 1.6)
		cook = clampf(cook + delta * rate * 0.055, 0.0, 1.0)
		if cook >= 1.0 and not announced:
			announced = true
			event = "готово"
	if heat > burn:
		char_level = clampf(char_level + delta * (heat - burn) / burn * 0.22, 0.0, 1.0)
		if char_level >= 1.0 and announced:
			announced = false
			event = "сгорело"

	_steam.emitting = cook > 0.08 and cook < 1.0 and heat > best * 0.6
	if _steam.emitting:
		_steam.amount_ratio = clampf(0.25 + cook * 0.75, 0.1, 1.0)

	var shade := _base.lerp(Color(0.34, 0.2, 0.09), cook * 0.7 if kind == Kind.BREAD else 0.0)
	shade = shade.lerp(Color(0.06, 0.05, 0.05), char_level)
	(_mi.material_override as StandardMaterial3D).albedo_color = shade
	return event


func label() -> String:
	if char_level > 0.5:
		return "уголёк"
	if cook >= 1.0:
		return "готово"
	return "%d%%" % roundi(cook * 100.0)


static func _make_steam() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 1.5
	p.randomness = 0.5
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-0.5, -0.1, -0.5), Vector3(1.0, 1.4, 1.0))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.045
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.14
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0.05, 0.3, 0)
	pm.damping_min = 0.0
	pm.damping_max = 0.1
	pm.scale_min = 0.05
	pm.scale_max = 0.14
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(0.95, 0.95, 0.94, 0.3), Color(0.9, 0.9, 0.9, 0.0),
	])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.draw_pass_1 = quad

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_texture = Mats.soft_dot()
	p.material_override = m
	return p
