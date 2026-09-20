extends RefCounted

const DEFS := {
	"hawk": {"name": "Falkenauge · Legendär", "price": 1800, "level": 5, "kind": "relic", "desc": "35 % weniger Streuung und 20 % weniger Rückstoß.", "bonuses": {"spread": 0.65, "recoil": 0.8}},
	"bark": {"name": "Herz der Uralteiche · Legendär", "price": 2200, "level": 8, "kind": "relic", "desc": "20 % weniger erlittener Schaden.", "bonuses": {"guard": 0.8}},
	"blood": {"name": "Blutstein · Legendär", "price": 2600, "level": 10, "kind": "relic", "desc": "Eigene Waffen- und Brandkills heilen 3 Leben; keine Heilung durch Türme.", "bonuses": {}},
	"wind": {"name": "Sturmfeder · Legendär", "price": 2500, "level": 9, "kind": "relic", "desc": "20 % kürzeres Nachladen und 10 % mehr Bewegungstempo.", "bonuses": {"reload": 0.8, "speed": 1.1}},
	"phoenix": {"name": "Phönixasche · Legendär", "price": 3800, "level": 15, "kind": "relic", "desc": "Verhindert einmal pro Welle einen tödlichen Treffer und stellt 40 % Leben her. Wechseln setzt die Ladung nicht zurück.", "bonuses": {}},
	"fire": {"name": "Drachenatem · Feuerpatronen", "price": 480, "level": 5, "kind": "ammo", "amount": 24, "desc": "24 Schüsse. Treffer entzünden Zombies: 36 Brandschaden über 3 s. Erneute Treffer erneuern die Dauer, stapeln nicht."},
	"frost": {"name": "Winterbiss · Frostpatronen", "price": 520, "level": 7, "kind": "ammo", "amount": 18, "desc": "18 Schüsse. Treffer verlangsamen Zombies 3 s um 45 %, Titanen um 20 %."},
}
const AMMO_CAP := 96

static func multiplier(relic: String, attribute: String) -> float:
	return float(DEFS.get(relic, {}).get("bonuses", {}).get(attribute, 1.0))
