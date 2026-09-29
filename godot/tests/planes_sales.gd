extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)

func has_sale(q: Node, name: String) -> bool:
	for row in q._row_nodes:
		if Lang.text(row[0].text).contains(name): return true
	return false

func run() -> void:
	var game: Node3D = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	game.waves.set_process(false)
	var q: Node = game.progression
	game.player.global_position = Map.ground_pos(-90,40)
	check(q.collect(0) and int(game.brewing.stock(1).flowers.get("golden_yarrow",0))==1,"Collected flower enters the brewing stock")
	game.player.global_position = Map.ground_pos(48,12)
	check(q.collect(10) and int(game.inventory.mushrooms.get("steinpilz",0))==1,"Collected woodland mushroom enters inventory")
	game.player.global_position = q.npcs.camp.global_position
	q.open_field("camp")
	q.page = "Sell"
	q.refresh_field()
	check(has_sale(q,"Golden Yarrow") and has_sale(q,"Porcini"),"Vendor lists both a flower and a mushroom for sale")
	var cash: int = game.player.score
	var flower_sale: String = q.authoritative_action(game.player,"trade",["camp","sell_flower","golden_yarrow",""])
	q.refresh_field()
	check(Lang.text(flower_sale).begins_with("Sold:") and game.player.score==cash+q.FLOWER_SELL_PRICE and int(game.brewing.stock(1).flowers.get("golden_yarrow",0))==0 and not has_sale(q,"Golden Yarrow"),"Flower sale pays once, removes stock and refreshes the row")
	cash = game.player.score
	q.authoritative_action(game.player,"trade",["camp","sell_flower","golden_yarrow",""])
	check(game.player.score==cash,"Missing flower cannot be sold a second time")
	var mushroom_price: int = Inventory.MUSHROOMS.steinpilz.sell
	var mushroom_sale: String = q.authoritative_action(game.player,"trade",["camp","sell_mushroom","steinpilz",""])
	q.refresh_field()
	check(Lang.text(mushroom_sale).begins_with("Sold:") and game.player.score==cash+mushroom_price and int(game.inventory.mushrooms.get("steinpilz",0))==0 and not has_sale(q,"Porcini"),"Mushroom sale pays once, removes stock and refreshes the row")
	game.brewing.add_flower(1,"golden_yarrow")
	await create_timer(0.3).timeout
	check(has_sale(q,"Golden Yarrow"),"Open vendor menu notices newly added plant stock")
	print("PLANES_SALES_DONE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
