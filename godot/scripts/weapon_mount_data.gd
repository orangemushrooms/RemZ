# Measured geometry of the weapon and attachment models - GENERATED, do not hand-edit.
# Rebuild with: node tools/weapon_geometry.mjs --all-weapons --bake godot/scripts/weapon_mount_data.gd
# Values are in the raw GLB frame (Meshy normalises every static to a ~1.9 unit box, barrel
# along -X). weapon_attachments.gd pushes them through the view model node transform, so they
# stay correct when a weapon's "height" in Weapons.DEFS changes.
class_name WeaponMountData
extends RefCounted

# bore: muzzle centre. mag: lowest point of the magazine. receiver: thickest cross section.
const WEAPONS := {
	"pistol": {
		"bore": Vector3(-0.95059, 0.32299, -0.00367), "bore_radius": 0.04457,
		"length": 1.89953, "height": 1.32768, "width": 0.31725,
		"mag": Vector3(0.47052, -0.66447, -0.01631), "mag_width": 0.26568,
		"receiver": Vector3(0.59278, -0.21754, -0.01352), "receiver_top": 0.66322, "receiver_width": 0.24473,
	},
	"revolver": {
		"bore": Vector3(-0.95078, 0.35694, 0.00063), "bore_radius": 0.04775,
		"length": 1.89939, "height": 1.0069, "width": 0.28753,
		"mag": Vector3(0.83079, -0.50427, -0.01246), "mag_width": 0.16972,
		"receiver": Vector3(0.51334, 0.03065, 0.00657), "receiver_top": 0.50263, "receiver_width": 0.19423,
	},
	"smg": {
		"bore": Vector3(-0.95084, 0.1931, 0.00151), "bore_radius": 0.02707,
		"length": 1.89961, "height": 0.79109, "width": 0.22627,
		"mag": Vector3(-0.099, -0.3933, -0.00401), "mag_width": 0.05887,
		"receiver": Vector3(-0.19891, 0.16442, -0.01763), "receiver_top": 0.39779, "receiver_width": 0.10796,
	},
	"ak47": {
		"bore": Vector3(-0.95079, 0.17655, 0.02487), "bore_radius": 0.01916,
		"length": 1.89939, "height": 0.59047, "width": 0.15111,
		"mag": Vector3(-0.13003, -0.29568, 0.01879), "mag_width": 0.03524,
		"receiver": Vector3(-0.1198, -0.11899, 0.01646), "receiver_top": 0.29479, "receiver_width": 0.05059,
	},
	"rifle": {
		"bore": Vector3(-0.95088, 0.15339, 0.00111), "bore_radius": 0.02371,
		"length": 1.89944, "height": 0.42817, "width": 0.10946,
		"mag": Vector3(0.27907, -0.21698, -0.00098), "mag_width": 0.01155,
		"receiver": Vector3(0.82984, -0.05181, -0.0002), "receiver_top": 0.21119, "receiver_width": 0.05992,
	},
	"marksman": {
		"bore": Vector3(-0.95068, 0.06027, -0.01006), "bore_radius": 0.01808,
		"length": 1.89905, "height": 0.4545, "width": 0.099,
		"mag": Vector3(0.12497, -0.22666, 0.00506), "mag_width": 0.03811,
		"receiver": Vector3(0.0384, 0.0815, -0.01644), "receiver_top": 0.22783, "receiver_width": 0.07249,
	},
	"lmg": {
		"bore": Vector3(-0.95075, 0.15889, 0.00103), "bore_radius": 0.02664,
		"length": 1.89843, "height": 0.6413, "width": 0.48778,
		"mag": Vector3(-0.39232, -0.32214, 0.19027), "mag_width": 0.45635,
		"receiver": Vector3(-0.35749, 0.10051, 0.0043), "receiver_top": 0.31916, "receiver_width": 0.16611,
	},
	"breacher": {
		"bore": Vector3(-0.95081, 0.10826, -0.00134), "bore_radius": 0.02493,
		"length": 1.89875, "height": 0.58526, "width": 0.14011,
		"mag": Vector3(0.10928, -0.29352, 0.02555), "mag_width": 0.06414,
		"receiver": Vector3(0.11723, 0.03736, 0.0145), "receiver_top": 0.29174, "receiver_width": 0.07242,
	},
	"titanbreaker": {
		"bore": Vector3(-0.9504, 0.03967, -0.01954), "bore_radius": 0.03671,
		"length": 1.89812, "height": 0.52238, "width": 0.16791,
		"mag": Vector3(0.17173, -0.2621, 0.01023), "mag_width": 0.06521,
		"receiver": Vector3(0.19638, 0.06412, -0.02679), "receiver_top": 0.26028, "receiver_width": 0.08104,
	},
	"deagle": {
		"bore": Vector3(-0.95046, 0.23114, 0.00645), "bore_radius": 0.04621,
		"length": 1.89847, "height": 0.84183, "width": 0.22304,
		"mag": Vector3(0.2558, -0.42248, -0.01665), "mag_width": 0.04986,
		"receiver": Vector3(0.75026, 0.02191, 0.01597), "receiver_top": 0.41935, "receiver_width": 0.19318,
	},
	"flare_pistol": {
		"bore": Vector3(-0.9507, 0.36244, -0.00686), "bore_radius": 0.10084,
		"length": 1.89916, "height": 1.07347, "width": 0.36016,
		"mag": Vector3(0.65663, -0.53756, 0.00932), "mag_width": 0.22958,
		"receiver": Vector3(0.6715, -0.31069, 0.03543), "receiver_top": 0.53591, "receiver_width": 0.2463,
	},
	"mac10": {
		"bore": Vector3(-0.95051, 0.15473, 0.0121), "bore_radius": 0.03865,
		"length": 1.89906, "height": 0.65761, "width": 0.20469,
		"mag": Vector3(0.08329, -0.32857, 0.02718), "mag_width": 0.07784,
		"receiver": Vector3(0.11771, 0.05963, -0.00942), "receiver_top": 0.32904, "receiver_width": 0.11355,
	},
	"cryo_smg": {
		"bore": Vector3(-0.95033, 0.14656, -0.0076), "bore_radius": 0.03454,
		"length": 1.89795, "height": 0.83151, "width": 0.24173,
		"mag": Vector3(-0.12059, -0.41639, -0.02034), "mag_width": 0.07663,
		"receiver": Vector3(-0.11997, 0.15908, 0.00402), "receiver_top": 0.41511, "receiver_width": 0.15232,
	},
	"plasma_sniper": {
		"bore": Vector3(-0.95034, 0.07418, -0.00498), "bore_radius": 0.03091,
		"length": 1.89908, "height": 0.60695, "width": 0.16077,
		"mag": Vector3(0.11883, -0.30449, 0.02497), "mag_width": 0.054,
		"receiver": Vector3(0.11789, 0.1004, 0.00144), "receiver_top": 0.30246, "receiver_width": 0.09206,
	},
	"lever_rifle": {
		"bore": Vector3(-0.95082, 0.19476, 0.00066), "bore_radius": 0.0179,
		"length": 1.89954, "height": 0.61585, "width": 0.09472,
		"mag": Vector3(0.24567, -0.30712, -0.03401), "mag_width": 0.06966,
		"receiver": Vector3(0.35511, -0.28922, -0.00292), "receiver_top": 0.30873, "receiver_width": 0.06805,
	},
	"minigun": {
		"bore": Vector3(-0.94984, 0.32701, -0.15374), "bore_radius": 0.02813,
		"length": 1.89695, "height": 0.84939, "width": 0.77633,
		"mag": Vector3(0.26833, 0.00848, -0.4264), "mag_width": 0.12849,
		"receiver": Vector3(0.43336, 0.05737, -0.06495), "receiver_top": 0.42299, "receiver_width": 0.62027,
	},
	"graviton_cannon": {
		"bore": Vector3(-0.95044, 0.12812, 0.0003), "bore_radius": 0.17367,
		"length": 1.89886, "height": 0.77688, "width": 0.46687,
		"mag": Vector3(0.01863, -0.38878, 0.00309), "mag_width": 0.06695,
		"receiver": Vector3(0.2759, 0.1005, 0.00402), "receiver_top": 0.38809, "receiver_width": 0.34095,
	},
}

