extends RefCounted

# Match the host's acknowledgement to the predicted position at send time,
# not to the player's newer position when the reply arrives.
const HISTORY_LIMIT := 256
const CORRECTION_DISTANCE := 0.35
const TELEPORT_DISTANCE := 4.0
var sequence := 0
var acknowledged := 0
var history: Dictionary = {}

func record(position: Vector3) -> int:
	sequence += 1
	history[sequence] = position
	while history.size() > HISTORY_LIMIT:
		history.erase(history.keys()[0])
	return sequence

func reconcile(server_position: Vector3, ack: int, current: Vector3, initial := false) -> Vector3:
	if initial:
		history.clear()
		acknowledged = maxi(acknowledged, ack)
		return server_position
	if ack <= acknowledged or ack <= 0 or ack > sequence:
		return current
	acknowledged = ack
	# A reply older than the bounded history needs an authoritative reset.
	var predicted: Vector3 = history.get(ack, current)
	var error := server_position - predicted
	var corrected := current
	if not history.has(ack) or error.length() > TELEPORT_DISTANCE:
		corrected = server_position
	elif error.length() > CORRECTION_DISTANCE:
		corrected += error
	var applied := corrected - current
	for pending in history.keys():
		if pending <= ack:
			history.erase(pending)
		else:
			# Later in-flight poses must not apply this correction a second time.
			history[pending] += applied
	return corrected
