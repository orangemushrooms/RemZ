extends RefCounted

# Shared by visible dispersion, solo ballistics and host-controlled fire.
const HIP_FACTOR := 1.7
const ADS_FACTOR := 0.5
const BLOOM_RECOVERY := 1.15
const KICK_RECOVERY := 5.0

static func spread(base: float, ads: float, speed: float, vertical_speed: float, bloom: float, precision: float) -> float:
	var movement := clampf(speed / 4.5, 0, 2.5)
	var cone := base * lerpf(HIP_FACTOR, ADS_FACTOR, ads)
	cone += lerpf(0.004, 0.0012, ads)
	cone += movement * lerpf(0.012, 0.007, ads)
	if absf(vertical_speed) > 2: cone += 0.035
	cone += (base * 1.2 + 0.012) * bloom
	return cone * maxf(0.25, precision)

static func sample_direction(forward: Vector3, right: Vector3, up: Vector3, cone: float, radial: float, angle: float) -> Vector3:
	# Uniform disk on the aim plane, independent of world orientation.
	var radius := sqrt(clampf(radial, 0, 1)) * cone
	return (forward + (right * cos(angle) + up * sin(angle)) * radius).normalized()
