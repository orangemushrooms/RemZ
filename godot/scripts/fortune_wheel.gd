# One wheel of fortune (27 Sep 2026, see fortune_wheels.gd): the Meshy stand (fortune_wheel.glb, oak easel
# with a cast iron hub; its own painted disc and flapper stay hidden behind / are cut away) carrying a
# procedural disc - 24 segments painted after FortuneWheels.SEGMENTS with wood grain and chipped paint, brass
# separators and pegs, icons and labels - a leather flapper that every peg pushes aside and a warm spot.
# The disc turns clockwise seen from the front. `angle` is that rotation; the segment under the flapper is
# floor(wrap(-angle) / segment), so the segments pass the flapper in falling order.
class_name FortuneWheel
extends Node3D

const SEGMENT_COUNT := 24
const SEGMENT := TAU / SEGMENT_COUNT
const STAND_HEIGHT := 1.9
const FLAP_MAX := 0.5          # radians a peg pushes the flapper aside
const FLAP_ZONE := 0.34        # share of a segment before the peg in which the flapper rides on it
const EASE_POWER := 2.6        # friction: the wheel loses speed faster at the start than a pure brake
# Where the disc sits on the Meshy stand, measured by `node tools/fortune_wheel_fit.mjs` (disc facing -z in
# the GLB, centre y 0.295 of a 1.898 tall model, radius 0.577, painted face at z -0.347): after the height
# fit and STAND_YAW the face looks along +z. HUB is the centre of our face, 5 mm in front of the painted one
# so that it hides it; the A-frame legs stay 5-10 cm in front of it, clear of the 5.5 cm pegs.
const STAND_YAW := PI
const HUB := Vector3(0.0, 1.246, 0.351)
const RADIUS := 0.582

var wheels: FortuneWheels
var index := 0
var radius := RADIUS
var hub := HUB
var disc: Node3D
var flapper: Node3D
var stand: Node3D
var angle := 0.0
var serial := 0
var a0 := 0.0
var a1 := 0.0
var duration := 0.0
var elapsed := 0.0
var spinning := false
var reveal: Array = []            # [icon, text, tier] of the current spin, shown when it stops
var flash := 0.0                  # the win glow on the landed segment
var _flap := 0.0
var _flap_v := 0.0
var _last_peg := 0
var _tick: AudioStreamPlayer3D
var _fx: AudioStreamPlayer3D
var _highlight: MeshInstance3D
var _highlight_mat: StandardMaterial3D
var _pop: Sprite3D
var _pop_label: Label3D
var _pop_t := -1.0
var _spot: SpotLight3D
var _meshy_stand := false

static var _face_material: ShaderMaterial
static var _brass: StandardMaterial3D
static var _iron: StandardMaterial3D
static var _oak: StandardMaterial3D
static var _leather: StandardMaterial3D
static var _ticks: Array[AudioStream] = []

