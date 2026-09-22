extends RefCounted

const DEFS := {
	"hawk": {"name": "Falkenauge · Legendär", "price": 1800, "level": 5, "kind": "relic", "desc": "35 % weniger Streuung und 20 % weniger Rückstoß.", "bonuses": {"spread": 0.65, "recoil": 0.8}},
	"bark": {"name": "Herz der Uralteiche · Legendär", "price": 2200, "level": 8, "kind": "relic", "desc": "20 % weniger erlittener Schaden.", "bonuses": {"guard": 0.8}},
	"blood": {"name": "Blutstein · Legendär", "price": 2600, "level": 10, "kind": "relic", "desc": "Eigene Waffen- und Brandkills heilen 3 Leben; keine Heilung durch Türme.", "bonuses": {}},
	"wind": {"name": "Sturmfeder · Legendär", "price": 2500, "level": 9, "kind": "relic", "desc": "20 % kürzeres Nachladen und 10 % mehr Bewegungstempo.", "bonuses": {"reload": 0.8, "speed": 1.1}},
	"phoenix": {"name": "Phönixasche · Legendär", "price": 3800, "level": 15, "kind": "relic", "desc": "Verhindert einmal pro Welle einen tödlichen Treffer und stellt 40 % Leben her. Wechseln setzt die Ladung nicht zurück.", "bonuses": {}},
	"coin": {"name": "Wegzoll des Krämers · Legendär", "price": 1900, "level": 6, "kind": "relic", "desc": "20 % mehr Rem Dollars für eigene Kills.", "bonuses": {"score": 1.2}},
	"owl": {"name": "Eulenauge · Legendär", "price": 2000, "level": 6, "kind": "relic", "time": ["night"], "desc": "30 % weniger Streuung und 15 % weniger Rückstoß. Nur nachts im Angebot.", "bonuses": {"spread": 0.7, "recoil": 0.85}},
	"moss": {"name": "Moosmantel · Legendär", "price": 2100, "level": 7, "kind": "relic", "region": ["N", "W"], "desc": "15 % weniger erlittener Schaden und 5 % mehr Tempo. Führt der Krämer im Nord- und Westwald.", "bonuses": {"guard": 0.85, "speed": 1.05}},
	"raven": {"name": "Rabenfeder · Legendär", "price": 2200, "level": 8, "kind": "relic", "time": ["night"], "desc": "30 % kürzeres Nachladen. Nur nachts im Angebot.", "bonuses": {"reload": 0.7}},
	"ember": {"name": "Glutkern · Legendär", "price": 2400, "level": 8, "kind": "relic", "time": ["day"], "desc": "15 % mehr Waffenschaden. Nur bei Tageslicht im Angebot.", "bonuses": {"damage": 1.15}},
	"stag": {"name": "Hirschkrone · Legendär", "price": 2300, "level": 9, "kind": "relic", "region": ["E", "S"], "desc": "18 % mehr Bewegungstempo. Führt der Krämer im Ost- und Südwald.", "bonuses": {"speed": 1.18}},
	"steel": {"name": "Stahlherz · Legendär", "price": 2500, "level": 10, "kind": "relic", "time": ["day"], "desc": "45 % weniger Rückstoß. Nur bei Tageslicht im Angebot.", "bonuses": {"recoil": 0.55}},
	"lantern": {"name": "Nebellaterne · Legendär", "price": 2800, "level": 11, "kind": "relic", "time": ["night"], "region": ["N", "E"], "desc": "15 % weniger erlittener Schaden und 8 % mehr Waffenschaden. Nachts im Nord- und Ostwald.", "bonuses": {"guard": 0.85, "damage": 1.08}},
	"root": {"name": "Wurzelband · Legendär", "price": 3000, "level": 12, "kind": "relic", "region": ["W", "S"], "desc": "25 % weniger erlittener Schaden. Führt der Krämer im West- und Südwald.", "bonuses": {"guard": 0.75}},
	"fire": {"name": "Drachenatem · Feuerpatronen", "price": 480, "level": 5, "kind": "ammo", "amount": 24, "desc": "24 Schüsse. Treffer entzünden Zombies: 36 Brandschaden über 3 s. Erneute Treffer erneuern die Dauer, stapeln nicht."},
	"frost": {"name": "Winterbiss · Frostpatronen", "price": 520, "level": 7, "kind": "ammo", "amount": 18, "desc": "18 Schüsse. Treffer verlangsamen Zombies 3 s um 45 %, Titanen um 20 %."},
}
const AMMO_CAP := 96

static func multiplier(relic: String, attribute: String) -> float:
	return float(DEFS.get(relic, {}).get("bonuses", {}).get(attribute, 1.0))
