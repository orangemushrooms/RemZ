extends SceneTree
var game: Node3D
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1
 print("PASS: " if ok else "FAIL: ",message)
func run() -> void:
 game = load("res://scenes/planes.tscn").instantiate()
 root.add_child(game); current_scene = game
 while not game.ready_for_exploration: await process_frame
 game.waves.set_process(false)
 check(game.quickbar.buttons.size()==10 and game.quickbar.bindings[9]=="knife","Shared Forest ten-slot bar includes knife on 0")
 game.quickbar.activate(9)
 check(game.weapons.current=="knife","Slot ten equips the knife")
 game.day_night.set_time_hours(12)
 var daylight: float = game.settings.sun.light_energy
 game.day_night.advance(1)
 check(game.day_night.clock_seconds>43200 and not game.hud.clock_label.text.is_empty(),"Shared clock advances and updates HUD")
 game.day_night.set_time_hours(23)
 check(game.settings.sun.light_energy<daylight and game.day_night.is_night(),"Night reduces sunlight")
 game.weather.force("storm"); game.weather.intensity=1
 game.weather._apply_environment(1)
 game.day_night._apply_lighting(true)
 check(game.day_night.weather_dim<1 and game.day_night.overcast>0,"Weather dims the shared day-night lighting")
 game._flags.erase("--no-music")
 game.waves.phase="idle"; game._update_music()
 check(game.music.current=="night" and game.music._players.night.playing,"Forest night music plays")
 game.day_night.set_time_hours(12); game._update_music()
 check(game.music.current=="morning","Daytime intermission uses Forest morning music")
 game.waves.phase="spawning"; game.waves.wave=1; game._update_music()
 check(game.music.current=="combat","Combat uses Forest combat music")
 game.waves.wave=5; game._update_music()
 check(Music.is_boss(game.music.current),"Fifth wave uses Forest boss music")
 game.waves.phase="idle"
 game.progression.show_loadout()
 check(game.progression.loadout_open and game.quickbar.inventory_open(),"I inventory supports shared slot assignment")
 game.quickbar.bind_item(1,"knife")
 check(game.quickbar.bindings[1]=="knife","Owned equipment can be assigned to slots")
 game.progression.close()
 game.progression.accepted.bouquet=true
 game.progression._update_tracker()
 check(game.progression.tracker.visible and game.progression.tracker.text.contains("0/6"),"Quest tracker shows accepted field progress")
 game.set_menu(true)
 var clock: float = game.day_night.clock_seconds
 await create_timer(0.15,true).timeout
 check(game.day_night.clock_seconds==clock,"Pause freezes the world clock")
 check(game.music.can_process(),"Forest music continues through pause and game over")
 game.set_menu(false)
 if "--render-atmosphere" in OS.get_cmdline_user_args():
  var folder := ProjectSettings.globalize_path("res://../artifacts/planes/atmosphere/")
  DirAccess.make_dir_recursive_absolute(folder)
  game.weather.force("clear"); game.weather.intensity=0
  game.weather._apply_environment(1)
  for hour in [12,23]:
   game.day_night.set_time_hours(hour)
   await create_timer(2).timeout
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder+str(hour)+".png")
 game.finish_survival(false); game._update_music()
 check(game.music.current=="gameover","Death plays Forest game-over track")
 print("PLANES_ATMOSPHERE_DONE checks=%d failures=%d" % [checks,failures])
 quit(1 if failures else 0)