const FACE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grain : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D wear : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float radius = 0.6;
uniform float glow = 0.0;
varying vec2 local_xy;
void vertex() { local_xy = VERTEX.xy; }
void fragment() {
	float r = length(local_xy) / radius;
	float g = texture(grain, vec2(local_xy.x * 0.9, local_xy.y * 7.0)).r;
	float fine = texture(grain, local_xy * 9.0).r;
	float w = texture(wear, local_xy * 2.2).r;
	bool gold = COLOR.a < 0.5;
	vec3 paint = COLOR.rgb * mix(0.88, 1.05, g) * mix(0.96, 1.03, fine);
	// a few paint chips, nearly all near the rim where the hands grab the wheel; none on the gold leaf
	float chip = smoothstep(0.9, 0.93, w + 0.07 * smoothstep(0.75, 1.0, r) - 0.06 * (1.0 - r)) * (gold ? 0.0 : 1.0);
	vec3 wood = vec3(0.2, 0.12, 0.07) * mix(0.7, 1.1, g);
	// soot and hand grime darken the rim a little, the varnish yellows the light paint
	paint *= mix(1.0, 0.82, smoothstep(0.8, 1.0, r));
	paint = mix(paint, paint * vec3(1.0, 0.95, 0.82), 0.35);
	ALBEDO = mix(paint, wood, chip);
	METALLIC = gold ? 0.85 : 0.0;
	ROUGHNESS = gold ? 0.32 + 0.2 * fine : mix(0.34, 0.8, chip) + 0.12 * fine;
	SPECULAR = 0.5;
}
"""

static func _materials() -> void:
	if _face_material: return
	_face_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FACE_SHADER
	_face_material.shader = shader
	var grain := NoiseTexture2D.new()
	grain.width = 512
	grain.height = 512
	grain.seamless = true
	var gn := FastNoiseLite.new()
	gn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gn.frequency = 0.02
	gn.fractal_octaves = 4
	grain.noise = gn
	var wear := NoiseTexture2D.new()
	wear.width = 512
	wear.height = 512
	wear.seamless = true
	var wn := FastNoiseLite.new()
	wn.noise_type = FastNoiseLite.TYPE_CELLULAR
	wn.frequency = 0.05
	wn.fractal_octaves = 3
	wear.noise = wn
	_face_material.set_shader_parameter("grain", grain)
	_face_material.set_shader_parameter("wear", wear)
	_face_material.set_shader_parameter("radius", RADIUS)
	_brass = StandardMaterial3D.new()
	_brass.albedo_color = Color(0.76, 0.58, 0.3)
	_brass.metallic = 1.0
	_brass.roughness = 0.38
	_iron = StandardMaterial3D.new()
	_iron.albedo_color = Color(0.13, 0.12, 0.11)
	_iron.metallic = 0.7
	_iron.roughness = 0.6
	_oak = Foliage.pbr("planks", 0.8, Color(0.36, 0.22, 0.13))
	_leather = StandardMaterial3D.new()
	_leather.albedo_color = Color(0.33, 0.18, 0.1)
	_leather.roughness = 0.72
	for k in 3:
		var path := "res://assets/audio/sfx/fortune/tick_%d.wav" % (k + 1)
		if ResourceLoader.exists(path): _ticks.append(load(path))

func build(owner_wheels: FortuneWheels, wheel_index: int) -> void:
	wheels = owner_wheels
	index = wheel_index
	name = "FortuneWheel%d" % wheel_index
	_materials()
	_build_stand()
	disc = Node3D.new()
	disc.name = "Disc"
	disc.position = hub + Vector3(0, 0, 0.0)
	add_child(disc)
	_build_disc()
	_build_flapper()
	_build_light()
	_tick = AudioStreamPlayer3D.new()
	_tick.unit_size = 4.0
	_tick.max_distance = 30.0
	_tick.volume_db = -6.0
	_tick.position = hub + Vector3(0, radius, 0.1)
	add_child(_tick)
	_fx = AudioStreamPlayer3D.new()
	_fx.unit_size = 6.0
	_fx.max_distance = 40.0
	_fx.position = hub + Vector3(0, 0, 0.3)
	add_child(_fx)
	# every wheel starts at its own angle, both stop on a segment centre
	angle = -(wheel_index * 7 + 0.5) * SEGMENT
	a1 = angle
	_apply_angle()

# ------------------------------------------------------------------ geometry
func _build_stand() -> void:
	var main: Node = wheels.main
	stand = main._prop(self, "fortune_wheel", STAND_HEIGHT, "y") if main and main.has_method("_prop") else null
	_meshy_stand = stand != null
	if stand:
		_fit_stand()
		return
	# fallback: an oak easel with a cast iron bearing on top, the disc in front of it
	stand = Node3D.new()
	add_child(stand)
	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 1.45, 0.07)
		leg.mesh = box
		leg.material_override = _oak
		leg.position = Vector3(side * 0.24, 0.68, -0.12)
		leg.rotation.z = side * 0.2
		stand.add_child(leg)
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.07, 1.45, 0.07)
	back.mesh = bb
	back.material_override = _oak
	back.position = Vector3(0, 0.66, -0.42)
	back.rotation.x = 0.35
	stand.add_child(back)
	var foot := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.1, 0.07, 0.8)
	foot.mesh = fb
	foot.material_override = _oak
	foot.position = Vector3(0, 0.035, -0.3)
	stand.add_child(foot)
	var bearing := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.12, 0.16)
	bearing.mesh = bm
	bearing.material_override = _iron
	bearing.position = hub + Vector3(0, -0.02, -0.1)
	stand.add_child(bearing)

# The Meshy stand (its own flapper was cut out of the GLB by fortune_wheel_fit.mjs --cut): turn its wheel to +z.
func _fit_stand() -> void:
	stand.rotation.y = STAND_YAW

func _build_disc() -> void:
	_face_material.set_shader_parameter("radius", radius)
	# the wooden body behind the painted face
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.032
	cyl.radial_segments = 72
	body.mesh = cyl
	body.rotation.x = PI / 2.0
	body.position.z = -0.017
	body.material_override = _oak
	disc.add_child(body)
	var face := MeshInstance3D.new()
	face.mesh = _face_mesh()
	face.material_override = _face_material
	disc.add_child(face)
	# brass band round the edge
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.012
	torus.outer_radius = radius + 0.01
	torus.rings = 96
	torus.ring_segments = 8
	rim.mesh = torus
	rim.rotation.x = PI / 2.0
	rim.scale = Vector3(1, 0.9, 1)
	rim.material_override = _brass
	disc.add_child(rim)
	# brass separators and the pegs on every boundary
	var strip := BoxMesh.new()
	strip.size = Vector3(0.006, radius - 0.1, 0.003)
	var peg := CylinderMesh.new()
	peg.top_radius = 0.0065
	peg.bottom_radius = 0.0075
	peg.height = 0.055
	peg.radial_segments = 10
	for k in SEGMENT_COUNT:
		var theta := k * SEGMENT
		var dir := Vector2(sin(theta), cos(theta))
		var s := MeshInstance3D.new()
		s.mesh = strip
		s.material_override = _brass
		var mid := (radius - 0.1) * 0.5 + 0.085
		s.position = Vector3(dir.x * mid, dir.y * mid, 0.002)
		s.rotation.z = -theta
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.add_child(s)
		var p := MeshInstance3D.new()
		p.mesh = peg
		p.material_override = _brass
		var pr := radius - 0.03
		p.position = Vector3(dir.x * pr, dir.y * pr, 0.027)
		p.rotation.x = PI / 2.0
		disc.add_child(p)
	# the hub: cast iron boss and a brass cap
	var boss := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.07
	bc.bottom_radius = 0.085
	bc.height = 0.05
	bc.radial_segments = 32
	boss.mesh = bc
	boss.rotation.x = PI / 2.0
	boss.position.z = 0.025
	boss.material_override = _iron
	disc.add_child(boss)
	var cap := MeshInstance3D.new()
	var cc := SphereMesh.new()
	cc.radius = 0.035
	cc.height = 0.04
	cap.mesh = cc
	cap.position.z = 0.05
	cap.material_override = _brass
	disc.add_child(cap)
	_build_marks()
	# the glow over the landed segment
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_highlight_mat.albedo_color = Color(1.0, 0.8, 0.4, 0.0)
	_highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight = MeshInstance3D.new()
	_highlight.mesh = _wedge_mesh(0.09, radius - 0.01)
	_highlight.material_override = _highlight_mat
	_highlight.position.z = 0.004
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.hide()
	disc.add_child(_highlight)

# Painted segments as one triangle mesh; colour per vertex, alpha 0 marks gold leaf.
func _face_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 8
	var inner := 0.06
	for k in SEGMENT_COUNT:
		var look: Dictionary = FortuneWheels.LOOK[FortuneWheels.SEGMENTS[k]]
		var colour: Color = look.color
		colour.a = 0.0 if look.get("gold", false) else 1.0
		for j in steps:
			var t0 := (k + float(j) / steps) * SEGMENT
			var t1 := (k + float(j + 1) / steps) * SEGMENT
			var quad := [Vector2(sin(t0), cos(t0)) * inner, Vector2(sin(t0), cos(t0)) * radius,
				Vector2(sin(t1), cos(t1)) * radius, Vector2(sin(t1), cos(t1)) * inner]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for v: int in tri:
					st.set_color(colour)
					st.set_normal(Vector3(0, 0, 1))
					st.set_uv(quad[v] / radius * 0.5 + Vector2(0.5, 0.5))
					st.add_vertex(Vector3(quad[v].x, quad[v].y, 0.0))
	return st.commit()

func _wedge_mesh(inner: float, outer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 8
	for j in steps:
		var t0 := float(j) / steps * SEGMENT
		var t1 := float(j + 1) / steps * SEGMENT
		var quad := [Vector2(sin(t0), cos(t0)) * inner, Vector2(sin(t0), cos(t0)) * outer,
			Vector2(sin(t1), cos(t1)) * outer, Vector2(sin(t1), cos(t1)) * inner]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for v: int in tri:
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(Vector3(quad[v].x, quad[v].y, 0.0))
	return st.commit()

# Icons near the rim, labels towards the hub, both reading outwards along the radius.
func _build_marks() -> void:
	for k in SEGMENT_COUNT:
		var kind: String = FortuneWheels.SEGMENTS[k]
		var look: Dictionary = FortuneWheels.LOOK[kind]
		var theta := (k + 0.5) * SEGMENT
		var dir := Vector2(sin(theta), cos(theta))
		var dark: bool = look.color.get_luminance() > 0.55 or look.get("gold", false)
		if not str(look.icon).is_empty():
			var icon := Sprite3D.new()
			icon.texture = ItemIcons.texture(look.icon)
			var size := icon.texture.get_size()
			var wide := size.x > size.y * 1.3
			# a long gun lies along the radius, a round item stands upright towards the rim
			var along := radius * (0.3 if wide else 0.16)
			icon.pixel_size = along / maxf(1.0, size.x if wide else size.y)
			icon.shaded = true
			icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var r := radius * (0.72 if wide else 0.78)
			icon.position = Vector3(dir.x * r, dir.y * r, 0.006)
			icon.rotation.z = -theta + (PI / 2.0 if wide else 0.0)
			icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			disc.add_child(icon)
		if not str(look.text).is_empty():
			var label := Label3D.new()
			label.text = look.text
			label.font_size = 56
			label.pixel_size = 0.0011 * radius / 0.6
			label.outline_size = 4
			label.modulate = Color(0.12, 0.07, 0.04) if dark else Color(0.98, 0.94, 0.84)
			label.outline_modulate = Color(0, 0, 0, 0.0) if dark else Color(0.1, 0.03, 0.02, 0.8)
			label.shaded = true
			label.double_sided = false
			label.width = 400
			var r := radius * (0.42 if not str(look.icon).is_empty() else 0.62)
			label.position = Vector3(dir.x * r, dir.y * r, 0.007)
			# text runs along the radius, its baseline towards the next segment clockwise
			label.rotation.z = -theta + PI / 2.0
			label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			disc.add_child(label)

func _build_flapper() -> void:
	# a leather tongue hanging from the stand's iron hook into the pegs (the fallback stand gets a bracket)
	var pivot_y := radius + 0.055
	flapper = Node3D.new()
	flapper.position = hub + Vector3(0, pivot_y, 0.034)
	add_child(flapper)
	if _meshy_stand:
		_build_tongue()
		return
	var bracket := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.05, 0.02, 0.13)
	bracket.mesh = bb
	bracket.material_override = _iron
	bracket.position = hub + Vector3(0, pivot_y + 0.01, -0.02)
	add_child(bracket)
	var post := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.04, 0.16, 0.02)
	post.mesh = pb
	post.material_override = _iron
	post.position = hub + Vector3(0, pivot_y - 0.06, -0.075)
	add_child(post)
	_build_tongue()

func _build_tongue() -> void:
	var tongue := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.16
	var shape := [Vector2(-0.018, 0.0), Vector2(0.018, 0.0), Vector2(0.022, -length * 0.62), Vector2(0.0, -length), Vector2(-0.022, -length * 0.62)]
	for tri in [[0, 1, 2], [0, 2, 4], [4, 2, 3]]:
		for v: int in tri:
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(shape[v].x, shape[v].y, 0.0))
	tongue.mesh = st.commit()
	var mat: StandardMaterial3D = _leather.duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tongue.material_override = mat
	flapper.add_child(tongue)
	var rivet := MeshInstance3D.new()
	var rv := SphereMesh.new()
	rv.radius = 0.008
	rv.height = 0.01
	rivet.mesh = rv
	rivet.material_override = _brass
	rivet.position = Vector3(0, -0.008, 0.004)
	flapper.add_child(rivet)

func _build_light() -> void:
	_spot = SpotLight3D.new()
	_spot.light_color = Color(1.0, 0.8, 0.55)
	_spot.light_energy = 2.2
	_spot.spot_range = 4.5
	_spot.spot_angle = 30.0
	_spot.spot_attenuation = 0.8
	_spot.shadow_enabled = true
	_spot.position = hub + Vector3(0, 1.1, 1.3)
	add_child(_spot)
	_spot.look_at_from_position(_spot.position, hub, Vector3.UP)
	_pop = Sprite3D.new()
	_pop.pixel_size = 0.0014
	_pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pop.no_depth_test = false
	_pop.position = hub + Vector3(0, 0, 0.35)
	_pop.hide()
	add_child(_pop)
	_pop_label = Label3D.new()
	_pop_label.font_size = 48
	_pop_label.pixel_size = 0.002
	_pop_label.outline_size = 10
	_pop_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pop_label.modulate = Color(1.0, 0.9, 0.55)
	_pop_label.outline_modulate = Color(0.15, 0.05, 0.0)
	_pop_label.position = hub + Vector3(0, 0.06, 0.52)
	_pop_label.hide()
	add_child(_pop_label)

# Where a player stands to spin this wheel (world space).
func stand_point() -> Vector3:
	return global_transform * Vector3(0, 0, 0.95)

# ------------------------------------------------------------------ motion
static func segment_at(disc_angle: float) -> int:
	return int(floor(wrapf(-disc_angle, 0.0, TAU) / SEGMENT)) % SEGMENT_COUNT

# Host / solo: start a spin that ends on `segment` at `fraction` of it (in passing order).
func start(spin_serial: int, segment: int, fraction: float, seconds: float, turns: int, shown: Array) -> void:
	var goal := -(segment + (1.0 - fraction)) * SEGMENT
	# `fraction` counts in passing order (falling angle under the flapper), the angle within the segment rises
	var delta := wrapf(goal - angle, 0.0, TAU) + turns * TAU
	_begin(spin_serial, angle, angle + delta, seconds, 0.0, shown)

func _begin(spin_serial: int, from: float, to: float, seconds: float, already: float, shown: Array) -> void:
	serial = spin_serial
	a0 = from
	a1 = to
	duration = seconds
	elapsed = already
	reveal = shown
	spinning = elapsed < duration
	flash = 0.0
	_highlight.hide()
	_pop.hide()
	_pop_label.hide()
	_pop_t = -1.0
	_last_peg = int(floor(a0 / SEGMENT))
	if spinning and already < 0.3:
		_play(_fx, "coin", -4.0)
	if not spinning: _finish(false)

func snapshot() -> Array:
	return [serial, a0, a1, duration, elapsed, reveal]

func apply_snapshot(s: Array) -> void:
	if s.size() < 6: return
	if int(s[0]) == serial: return
	var shown: Array = s[5] if s[5] is Array else []
	# a client joining late sees the wheel standing where it stopped
	_begin(int(s[0]), float(s[1]), float(s[2]), float(s[3]), float(s[4]), shown)
	if not spinning:
		angle = a1
		_apply_angle()

func _process(delta: float) -> void:
	if spinning:
		elapsed = minf(duration, elapsed + delta)
		var u := elapsed / maxf(duration, 0.001)
		angle = a0 + (a1 - a0) * (1.0 - pow(1.0 - u, EASE_POWER))
		var peg := int(floor(angle / SEGMENT))
		if peg != _last_peg:
			# one audible tick per frame at most; quieter while the pegs blur past
			var speed := (a1 - a0) * EASE_POWER * pow(1.0 - u, EASE_POWER - 1.0) / maxf(duration, 0.001)
			_play(_tick, "tick", lerpf(-2.0, -12.0, clampf(speed / 14.0, 0.0, 1.0)), randf_range(0.92, 1.1))
			_last_peg = peg
		if elapsed >= duration:
			spinning = false
			angle = a1
			_finish(true)
		_apply_angle()
	_update_flapper(delta)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		_highlight_mat.albedo_color.a = 0.35 * (0.5 + 0.5 * sin(flash * 14.0)) * minf(1.0, flash)
		if flash <= 0.0: _highlight.hide()
	if _pop_t >= 0.0:
		_pop_t += delta
		var grow := minf(1.0, _pop_t / 0.35)
		var fade := clampf(4.0 - _pop_t, 0.0, 1.0)
		_pop.scale = Vector3.ONE * (0.4 + 0.6 * grow) * (1.0 + 0.05 * sin(_pop_t * 5.0))
		_pop.position = hub + Vector3(0, 0.3 + _pop_t * 0.03, 0.5)
		_pop.modulate.a = fade
		_pop_label.modulate.a = fade
		_pop_label.outline_modulate.a = fade
		if _pop_t > 4.0:
			_pop_t = -1.0
			_pop.hide()
			_pop_label.hide()

func _apply_angle() -> void:
	disc.rotation.z = -angle

# The flapper rides up on each peg that comes round and snaps back on a damped spring once it slips past.
func _update_flapper(delta: float) -> void:
	var inside := fposmod(-angle, SEGMENT) / SEGMENT   # 1 -> 0 while a segment passes; 0 = on the peg
	var push := FLAP_MAX * clampf(1.0 - inside / FLAP_ZONE, 0.0, 1.0) if inside < FLAP_ZONE else 0.0
	if push >= _flap:
		_flap = push
		_flap_v = 0.0
	else:
		_flap_v += (-_flap * 420.0 - _flap_v * 11.0) * delta
		_flap += _flap_v * delta
		_flap = maxf(_flap, push)
	# the pegs move clockwise past the top, so they push the tongue towards +x
	flapper.rotation.z = _flap

func _finish(audible: bool) -> void:
	var kind: String = str(reveal[2]) if reveal.size() > 2 else ""
	var segment := segment_at(angle)
	_highlight.rotation.z = -segment * SEGMENT
	_highlight.show()
	flash = 3.0 if kind != "nothing" else 0.0
	if kind == "nothing": _highlight.hide()
	if not audible: return
	if kind.begins_with("weapon"): _play(_fx, "jackpot", -2.0)
	elif kind == "nothing": _play(_fx, "lose", -8.0)
	else: _play(_fx, "win", -6.0)
	if reveal.size() > 1 and kind != "nothing":
		_pop.texture = ItemIcons.texture(str(reveal[0])) if not str(reveal[0]).is_empty() else null
		_pop.visible = _pop.texture != null
		if _pop.texture: _pop.pixel_size = 0.38 / maxf(1.0, float(_pop.texture.get_width()))
		_pop_label.text = str(reveal[1])
		_pop_label.modulate = Color(1.0, 0.82, 0.3) if kind.begins_with("weapon") else Color(0.98, 0.94, 0.84)
		_pop_label.show()
		_pop_t = 0.0

func _play(player: AudioStreamPlayer3D, sound: String, db: float, pitch := 1.0) -> void:
	var stream: AudioStream = null
	if sound == "tick":
		if _ticks.is_empty(): return
		stream = _ticks[randi() % _ticks.size()]
	else:
		var path := "res://assets/audio/sfx/fortune/%s.wav" % sound
		if not ResourceLoader.exists(path): return
		stream = load(path)
	if sound == "tick" and player.playing and player.get_playback_position() < 0.03: return
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = pitch
	player.play()
