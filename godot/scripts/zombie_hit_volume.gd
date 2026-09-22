# Exact skinned convex hit volume, evaluated only by a shot. It creates no
# per-bone scene nodes or moving physics areas, and follows the full-rate rig.
extends RefCounted

var rig: Skeleton3D
var bone := 0
var bone_name := ""
var shape: ConvexPolygonShape3D
var planes: Array[Plane] = []
var bounds: AABB
var center := Vector3.ZERO
var owner: CharacterBody3D
var _cached_pose := Transform3D()
var _cached_bounds: AABB
var _inverse := Transform3D()
var _has_pose := false
var _has_inverse := false

func configure(skeleton: Skeleton3D, index: int, hull: ConvexPolygonShape3D, hull_planes: Array[Plane], zombie: CharacterBody3D) -> void:
	rig = skeleton
	bone = index
	bone_name = rig.get_bone_name(bone)
	shape = hull
	planes = hull_planes
	owner = zombie
	set_meta("zombie", zombie)
	set_meta("headshot", "head" in bone_name.to_lower())
	bounds = hull.get_meta("shot_bounds")
	center = hull.get_meta("shot_center")

func get_rid() -> RID:
	return owner.get_rid()

func world_transform() -> Transform3D:
	return rig.global_transform * rig.get_bone_global_pose(bone)

func to_global(point: Vector3) -> Vector3:
	return world_transform() * point

func intersect(from: Vector3, to: Vector3, inside: bool) -> Dictionary:
	var pose := world_transform()
	if not _has_pose or pose != _cached_pose:
		_cached_pose = pose
		_cached_bounds = pose * bounds
		_has_pose = true
		_has_inverse = false
	# Most bones miss. A world-space box avoids an inverse transform for each
	# one, and repeated rays share work while the actual bone pose is unchanged.
	if not _cached_bounds.intersects_segment(from, to) and not _cached_bounds.has_point(from): return {}
	if not _has_inverse:
		_inverse = pose.affine_inverse()
		_has_inverse = true
	var local_from := _inverse * from
	var local_to := _inverse * to
	if not bounds.intersects_segment(local_from, local_to) and not bounds.has_point(local_from): return {}
	var result := Geometry3D.segment_intersects_convex(local_from, local_to, planes)
	if result.is_empty():
		if not inside or not bounds.has_point(local_from): return {}
		for plane in planes:
			if plane.distance_to(local_from) > 0.00001: return {}
		return {"position": from, "normal": Vector3.ZERO, "collider": self, "rid": get_rid(), "shape": bone}
	return {"position": pose * result[0], "normal": (_inverse.basis.transposed() * result[1]).normalized(), "collider": self, "rid": get_rid(), "shape": bone}
