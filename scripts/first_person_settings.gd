extends RefCounted

# Shared by gameplay, the viewmodel and the settings interface. Angles are degrees,
# mouse sensitivity is degrees per pixel and world distances are metres.
const DEFAULTS := {
	"view_mode": "top_down",
	"fp_fov": 75.0,
	"fp_ads_fov": 55.0,
	"fp_sensitivity": 0.12,
	"fp_ads_sensitivity": 0.65,
	"fp_invert_y": false,
	"fp_smoothing": 0.0,
	"fp_pitch_up": 89.0,
	"fp_pitch_down": 89.0,
	"fp_eye_height": 1.5,
	"fp_near": 0.03,
	"fp_far": 240.0,
	"fp_viewmodel_fov": 65.0,
	"fp_weapon_x": 0.24,
	"fp_weapon_y": -0.22,
	"fp_weapon_z": -0.38,
	"fp_weapon_scale": 1.0,
	"fp_bob": 0.015,
	"fp_bob_speed": 10.0,
	"fp_sway": 0.4,
	"fp_recoil": 0.6,
	"fp_recoil_recovery": 10.0,
	"fp_crosshair_length": 7.0,
	"fp_crosshair_gap": 4.0,
	"fp_crosshair_width": 2.0,
	"fp_crosshair_dynamic": true,
	"fp_crosshair_dot": false,
}

# [minimum, maximum, interface step]. Loading clamps without quantizing so that
# hand-edited configuration values retain their intended precision.
const RANGES := {
	"fp_fov": [50.0, 100.0, 1.0],
	"fp_ads_fov": [30.0, 90.0, 1.0],
	"fp_sensitivity": [0.02, 0.5, 0.01],
	"fp_ads_sensitivity": [0.1, 1.0, 0.05],
	"fp_smoothing": [0.0, 30.0, 1.0],
	"fp_pitch_up": [30.0, 89.0, 1.0],
	"fp_pitch_down": [30.0, 89.0, 1.0],
	"fp_eye_height": [1.2, 1.6, 0.01],
	"fp_near": [0.01, 0.1, 0.01],
	"fp_far": [100.0, 400.0, 10.0],
	"fp_viewmodel_fov": [40.0, 100.0, 1.0],
	"fp_weapon_x": [-0.4, 0.4, 0.01],
	"fp_weapon_y": [-0.5, -0.05, 0.01],
	"fp_weapon_z": [-0.8, -0.2, 0.01],
	"fp_weapon_scale": [0.5, 1.5, 0.05],
	"fp_bob": [0.0, 0.05, 0.001],
	"fp_bob_speed": [4.0, 18.0, 0.5],
	"fp_sway": [0.0, 2.0, 0.05],
	"fp_recoil": [0.0, 2.0, 0.05],
	"fp_recoil_recovery": [2.0, 25.0, 1.0],
	"fp_crosshair_length": [2.0, 16.0, 1.0],
	"fp_crosshair_gap": [0.0, 12.0, 1.0],
	"fp_crosshair_width": [1.0, 4.0, 1.0],
}

static func sanitize(values: Dictionary) -> Dictionary:
	var result := values.duplicate(true)
	for key in DEFAULTS:
		if key == "view_mode":
			var view_mode := str(result.get(key, DEFAULTS[key]))
			result[key] = view_mode if view_mode in ["top_down", "first_person"] else DEFAULTS[key]
		elif DEFAULTS[key] is bool:
			var raw: Variant = result.get(key, DEFAULTS[key])
			result[key] = raw if raw is bool else DEFAULTS[key]
		else:
			var raw: Variant = result.get(key, DEFAULTS[key])
			var number := float(raw) if raw is float or raw is int else float(DEFAULTS[key])
			if not is_finite(number):
				number = float(DEFAULTS[key])
			var limits: Array = RANGES[key]
			result[key] = clampf(number, float(limits[0]), float(limits[1]))
	result.fp_ads_fov = minf(float(result.fp_ads_fov), float(result.fp_fov))
	return result
