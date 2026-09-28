extends Weather
## Share rain, wetness, thunder and lightning; retain the site's summer sky.
var summer_sky: ProceduralSkyMaterial
var elapsed := 0.0

func setup(game: Node) -> void:
	main = game
	_env = main.settings.env
	summer_sky = _env.sky.sky_material
	_rng.seed = 83447
	_build_rain()
	# Open fields use distance fog; no extra volumetric fog pass.
	_rain.amount = 1600
	for flag in OS.get_cmdline_user_args():
		if flag.begins_with("--weather="): force(flag.get_slice("=",1))

func scheduled_state(_clock: float) -> String:
	var minute := fmod(elapsed/60.0,16.0)
	if minute<4: return "clear"
	if minute<7: return "fog"
	if minute<11: return "rain"
	if minute<13: return "storm"
	return "clear"

func _process(delta: float) -> void:
	if not main or not main.started or main.over or not main.player.active: return
	elapsed += delta
	super._process(delta)

func _apply_environment(delta: float) -> void:
	var fog := 0.00018
	if state=="fog": fog = lerpf(fog,0.008,intensity)
	elif state=="rain": fog = lerpf(fog,0.0015,intensity)
	elif state=="storm": fog = lerpf(fog,0.003,intensity)
	_env.fog_density = lerpf(_env.fog_density,fog,minf(1,delta))
	var dim := float(DIM[state])*intensity
	main.settings.sun.light_energy = 1.65*(1.0-dim)
	_env.ambient_light_energy = 0.7*(1.0-dim*0.45)
	summer_sky.sky_top_color = Color(0.15,0.39,0.78).lerp(Color(0.24,0.28,0.32),float(OVERCAST[state])*intensity)
	summer_sky.sky_horizon_color = Color(0.66,0.79,0.89).lerp(Color(0.4,0.44,0.47),float(OVERCAST[state])*intensity)

func _update_flash(delta: float) -> void:
	if _flash_t<=0:
		_sun_restore = false
		flash = 0
		return
	_flash_t -= delta
	var t := 1.0-_flash_t/_flash_len
	flash = clampf(maxf(exp(-t*6),_flicker*exp(-absf(t-0.35)*14))*(1-t*0.4),0,1)
	main.settings.sun.light_energy = maxf(main.settings.sun.light_energy,flash*9)
	_env.ambient_light_energy = maxf(_env.ambient_light_energy,0.7+flash*2.0)
