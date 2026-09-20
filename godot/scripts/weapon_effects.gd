class_name WeaponEffects
extends Node3D

# Shared pool: sustained fire never allocates new particles or materials.
const SMOKE_CAPACITY := 48
const FLASH_SHADER = preload("res://shaders/muzzle_flash.gdshader")
const SMOKE_SHADER = preload("res://shaders/muzzle_smoke.gdshader")
const PROFILES := {
	# Width, length, duration, smoke strength. Suppression-free game weapons.
	"pistol": Vector4(0.085, 0.17, 0.040, 0.65),
	"revolver": Vector4(0.12, 0.25, 0.050, 0.95),
	"smg": Vector4(0.065, 0.15, 0.032, 0.55),
	"ak47": Vector4(0.10, 0.24, 0.045, 0.85),
	"shotgun": Vector4(0.15, 0.31, 0.055, 1.15),
	"marksman": Vector4(0.13, 0.30, 0.055, 1.0),
	"lmg": Vector4(0.12, 0.26, 0.040, 0.9),
	"breacher": Vector4(0.17, 0.34, 0.060, 1.2),
	"titanbreaker": Vector4(0.22, 0.48, 0.080, 1.5),
}
class Puff:
	var age := 100.0
	var lifetime := 1.0
	var origin := Vector3.ZERO
	var velocity := Vector3.ZERO
	var size := 0.03
	var opacity := 0.4
	var spin := 0.0
	var variation := 0.0

var front: MeshInstance3D
var world_light: OmniLight3D
var hand_light: OmniLight3D
var flash_root: Node3D
var flash_age := 1.0
var flash_duration := 0.04
var heat := 0.0
var ammo_mode := ""
var emitted_puffs := 0
var _camera: Camera3D
var _flash_material: ShaderMaterial
var _axial_material: ShaderMaterial
var _jets: Array[MeshInstance3D] = []
var _smoke: MultiMesh
var _puffs: Array[Puff] = []
var _next := 0
var _tail_time := 0.0
var _muzzle := Transform3D.IDENTITY
var _profile := PROFILES.pistol
var _rng := RandomNumberGenerator.new()

