extends SceneTree

class Receiver:
	extends RefCounted
	var received: Array = []
	func apply_snapshot(data: Dictionary, _initial: bool) -> void: received.append(data)

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	var net := root.get_node("NetSession")
	var receiver := Receiver.new()
	net.world = receiver
	net.epoch = 42
	var random := RandomNumberGenerator.new()
	random.seed = 971
	var payload := PackedByteArray()
	for i in 18000: payload.append(random.randi_range(0, 255))
	var data := {"test": payload, "position": Vector3(1, 2, 3), "counter": 99}
	var raw := var_to_bytes(data)
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var count := ceili(float(packed.size()) / net.SNAPSHOT_CHUNK)
	check(count > 1, "Payload needs several packets")
	for i in range(count-1, -1, -1):
		net._snapshot_part(42, 1, i, count, raw.size(), packed.slice(i*net.SNAPSHOT_CHUNK, (i+1)*net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 1 and receiver.received[0] == data, "Reverse arrival reassembles exact data")
	for i in count:
		net._snapshot_part(42, 1, i, count, raw.size(), packed.slice(i*net.SNAPSHOT_CHUNK, (i+1)*net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 1, "Duplicate snapshot does not apply twice")
	for i in range(1, count):
		net._snapshot_part(42, 2, i, count, raw.size(), packed.slice(i*net.SNAPSHOT_CHUNK, (i+1)*net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 1, "Missing fragment never applies partial state")
	for i in count:
		net._snapshot_part(42, 3, i, count, raw.size(), packed.slice(i*net.SNAPSHOT_CHUNK, (i+1)*net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 2, "New complete snapshot recovers after packet loss")
	net._snapshot_part(42, 2, 0, count, raw.size(), packed.slice(0, net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 2, "Late older snapshot cannot roll back state")
	net._snapshot_part(41, 4, 0, count, raw.size(), packed.slice(0, net.SNAPSHOT_CHUNK))
	check(not net._snapshot_parts.has(4), "Previous round packets are ignored")
	net._snapshot_part(42, 4, 0, 65, raw.size(), packed.slice(0, net.SNAPSHOT_CHUNK))
	net._snapshot_part(42, 4, 0, count, 99999999, packed.slice(0, net.SNAPSHOT_CHUNK))
	check(not net._snapshot_parts.has(4), "Invalid fragment and allocation limits are rejected")
	for seq in range(4, 25):
		net._snapshot_part(42, seq, 0, count, raw.size(), packed.slice(0, net.SNAPSHOT_CHUNK))
	check(net._snapshot_parts.size() <= 3, "Incomplete snapshot memory stays bounded")
	net._world_state(42, 25, data, true)
	for i in count:
		net._snapshot_part(42, 24, i, count, raw.size(), packed.slice(i*net.SNAPSHOT_CHUNK, (i+1)*net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 3 and net._snapshot_parts.is_empty(), "Reliable world state cannot be overwritten by older movement packets")
	for i in range(count - 1, 0, -1):
		net._initial_part(42, 26, i, count, raw.size(), packed.slice(i * net.SNAPSHOT_CHUNK, (i + 1) * net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 3, "Partial initial state never starts loading")
	net._initial_part(42, 26, 0, count, raw.size(), packed.slice(0, net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 4 and receiver.received.back() == data, "Chunked reliable initial state reconstructs the complete world")
	net._initial_part(42, 26, 0, count, raw.size(), packed.slice(0, net.SNAPSHOT_CHUNK))
	check(receiver.received.size() == 4 and net._initial_parts.is_empty(), "Duplicate initial transfer cannot reload the world")
	net._initial_part(42, 27, 0, 9999, raw.size(), packed.slice(0, net.SNAPSHOT_CHUNK))
	check(net._initial_parts.is_empty(), "Oversized initial transfer is rejected")
	await process_frame
	await process_frame
	net.world = null
	print("NETWORK_PACKETS_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
