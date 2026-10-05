extends SceneTree
const Checkpoint = preload("res://scripts/expedition_checkpoint.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func run() -> void:
	check(Checkpoint._compatible({"accepted": {}}, {"accepted": {"arrival": true}}), "An older checkpoint may predate quest acceptance")
	check(Checkpoint._compatible({"accepted": {}}, {"accepted": {"arrival": true}, "baseline": {"arrival": {"kills": 0}}}), "A checkpoint before the first quest does not need its later baseline")
	check(Checkpoint._compatible({"stocks": {1: {"flowers": {}, "drinks": {}}}}, {"stocks": {1: {"flowers": {"yarrow": 2}, "drinks": {"clear": 1}}, 2: {"flowers": {}, "drinks": {}}}}), "Optional inventory entries and lazily created peer stocks may be absent")
	check(not Checkpoint._compatible({"stocks": 2}, {"stocks": {}}), "A collection still requires the correct data type")
	check(not Checkpoint._compatible({"people": {1: {"accepted": {}, "discovered": "bad"}}}, {"people": {1: {"accepted": {}, "discovered": false}}}), "Known record fields retain strict value types")
	check(not Checkpoint._compatible({"people": {1: {"accepted": {}}}}, {"people": {1: {"accepted": {}, "discovered": false}}}), "Required player record fields cannot disappear")
	var mapping := {2: 55, 3: 66}
	var source := {"support:2:2:heal:3:2": true, "support:2:3:tower:2:3": true, "support-budget:2:3": 4, "outpost-restock:site_2:3:2": true, "sniper:2": true, "delivery:2": true, "operation:3": true}
	var remapped := Checkpoint._reward_keys(source, mapping)
	check(remapped.has("support:55:2:heal:66:2"), "Healing reward remaps both peers while preserving wave and time")
	check(remapped.has("support:55:3:tower:2:3"), "Tower IDs are never mistaken for peer IDs")
	check(remapped.has("support-budget:55:3") and remapped["support-budget:55:3"] == 4, "Support budgets keep their wave and count")
	check(remapped.has("outpost-restock:site_2:66:2") and remapped.has("sniper:55"), "Outpost and sniper reward owners follow the joining player")
	check(remapped.has("delivery:2") and remapped.has("operation:3"), "Delivery counts and operation waves remain unchanged")
	var quests := Checkpoint._reward_keys({"2:expedition:sniper:2": true, "team:expedition:sniper:3": true, "2:expedition:operation:3": true, "3:planes:range": true, "mission-complete": true}, mapping, true)
	check(quests.has("55:expedition:sniper:55") and quests.has("team:expedition:sniper:66"), "Nested expedition quest rewards remap only their peer fields")
	check(quests.has("55:expedition:operation:3") and quests.has("66:planes:range") and quests.has("mission-complete"), "Quest reward replay protection preserves non-player identifiers")
	print("CHECKPOINT_SCHEMA_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
