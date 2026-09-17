class_name Kettle
extends RigidBody3D

## Чайник на плите. Греется от кладки, на которой стоит, парит носиком и
## закипев свистит. Физику не отключаем: если печку разнесёт, он свалится.

const R := 0.086
const H := 0.132

var water := 20.0
var boiled := false

var _steam: GPUParticles3D


static func create() -> Kettle:
	var k := Kettle.new()
	k.name = "Kettle"
	k.mass = 1.4
	# без этого чайник не видит кирпича и проваливается сквозь плиту
	k.collision_layer = Piece.LAYER_SOLID
	k.collision_mask = Piece.LAYER_WORLD | Piece.LAYER_SOLID
	k.continuous_cd = true
	k.angular_damp = 1.2
	k.physics_material_override = PhysicsMaterial.new()
	k.physics_material_override.friction = 0.9

	var body_mat := Mats.metal(Vector3(1.2, 1.2, 1.2))
	var dark := Mats.metal(Vector3(0.55, 0.55, 0.55))

	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = R * 0.82
	bm.bottom_radius = R
	bm.height = H
	bm.radial_segments = 24
	body.mesh = bm
	body.material_override = body_mat
	k.add_child(body)

	var lid := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = R * 0.42
	lm.bottom_radius = R * 0.62
	lm.height = 0.026
	lm.radial_segments = 20
	lid.mesh = lm
	lid.material_override = dark
	lid.position = Vector3(0, H * 0.5 + 0.012, 0)
	k.add_child(lid)

	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.016
	km.height = 0.03
	knob.mesh = km
	knob.material_override = dark
	knob.position = Vector3(0, H * 0.5 + 0.038, 0)
	k.add_child(knob)

	# носик: конус, задранный вверх от борта
	var spout := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.012
	sm.bottom_radius = 0.026
	sm.height = 0.13
	sm.radial_segments = 14
	spout.mesh = sm
	spout.material_override = body_mat
	spout.position = Vector3(R * 0.78, 0.03, 0)
	spout.rotation_degrees = Vector3(0, 0, -52.0)
	k.add_child(spout)

	# дужка
	var bail := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = R * 0.72
	tm.outer_radius = R * 0.78
	tm.rings = 24
	tm.ring_segments = 8
	bail.mesh = tm
	bail.material_override = dark
	bail.position = Vector3(0, H * 0.5 + 0.03, 0)
	bail.rotation_degrees = Vector3(90.0, 0, 0)
	k.add_child(bail)

	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = R
	shape.height = H
	cs.shape = shape
	k.add_child(cs)

	k._steam = k._make_steam()
	k._steam.position = Vector3(R * 1.22, 0.115, 0)
	k.add_child(k._steam)
	return k


## Куда бьёт струя пара — на конце носика, в мировых координатах.
func spout_tip() -> Vector3:
	return global_transform * Vector3(R * 1.22, 0.115, 0)


func set_steam(amount: float) -> void:
	_steam.emitting = amount > 0.02
	if _steam.emitting:
		_steam.amount_ratio = clampf(amount, 0.05, 1.0)


func _make_steam() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 46
	p.amount_ratio = 0.2
	p.lifetime = 1.5
	p.preprocess = 0.4
	p.randomness = 0.5
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.visibility_aabb = AABB(Vector3(-0.5, -0.1, -0.5), Vector3(1.0, 1.6, 1.0))
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.012
	pm.direction = Vector3(0.55, 1.0, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.45
	pm.initial_velocity_max = 0.95
	pm.gravity = Vector3(0, 0.55, 0)
	# почти без торможения: иначе струя не разлетается, а копится комом у носика
	pm.damping_min = 0.0
	pm.damping_max = 0.12
	pm.scale_min = 0.022
	pm.scale_max = 0.075
	pm.scale_curve = _grow()
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.28
	pm.turbulence_noise_scale = 2.2
	pm.color_ramp = _ramp()
	p.process_material = pm

	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# без keep_scale каждая частица рисуется в размер квада, то есть в метр
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Mats.puff_tex(256)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	qm.material = m
	p.draw_pass_1 = qm
	return p


static func _grow() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(0.95, 0.95, 0.96, 0.0),
		Color(0.95, 0.95, 0.96, 0.46),
		Color(0.92, 0.93, 0.95, 0.2),
		Color(0.9, 0.91, 0.94, 0.0),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t
