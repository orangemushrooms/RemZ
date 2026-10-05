extends Weather
## Share rain, wetness, thunder and lightning with the Forest day-night lighting.
var elapsed := 0.0

func setup(game: Node) -> void:
	main = game
	_env = main.settings.env
	_rng.seed = 83447
	_build_rain()
	# Open fields use distance fog; no extra volumetric fog pass.
	_rain.amount = 1600
	for flag in OS.get_cmdline_user_args():
		if flag.begins_with("--weather="): force(flag.get_slice("=",1))

func scheduled_state(_clock: float) -> String:
	if main.get("expedition") and main.expedition.enabled: return str(main.expedition.forecast().state)
	var minute := fmod(elapsed/60.0,16.0)
	if minute<4: return "clear"
	if minute<7: return "fog"
	if minute<11: return "rain"
	if minute<13: return "storm"
	return "clear"

func _process(delta: float) -> void:
	if not main or not main.started or main.over or (not NetSession.enabled and not main.player.active): return
	if not NetSession.is_client(): elapsed += delta
	super._process(delta)

func _apply_environment(delta: float) -> void:
	var fog := 0.00018
	if state=="fog": fog = lerpf(fog,0.008,intensity)
	elif state=="rain": fog = lerpf(fog,0.0015,intensity)
	elif state=="storm": fog = lerpf(fog,0.003,intensity)
	_env.fog_density = lerpf(_env.fog_density,fog,minf(1,delta))
	main.day_night.weather_dim = 1.0-float(DIM[state])*intensity
	main.day_night.overcast = float(OVERCAST[state])*intensity

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