func setup(world_camera: Camera3D) -> void:
	_camera = world_camera
	_rng.randomize()
	flash_root = Node3D.new()
	add_child(flash_root)
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	_axial_material = _flash_material.duplicate()
	_axial_material.set_shader_parameter("axial", true)
	front = _flash_quad(_flash_material)
	front.position.z = -0.012
	for i in 2:
		var jet := _flash_quad(_axial_material)
		jet.basis = Basis(Vector3.FORWARD, i * PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
		_jets.append(jet)
	hand_light = OmniLight3D.new()
	hand_light.light_cull_mask = 2
	hand_light.omni_range = 1.8
	hand_light.light_color = Color(1.0, 0.58, 0.22)
	hand_light.shadow_enabled = false
	flash_root.add_child(hand_light)
	world_light = OmniLight3D.new()
	world_light.omni_range = 5.0
	world_light.light_color = hand_light.light_color
	world_light.shadow_enabled = false
	_camera.add_child(world_light)
	var smoke_draw := MultiMeshInstance3D.new()
	smoke_draw.layers = 2
	smoke_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke = MultiMesh.new()
	_smoke.transform_format = MultiMesh.TRANSFORM_3D
	_smoke.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	quad.material = material
	_smoke.mesh = quad
	_smoke.instance_count = SMOKE_CAPACITY
	_smoke.custom_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	smoke_draw.multimesh = _smoke
	add_child(smoke_draw)
	for i in SMOKE_CAPACITY:
		_puffs.append(Puff.new())
		_hide_puff(i)
	cancel_flash()

func _flash_quad(material: ShaderMaterial) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.layers = 2
	mesh.mesh = QuadMesh.new()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_root.add_child(mesh)
	return mesh

func sync_muzzle(muzzle: Transform3D) -> void:
	_muzzle = muzzle
	flash_root.transform = muzzle
	world_light.transform = muzzle

func fire(weapon_id: String, muzzle: Transform3D, player_velocity: Vector3, flash_scale := 1.0, mode := "") -> void:
	sync_muzzle(muzzle)
	ammo_mode = mode
	_profile = PROFILES.get(weapon_id, PROFILES["ak47"])
	if mode == "fire":
		_profile.y *= 2.8
		_profile.x *= 1.4
		_profile.z = 0.11
	elif mode == "frost":
		_profile.y *= 1.5
		_profile.z = 0.075
	var edge := Color(0.08, 0.45, 1.0) if mode == "frost" else Color(1, 0.1 if mode == "fire" else 0.18, 0.015)
	var core := Color(0.75, 0.95, 1) if mode == "frost" else Color(1, 0.91, 0.57)
	for material in [_flash_material, _axial_material]:
		material.set_shader_parameter("edge_color", edge)
		material.set_shader_parameter("core_color", core)
	hand_light.light_color = edge.lerp(core, 0.35)
	world_light.light_color = hand_light.light_color
	flash_age = 0.0
	_profile.x *= sqrt(flash_scale)
	_profile.y *= sqrt(flash_scale)
	_profile.w *= flash_scale
	flash_duration = _profile.z
	var variation := _rng.randf_range(0.85, 1.15)
	(front.mesh as QuadMesh).size = Vector2.ONE * _profile.x * variation
	front.rotation.z = _rng.randf() * TAU
	front.visible = true
	for jet in _jets:
		(jet.mesh as QuadMesh).size = Vector2(_profile.x * 1.4, _profile.y) * variation
		jet.position.z = -_profile.y * variation * 0.48
		jet.visible = true
	var phase := _rng.randf() * TAU
	_flash_material.set_shader_parameter("phase", phase)
	_axial_material.set_shader_parameter("phase", phase)
	_set_flash(1.0)
	heat = minf(heat + 0.28 * _profile.w, 1.5)
	_tail_time = 0.09
	for i in 3:
		_emit_puff(_profile.w, false, player_velocity)

func cancel_flash() -> void:
	flash_age = 1.0
	heat = 0.0
	front.visible = false
	for jet in _jets:
		jet.visible = false
	_set_flash(0.0)

func _set_flash(value: float) -> void:
	_flash_material.set_shader_parameter("intensity", value)
	_axial_material.set_shader_parameter("intensity", value)
	hand_light.light_energy = value * 2.8 * _profile.w
	world_light.light_energy = value * 5.0 * _profile.w

func advance(delta: float, player_velocity: Vector3) -> void:
	# Called before fire input: even a shot at low FPS gets one rendered flash.
	flash_age += delta
	var brightness := pow(maxf(0.0, 1.0 - flash_age / flash_duration), 0.65)
	_set_flash(brightness)
	if flash_age >= flash_duration:
		front.visible = false
		for jet in _jets:
			jet.visible = false
	heat = maxf(0.0, heat - delta * 0.65)
	_tail_time -= delta
	if heat > 0.08 and _tail_time <= 0.0:
		_emit_puff(minf(heat, 0.7), true, player_velocity)
		_tail_time = 0.09
	var inverse := _camera.global_transform.affine_inverse()
	for i in SMOKE_CAPACITY:
		var puff := _puffs[i]
		if puff.age >= puff.lifetime:
			continue
		puff.age += delta
		if puff.age >= puff.lifetime:
			_hide_puff(i)
			continue
		puff.velocity *= exp(-delta * 2.3)
		puff.velocity += Vector3.UP * delta * 0.18
		puff.origin += puff.velocity * delta
		_draw_puff(i, inverse)

func _emit_puff(strength: float, tail: bool, player_velocity: Vector3) -> void:
	var i := _next
	_next = (_next + 1) % SMOKE_CAPACITY
	emitted_puffs += 1
	var puff := _puffs[i]
	puff.age = 0.0
	puff.lifetime = _rng.randf_range(0.55, 0.9) if not tail else 1.1
	puff.size = (0.025 if tail else 0.045) * strength
	puff.opacity = (0.28 if tail else 0.62) * minf(strength, 1.0)
	puff.spin = _rng.randf() * TAU
	puff.variation = _rng.randf()
	var world_muzzle := _camera.global_transform * _muzzle
	puff.origin = world_muzzle.origin - world_muzzle.basis.z * _rng.randf_range(0.005, 0.035)
	var spread := Vector3(_rng.randf_range(-0.06, 0.06), _rng.randf_range(0.0, 0.08), 0)
	puff.velocity = -world_muzzle.basis.z * (0.08 if tail else _rng.randf_range(0.25, 0.5)) + Vector3.UP * 0.08 + spread + player_velocity * 0.15
	_draw_puff(i, _camera.global_transform.affine_inverse())

func _draw_puff(index: int, inverse: Transform3D) -> void:
	var puff := _puffs[index]
	var age := puff.age / puff.lifetime
	var local := inverse * puff.origin
	if local.z > -0.05 or local.length_squared() > 64.0:
		_hide_puff(index)
		return
	var size := puff.size + age * 0.13
	var basis := Basis(Vector3.BACK, puff.spin + age * 0.45).scaled(Vector3.ONE * size)
	_smoke.set_instance_transform(index, Transform3D(basis, local))
	_smoke.set_instance_custom_data(index, Color(age, puff.opacity * pow(1.0 - age, 1.5), puff.variation, 0))

func _hide_puff(index: int) -> void:
	_smoke.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	_smoke.set_instance_custom_data(index, Color(0, 0, 0, 0))

func active_smoke_count() -> int:
	var count := 0
	for puff in _puffs:
		if puff.age < puff.lifetime:
			count += 1
	return count
