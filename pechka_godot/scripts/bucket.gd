class_name Bucket
extends RigidBody3D

## Ведро. Пустое — жестянка, полное — двенадцать килограммов, которые нужно
## донести до печки. Воду набирают из бочки, выплёскивают по прицелу.

const R := 0.16
const H := 0.3

var water := 0.0                ## 0 — пустое, 1 — полное

var _disc: MeshInstance3D


static func create() -> Bucket:
	var b := Bucket.new()
	b.name = "Bucket"
	b.mass = 2.2
	b.collision_layer = Piece.LAYER_SOLID
	b.collision_mask = Piece.LAYER_WORLD | Piece.LAYER_SOLID
	b.physics_material_override = PhysicsMaterial.new()
	b.physics_material_override.friction = 0.9
	b.angular_damp = 1.2
	b.set_meta("carry", true)

	var metal := Mats.metal(Vector3(1.1, 1.1, 1.1))
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R
	cm.bottom_radius = R * 0.82
	cm.height = H
	cm.radial_segments = 24
	body.mesh = cm
	body.material_override = metal
	b.add_child(body)

	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = R - 0.012
	rm.outer_radius = R + 0.008
	rm.rings = 20
	rm.ring_segments = 8
	rim.mesh = rm
	rim.material_override = Mats.metal(Vector3(1.6, 1.6, 1.6))
	rim.position = Vector3(0, H * 0.5, 0)
	b.add_child(rim)

	var bail := MeshInstance3D.new()
	var bm := TorusMesh.new()
	bm.inner_radius = R - 0.008
	bm.outer_radius = R + 0.002
	bm.rings = 18
	bm.ring_segments = 6
	bail.mesh = bm
	bail.material_override = rim.material_override
	bail.position = Vector3(0, H * 0.5 + 0.06, 0)
	bail.rotation_degrees = Vector3(90, 0, 0)
	b.add_child(bail)

	b._disc = MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = R - 0.012
	dm.bottom_radius = R - 0.012
	dm.height = 0.006
	dm.radial_segments = 20
	b._disc.mesh = dm
	var w := StandardMaterial3D.new()
	w.albedo_color = Color(0.1, 0.15, 0.15)
	w.roughness = 0.03
	w.metallic = 0.25
	w.metallic_specular = 0.95
	b._disc.material_override = w
	b._disc.visible = false
	b.add_child(b._disc)

	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = R
	sh.height = H
	cs.shape = sh
	b.add_child(cs)
	return b


func fill(x: float) -> void:
	water = clampf(x, 0.0, 1.0)
	mass = 2.2 + water * 10.0
	_disc.visible = water > 0.02
	_disc.position = Vector3(0, -H * 0.5 + 0.02 + water * (H - 0.05), 0)