# forward points away from the gun (muzzle end), rear is the face that meets the weapon.
const PARTS := {
	"mod_suppressor": {"shape": "tube", "forward": Vector3(-1, 0.00067, -0.00159), "up": Vector3(0.00017, 0.95433, 0.29875), "centre": Vector3(0.26974, 0.00105, 0.00319),
		"length": 1.89819, "radius": 0.16038, "up_span": 0.28472, "side_span": 0.32076,
		"front": 1.21962, "front_radius": 0.17542, "front_centre": Vector2(0.00343, 0.00663),
		"rear": 0.67857, "rear_radius": 0.17637, "rear_centre": Vector2(0.01402, 0.0101)},
	"mod_compensator": {"shape": "block", "forward": Vector3(-1, -0.00198, -0.00189), "up": Vector3(0.00215, -0.9957, -0.09263), "centre": Vector3(-0.01534, -0.01766, 0.00032),
		"length": 1.90048, "radius": 0.24637, "up_span": 0.49274, "side_span": 0.42018,
		"front": 0.93578, "front_radius": 0.2393, "front_centre": Vector2(-0.00695, -0.00652),
		"rear": 0.9647, "rear_radius": 0.23697, "rear_centre": Vector2(0.0106, 0.00212)},
	"mod_ghost": {"shape": "tube", "forward": Vector3(-0.96555, 0.26014, 0.00619), "up": Vector3(-0.00659, -0.0007, -0.99998), "centre": Vector3(-0.23156, 0.05657, 0.00343),
		"length": 1.87412, "radius": 0.16938, "up_span": 0.33875, "side_span": 0.31203,
		"front": 0.69589, "front_radius": 0.1216, "front_centre": Vector2(0.00167, 0.00497),
		"rear": 1.17823, "rear_radius": 0.15236, "rear_centre": Vector2(0.00779, 0.0095)},
	"mod_extended_mag": {"shape": "tube", "forward": Vector3(0.01642, 0.99986, -0.00161), "up": Vector3(0.99634, -0.01623, 0.08389), "centre": Vector3(-0.0014, 0.18085, 0.00077),
		"length": 1.90329, "radius": 0.20703, "up_span": 0.41406, "side_span": 0.29095,
		"front": 0.76826, "front_radius": 0.08123, "front_centre": Vector2(-0.0076, 0.00278),
		"rear": 1.13503, "rear_radius": 0.26844, "rear_centre": Vector2(-0.12915, 0.05296)},
	"mod_endless": {"shape": "disc", "forward": Vector3(-0.00523, 0.00274, 0.99998), "up": Vector3(0.00918, -0.99995, 0.00279), "centre": Vector3(0.00793, 0.06801, -0.02552),
		"length": 0.68058, "radius": 0.60193, "up_span": 1.20385, "side_span": 0.98705,
		"front": 0.36433, "front_radius": 0.24976, "front_centre": Vector2(0.07074, -0.01593),
		"rear": 0.31625, "rear_radius": 0.54512, "rear_centre": Vector2(0.03437, -0.01545)},
	"mod_quick_action": {"shape": "tube", "forward": Vector3(-0.99972, -0.02345, 0.00067), "up": Vector3(0.02346, -0.99959, 0.01632), "centre": Vector3(0.38612, 0.02619, 0.00078),
		"length": 1.89213, "radius": 0.1136, "up_span": 0.22719, "side_span": 0.19375,
		"front": 1.33352, "front_radius": 0.07451, "front_centre": Vector2(-0.04817, -0.00959),
		"rear": 0.55862, "rear_radius": 0.12464, "rear_centre": Vector2(0.00596, 0.00491)},
	"mod_match_barrel": {"shape": "tube", "forward": Vector3(-0.99997, 0.00809, 0.00095), "up": Vector3(-0.00813, -0.99895, -0.04499), "centre": Vector3(0.38274, -0.00592, -0.00012),
		"length": 1.89881, "radius": 0.06102, "up_span": 0.12203, "side_span": 0.11804,
		"front": 1.33297, "front_radius": 0.06554, "front_centre": Vector2(-0.00317, 0.00193),
		"rear": 0.56583, "rear_radius": 0.07003, "rear_centre": Vector2(0.00048, -0.00221)},
	"mod_titan_core": {"shape": "tube", "forward": Vector3(-1, 0.00221, 0.00136), "up": Vector3(0.00177, 0.96394, -0.26613), "centre": Vector3(0.56941, -0.01848, -0.00092),
		"length": 1.8989, "radius": 0.05937, "up_span": 0.11875, "side_span": 0.11093,
		"front": 1.51988, "front_radius": 0.04363, "front_centre": Vector2(0.00065, 0.00962),
		"rear": 0.37903, "rear_radius": 0.07047, "rear_centre": Vector2(-0.00866, 0.00461)},
	"mod_mag_tube": {"shape": "tube", "forward": Vector3(-1, -0.00155, -0.00147), "up": Vector3(0.00157, -0.06952, -0.99758), "centre": Vector3(0.44576, -0.00131, 0.00231),
		"length": 1.89938, "radius": 0.08514, "up_span": 0.17028, "side_span": 0.15467,
		"front": 1.39625, "front_radius": 0.07951, "front_centre": Vector2(-0.00411, 0.00101),
		"rear": 0.50312, "rear_radius": 0.11696, "rear_centre": Vector2(-0.00223, 0.00195)},
}
