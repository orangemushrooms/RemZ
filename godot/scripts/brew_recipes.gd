extends RefCounted

# Separate catalogue: effects can read recipes without loading the brewing UI/world.
const FLOWERS := {
	"corpse_bloom": {"name": "Corpse Bloom", "model": "field_flower_1", "color": Color("c8c65a"), "height": 0.85},
	"ember_lily": {"name": "Ember Lily", "model": "field_flower_2", "color": Color("ee4080"), "height": 0.65},
	"golden_yarrow": {"name": "Golden Yarrow", "model": "field_flower_3", "color": Color("edc842"), "height": 0.65},
	"dusk_thistle": {"name": "Dusk Thistle", "model": "field_flower_4", "color": Color("d7a35d"), "height": 0.7},
	"crimson_rose": {"name": "Crimson Rose", "model": "field_flower_5", "color": Color("e44748"), "height": 0.65},
	"violet_bell": {"name": "Violet Bell", "model": "field_flower_6", "color": Color("ad8bef"), "height": 0.6},
}
const DRINKS := {
	"brew_meadow": {"name": "Meadow Tea", "ingredients": {"golden_yarrow": 2}, "text": "+45 health. Kept at full health.", "heal": 45.0, "color": Color("eac64c")},
	"brew_rose": {"name": "Roseguard Tonic", "ingredients": {"crimson_rose": 2}, "text": "+20 health; 45 s 20% less damage taken", "heal": 20.0, "duration": 45.0, "guard": 0.8, "effect": "Damage taken -20%", "color": Color("f47995")},
	"brew_fleet": {"name": "Meadow Runner", "ingredients": {"violet_bell": 2, "golden_yarrow": 1}, "text": "45 s +35% running speed", "duration": 45.0, "speed": 1.35, "effect": "Speed +35%", "color": Color("97e1bc")},
	"brew_ember": {"name": "Emberheart", "ingredients": {"ember_lily": 1, "reizker": 1}, "text": "25 s +25% damage; every 3 s ignite visible zombies within 6 m", "duration": 25.0, "damage": 1.25, "pulse": "fire", "interval": 3.0, "radius": 6.0, "effect": "Damage +25% / fire aura", "color": Color("ff8842")},
	"brew_frost": {"name": "Winter Bloom", "ingredients": {"violet_bell": 2, "parasol": 1}, "text": "25 s 20% less damage taken; every 3 s slow visible zombies within 7 m (bosses resist)", "duration": 25.0, "guard": 0.8, "pulse": "frost", "interval": 3.0, "radius": 7.0, "effect": "Damage taken -20% / frost aura", "color": Color("72dfff")},
	"brew_dream": {"name": "Moonpetal Dream", "ingredients": {"corpse_bloom": 1, "kahlkopf": 1}, "text": "35 s +65% damage and +20% speed; 12 s of colourful visions", "duration": 35.0, "damage": 1.65, "speed": 1.2, "trip": 12.0, "effect": "Damage +65% / speed +20%", "color": Color("c98dff")},
	"brew_focus": {"name": "Still Hand", "ingredients": {"dusk_thistle": 1, "morchel": 1}, "text": "45 s 35% faster reloads and 40% less spread", "duration": 45.0, "reload": 0.65, "spread": 0.6, "effect": "Reload -35% / spread -40%", "color": Color("d4b47b")},
	"brew_spring": {"name": "Springheart Cordial", "ingredients": {"crimson_rose": 1, "golden_yarrow": 1, "steinpilz": 1}, "text": "+60 health; 45 s triple health regeneration", "heal": 60.0, "duration": 45.0, "regen": 3.0, "effect": "Regeneration x3", "color": Color("6ceba6")},
}
const BREW_SECONDS := 4.0
const DRINK_LIMIT := 8

