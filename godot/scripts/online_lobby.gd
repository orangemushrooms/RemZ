# Autoload "Online": the Epic Online Services side of the co-op. It starts the EOS platform, signs the
# player in anonymously (Connect Device ID, no Epic account), opens or finds the lobby a six-letter join
# code stands for and hands NetSession an EOSGMultiplayerPeer, so every RPC of the game travels over
# EOS P2P (direct when the NATs allow it, Epic's relay otherwise). Everything EOS is reached dynamically:
# the IEOS engine singleton, ClassDB and the addon's scripts loaded at runtime. A missing or unloadable
# extension therefore only switches the online lobby off - the ENet path (direct IP / LAN / Hamachi)
# never notices. Player-facing texts are English literals or Lang.t segments (see docs/LOCALIZATION.md).
extends Node

signal changed

const ADDON := "res://addons/epic-online-services-godot/"
const CONFIG := "res://eos.cfg"
const BUCKET := "remz-coop-1"
const SOCKET := "remz"
# No 0 / O / 1 / I: a code read out loud or typed from a screenshot stays unambiguous.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
const ATTR_CODE := "CODE"
const ATTR_VERSION := "VERSION"
const ATTR_HOST := "HOST"
const STEP_TIMEOUT := 20.0 # seconds we wait for one EOS round trip
const QUEUE_BYTES := 8 * 1024 * 1024 # EOS P2P packet queues: a late joiner's initial state is a burst of chunks
const REQUEST_GRACE := 15.0 # a P2P connection request from a user the lobby does not list yet waits this long
const RESULT_SUCCESS := 0
const RESULT_INVALID_USER := 3
const RESULT_NOT_FOUND := 18
const RESULT_DUPLICATE := 24
const RESULT_LOBBY_TOO_MANY_PLAYERS := 9004

var state := "off" # off | starting | ready | failed
var code := "" # join code of the lobby we are in
var lobby = null # HLobby (addon script), null outside a lobby
var peer = null # the EOSGMultiplayerPeer NetSession plays over
var product_user_id := ""
var credentials: Dictionary = {}
var force_unavailable := false # tests: behave as if the runtime were missing
var log_lines: Array[String] = [] # EOS warnings and errors, newest last (diagnostics)
var _eos = null # the addon's eos.gd script (EOS.* option classes and enums)
var _ieos = null # the IEOS engine singleton
var _hlobby_script = null
var _generation := 0
var _platform_ready := false
var _login_pending := false
var _requests: Dictionary = {} # pending P2P connection requests: product user id -> first seen (s)
var _elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The start menu pauses the tree; EOS must keep ticking so lobby callbacks arrive while the menu is open.
	var runtime := get_node_or_null("/root/EOSGRuntime")
	if runtime: runtime.process_mode = Node.PROCESS_MODE_ALWAYS
	credentials = load_credentials()
	if "--eos-unavailable" in OS.get_cmdline_user_args(): force_unavailable = true
	if "--eos-check" in OS.get_cmdline_user_args(): _run_check()

func _process(delta: float) -> void:
	_elapsed += delta
	if not _requests.is_empty(): _review_requests()

# ---------------------------------------------------------------- availability
func runtime_loaded() -> bool:
	if force_unavailable: return false
	if not Engine.has_singleton("IEOS") or not ClassDB.class_exists("EOSGMultiplayerPeer"): return false
	for autoload in ["EOSGRuntime", "HPlatform", "HAuth", "HLobbies", "HP2P"]:
		if get_node_or_null("/root/" + autoload) == null: return false
	return true

func available() -> bool:
	return runtime_loaded() and credentials_complete(credentials)

func unavailable_reason() -> String:
	if not runtime_loaded(): return "The online lobby is not available on this PC: the Epic Online Services runtime did not load. Direct / LAN / Hamachi still works."
	if not credentials_complete(credentials): return "The online lobby is not configured in this build (no EOS client credentials). Direct / LAN / Hamachi still works."
	return ""

func active() -> bool:
	return lobby != null or peer != null or _login_pending

func is_owner() -> bool:
	return lobby != null and lobby.is_valid() and str(lobby.owner_product_user_id) == product_user_id

# ---------------------------------------------------------------- credentials
static func credential_keys() -> PackedStringArray:
	return PackedStringArray(["product_name", "product_id", "sandbox_id", "deployment_id", "client_id", "client_secret"])

static func credentials_complete(values: Dictionary) -> bool:
	for key in credential_keys():
		if str(values.get(key, "")).strip_edges().is_empty(): return false
	return true

# KEY=value lines; comments, blank lines, `export KEY=`, quotes and CRLF are accepted (same rules as tools/eos_config.py).
static func parse_env(text: String) -> Dictionary:
	var values := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or not "=" in line: continue
		if line.begins_with("export "): line = line.trim_prefix("export ").strip_edges()
		var key := line.get_slice("=", 0).strip_edges()
		var value := line.substr(line.find("=") + 1).strip_edges()
		if value.length() >= 2 and value[0] == value[value.length() - 1] and value[0] in ["\"", "'"]:
			value = value.substr(1, value.length() - 2)
		elif " #" in value:
			value = value.get_slice(" #", 0).strip_edges()
		if not key.is_empty(): values[key] = value
	return values

static func credentials_from_env(values: Dictionary) -> Dictionary:
	var out := {}
	for key in credential_keys():
		out[key] = str(values.get("EOS_" + key.to_upper(), "")).strip_edges()
	out["product_version"] = str(values.get("EOS_PRODUCT_VERSION", "")).strip_edges()
	if out.product_name.is_empty(): out.product_name = "RemZ"
	return out

# res://eos.cfg (written by tools/eos_config.py, packed into the export) wins; the editor also accepts the
# repository's .env directly; environment variables fill any gap (CI). Values are never printed or logged.
func load_credentials() -> Dictionary:
	var values := {}
	var config := ConfigFile.new()
	if config.load(CONFIG) == OK:
		for key in credential_keys(): values[key] = str(config.get_value("eos", key, "")).strip_edges()
		values["product_version"] = str(config.get_value("eos", "product_version", ""))
	if not credentials_complete(values) and OS.has_feature("editor"):
		var env_path := ProjectSettings.globalize_path("res://").path_join("../.env")
		if FileAccess.file_exists(env_path):
			var from_env := credentials_from_env(parse_env(FileAccess.get_file_as_string(env_path)))
			for key in from_env:
				if str(values.get(key, "")).is_empty(): values[key] = from_env[key]
	for key in credential_keys():
		if str(values.get(key, "")).is_empty() and OS.has_environment("EOS_" + key.to_upper()):
			values[key] = OS.get_environment("EOS_" + key.to_upper()).strip_edges()
	if str(values.get("product_name", "")).is_empty(): values["product_name"] = "RemZ"
	return values

# ---------------------------------------------------------------- join codes
static func make_code(rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var out := ""
	for i in CODE_LENGTH: out += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return out

static func normalize_code(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if ch in CODE_ALPHABET: out += ch
	return out

static func valid_code(text: String) -> bool:
	return text.length() == CODE_LENGTH and normalize_code(text) == text

# What a lobby advertises so a teammate on another build is turned away before the P2P handshake.
static func version_tag() -> String:
	return "%d|%s|%s" % [NetSession.PROTOCOL, NetSession.BUILD, NetSession._fingerprint.left(12)]

# ---------------------------------------------------------------- platform and login
# Starts the platform once and signs in with the device id. Returns {"ok": bool, "error": String}.
func ensure_ready(display_name: String) -> Dictionary:
	if not available(): return {"ok": false, "error": unavailable_reason()}
	if _login_pending: return {"ok": false, "error": "The online sign-in is still running. Please wait a moment."}
	if state == "ready" and _logged_in(): return {"ok": true}
	_login_pending = true
	var generation := _generation
	if not _platform_ready:
		state = "starting"
		changed.emit()
		var started: bool = await _start_platform()
		if not started or generation != _generation:
			_login_pending = false
			state = "failed" if not started else "off"
			changed.emit()
			return {"ok": false, "error": "The online service could not be started. Check your internet connection and try again."}
		_platform_ready = true
	var login: Dictionary = await _login(display_name)
	_login_pending = false
	if generation != _generation: return {"ok": false, "error": "Cancelled."}
	state = "ready" if login.ok else "failed"
	changed.emit()
	return login

func _start_platform() -> bool:
	_eos = load(ADDON + "eos.gd")
	_hlobby_script = load(ADDON + "heos/hlobby.gd")
	_ieos = Engine.get_singleton("IEOS")
	if _eos == null or _hlobby_script == null or _ieos == null: return false
	var hplatform := get_node("/root/HPlatform")
	hplatform.flags = _eos.Platform.PlatformFlags.DisableOverlay | _eos.Platform.PlatformFlags.DisableSocialOverlay
	for arg in OS.get_cmdline_user_args():
		# Two processes on one PC (tools/test_online_coop.ps1) must not share the SDK's cache folder.
		if arg.begins_with("--eos-cache="): hplatform.cache_directory = ProjectSettings.globalize_path("user://eosg-cache-" + arg.trim_prefix("--eos-cache=").validate_filename())
	var creds = load(ADDON + "heos/hcredentials.gd").new()
	for key in credential_keys(): creds.set(key, str(credentials[key]))
	creds.product_version = str(credentials.get("product_version", "")) if not str(credentials.get("product_version", "")).is_empty() else NetSession.BUILD
	if not hplatform.log_msg.is_connected(_on_eos_log): hplatform.log_msg.connect(_on_eos_log)
	NetSession.trace_load("EOS_PLATFORM_START")
	var ok: bool = await hplatform.setup_eos_async(creds)
	NetSession.trace_load("EOS_PLATFORM_%s" % ["READY" if ok else "FAILED"])
	if not ok: return false
	_platform_ready = true # from here on _exit_tree must release the platform, whoever started it
	_eos.Logging.set_log_level(_eos.Logging.LogCategory.AllCategories, _eos.Logging.LogLevel.Warning)
	# --eos-force-relay (tests): every packet takes Epic's relay, the path two strict routers would end up on.
	var relay = _eos.P2P.RelayControl.ForceRelays if "--eos-force-relay" in OS.get_cmdline_user_args() else _eos.P2P.RelayControl.AllowRelays
	_eos.P2P.P2PInterface.set_relay_control(relay)
	NetSession.trace_load("EOS_RELAY_CONTROL %s" % ("forced" if relay == _eos.P2P.RelayControl.ForceRelays else "allowed"))
	var queue = _eos.P2P.SetPacketQueueSizeOptions.new()
	queue.incoming_packet_queue_max_size_bytes = QUEUE_BYTES
	queue.outgoing_packet_queue_max_size_bytes = QUEUE_BYTES
	_eos.P2P.P2PInterface.set_packet_queue_size(queue)
	return true

func _on_eos_log(msg) -> void:
	# level 300 = Warning; everything louder than that is kept for the diagnostics file
	if int(msg.level) > 300: return
	var line := "EOS %s: %s" % [str(msg.category), str(msg.message)]
	log_lines.append(line)
	if log_lines.size() > 60: log_lines.pop_front()
	NetSession.trace_load(line)

func _logged_in() -> bool:
	if product_user_id.is_empty() or _eos == null: return false
	return int(_eos.Connect.ConnectInterface.get_login_status(product_user_id)) == int(_eos.LoginStatus.LoggedIn)

# Connect Device ID: the SDK keeps an anonymous credential in the Windows user's keychain, the first login
# creates the product user. --eos-fresh-device throws the stored credential away first (a second identity
# for two processes on one PC, tests only).
func _login(display_name: String) -> Dictionary:
	var timeout_error := {"ok": false, "error": "The online service did not answer. Check your internet connection and try again."}
	if "--eos-fresh-device" in OS.get_cmdline_user_args():
		_eos.Connect.ConnectInterface.delete_device_id(_eos.Connect.DeleteDeviceIdOptions.new())
		await _wait(Signal(_ieos, "connect_interface_delete_device_id_callback"), STEP_TIMEOUT)
	var create = _eos.Connect.CreateDeviceIdOptions.new()
	create.device_model = ("%s %s" % [OS.get_name(), OS.get_model_name()]).left(64)
	_eos.Connect.ConnectInterface.create_device_id(create)
	var created = await _wait(Signal(_ieos, "connect_interface_create_device_id_callback"), STEP_TIMEOUT)
	if created == null: return timeout_error
	var rc := int(created.get("result_code", -1))
	if rc != RESULT_SUCCESS and rc != RESULT_DUPLICATE:
		return _failure("EOS_DEVICE_ID", rc, "The online sign-in failed (%s). Try again in a moment.")
	var opts = _eos.Connect.LoginOptions.new()
	opts.credentials = _eos.Connect.Credentials.new()
	opts.credentials.type = _eos.ExternalCredentialType.DeviceidAccessToken
	opts.credentials.token = null
	opts.user_login_info = _eos.Connect.UserLoginInfo.new()
	opts.user_login_info.display_name = display_name.left(32)
	_eos.Connect.ConnectInterface.login(opts)
	var login = await _wait(Signal(_ieos, "connect_interface_login_callback"), STEP_TIMEOUT)
	if login == null: return timeout_error
	rc = int(login.get("result_code", -1))
	var puid := str(login.get("local_user_id", ""))
	if rc == RESULT_INVALID_USER:
		var user = _eos.Connect.CreateUserOptions.new()
		user.continuance_token = login.get("continuance_token")
		_eos.Connect.ConnectInterface.create_user(user)
		var made = await _wait(Signal(_ieos, "connect_interface_create_user_callback"), STEP_TIMEOUT)
		if made == null: return timeout_error
		rc = int(made.get("result_code", -1))
		puid = str(made.get("local_user_id", ""))
	if rc != RESULT_SUCCESS or puid.is_empty():
		return _failure("EOS_LOGIN", rc, "The online sign-in failed (%s). The service may be down or this build may not be registered.")
	product_user_id = puid
	# HAuth re-runs this login when the token nears expiry (about an hour) and HLobbies reads the user from it.
	var hauth := get_node("/root/HAuth")
	hauth.product_user_id = puid
	hauth.display_name = display_name
	hauth._last_connect_login_opts = opts
	NetSession.trace_load("EOS_LOGIN_OK")
	return {"ok": true}

func _failure(stage: String, rc: int, template: String) -> Dictionary:
	var name := str(_eos.result_str(rc)) if _eos else str(rc)
	NetSession.trace_load("%s_FAILED result=%s" % [stage, name])
	return {"ok": false, "error": Lang.t(template, [Lang.raw(name)])}

# ---------------------------------------------------------------- lobby
# Opens a public lobby carrying the join code, our version tag and the host name.
func create_lobby(host_name: String, version: String) -> Dictionary:
	if not _logged_in(): return {"ok": false, "error": "Not signed in to the online service."}
	var generation := _generation
	var opts = _eos.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = BUCKET
	opts.max_lobby_members = NetSession.MAX_PLAYERS
	opts.permission_level = _eos.Lobby.LobbyPermissionLevel.PublicAdvertised
	opts.presence_enabled = false
	opts.allow_invites = false
	opts.enable_join_by_id = false
	opts.disable_host_migration = true
	opts.enable_rtc_room = false
	opts.local_user_id = product_user_id
	_eos.Lobby.LobbyInterface.create_lobby(opts)
	var ret = await _wait(Signal(_ieos, "lobby_interface_create_lobby_callback"), STEP_TIMEOUT)
	if ret == null: return {"ok": false, "error": "The online service did not answer while creating the lobby."}
	var rc := int(ret.get("result_code", -1))
	if rc != RESULT_SUCCESS: return _failure("EOS_LOBBY_CREATE", rc, "The lobby could not be created (%s).")
	var lobby_id := str(ret.get("lobby_id", ""))
	var new_code := make_code()
	var applied: Dictionary = await _apply_attributes(lobby_id, {ATTR_CODE: new_code, ATTR_VERSION: version, ATTR_HOST: host_name.left(24)})
	if generation != _generation:
		_release_lobby_id(lobby_id, true)
		return {"ok": false, "error": "Cancelled."}
	if not applied.ok:
		_release_lobby_id(lobby_id, true)
		return applied
	lobby = _hlobby_script.new()
	lobby.init_from_id(lobby_id)
	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.kicked_from_lobby.connect(_on_lobby_lost)
	code = new_code
	NetSession.trace_load("EOS_LOBBY_CREATED code=%s" % code)
	changed.emit()
	return {"ok": true, "code": code}

func _apply_attributes(lobby_id: String, attributes: Dictionary) -> Dictionary:
	var mod_opts = _eos.Lobby.UpdateLobbyModificationOptions.new()
	mod_opts.lobby_id = lobby_id
	mod_opts.local_user_id = product_user_id
	var mod_ret = _eos.Lobby.LobbyInterface.update_lobby_modification(mod_opts)
	if not _eos.is_success(mod_ret): return _failure("EOS_LOBBY_MODIFY", int(mod_ret.get("result_code", -1)), "The lobby could not be set up (%s).")
	var modification = mod_ret.lobby_modification
	for key in attributes:
		modification.add_attribute(key, str(attributes[key]), _eos.Lobby.LobbyAttributeVisibility.Public)
	var update = _eos.Lobby.UpdateLobbyOptions.new()
	update.lobby_modification = modification
	_eos.Lobby.LobbyInterface.update_lobby(update)
	var ret = await _wait(Signal(_ieos, "lobby_interface_update_lobby_callback"), STEP_TIMEOUT)
	if ret == null: return {"ok": false, "error": "The online service did not answer while setting up the lobby."}
	var rc := int(ret.get("result_code", -1))
	if rc != RESULT_SUCCESS: return _failure("EOS_LOBBY_UPDATE", rc, "The lobby could not be set up (%s).")
	return {"ok": true}

# Finds the lobby behind a join code. Returns {"ok", "lobby", "host_name", "version"} or an error. The search
# index trails a fresh lobby - usually by a second, sometimes by more than five - so an empty answer is asked
# again for about ten seconds before it counts.
func find_lobby(wanted: String, attempts: int = 6) -> Dictionary:
	var generation := _generation
	var result: Dictionary = {}
	for attempt in maxi(1, attempts):
		if attempt > 0:
			await get_tree().create_timer(2.0).timeout
			if generation != _generation: return {"ok": false, "error": "Cancelled."}
		result = await _search_once(wanted)
		if result.ok or not bool(result.get("retry", false)): break
	result.erase("retry")
	return result

func _search_once(wanted: String) -> Dictionary:
	if not _logged_in(): return {"ok": false, "error": "Not signed in to the online service."}
	var search_opts = _eos.Lobby.CreateLobbySearchOptions.new()
	search_opts.max_results = 10
	var created = _eos.Lobby.LobbyInterface.create_lobby_search(search_opts)
	if not _eos.is_success(created): return _failure("EOS_LOBBY_SEARCH", int(created.get("result_code", -1)), "The lobby search failed (%s).")
	var search = created.lobby_search
	search.set_parameter(_eos.Lobby.SEARCH_BUCKET_ID, BUCKET, _eos.ComparisonOp.Equal)
	search.set_parameter(ATTR_CODE, wanted, _eos.ComparisonOp.Equal)
	search.find(product_user_id)
	var ret = await _wait(Signal(_ieos, "lobby_search_find_callback"), STEP_TIMEOUT)
	if ret == null: return {"ok": false, "error": "The online service did not answer while looking for the lobby."}
	var rc := int(ret.get("result_code", -1))
	if rc != RESULT_SUCCESS and rc != RESULT_NOT_FOUND: return _failure("EOS_LOBBY_SEARCH", rc, "The lobby search failed (%s).")
	var count := int(search.get_search_result_count())
	var mine := version_tag()
	var other_version := ""
	var full := false
	for index in count:
		var copied = search.copy_search_result_by_index(index)
		if not _eos.is_success(copied): continue
		var candidate = _hlobby_script.new()
		candidate._init_from_details(copied.lobby_details)
		var version := str(candidate.get_attribute(ATTR_VERSION).get("value", ""))
		if version != mine:
			other_version = version
			continue
		if int(candidate.available_slots) <= 0:
			full = true
			continue
		NetSession.trace_load("EOS_LOBBY_FOUND code=%s" % wanted)
		return {"ok": true, "lobby": candidate, "host_name": str(candidate.get_attribute(ATTR_HOST).get("value", "")), "version": version}
	NetSession.trace_load("EOS_LOBBY_SEARCH_EMPTY code=%s results=%d" % [wanted, count])
	if full: return {"ok": false, "error": Lang.t("Lobby %s is full (%d/%d players).", [Lang.raw(wanted), NetSession.MAX_PLAYERS, NetSession.MAX_PLAYERS])}
	if not other_version.is_empty(): return {"ok": false, "error": "The host runs a different RemZ version. Host and teammates need the same build."}
	return {"ok": false, "retry": true, "error": Lang.t("No open lobby with code %s. Check the code - the host must still be in the lobby.", [Lang.raw(wanted)])}

# Joins a lobby returned by find_lobby. Returns {"ok", "host_id"} or an error.
func join_lobby(found) -> Dictionary:
	if found == null or not _logged_in(): return {"ok": false, "error": "Not signed in to the online service."}
	var generation := _generation
	var opts = _eos.Lobby.JoinLobbyOptions.new()
	opts.lobby_details = found._lobby_details
	opts.presence_enabled = false
	opts.local_user_id = product_user_id
	_eos.Lobby.LobbyInterface.join_lobby(opts)
	var ret = await _wait(Signal(_ieos, "lobby_interface_join_lobby_callback"), STEP_TIMEOUT)
	if ret == null: return {"ok": false, "error": "The online service did not answer while joining the lobby."}
	var rc := int(ret.get("result_code", -1))
	if rc == RESULT_LOBBY_TOO_MANY_PLAYERS: return {"ok": false, "error": Lang.t("This lobby is full (%d/%d players).", [NetSession.MAX_PLAYERS, NetSession.MAX_PLAYERS])}
	if rc != RESULT_SUCCESS: return _failure("EOS_LOBBY_JOIN", rc, "Could not join the lobby (%s). The host may have left.")
	var lobby_id := str(ret.get("lobby_id", ""))
	if generation != _generation:
		_release_lobby_id(lobby_id, false)
		return {"ok": false, "error": "Cancelled."}
	lobby = _hlobby_script.new()
	lobby.init_from_id(lobby_id)
	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.kicked_from_lobby.connect(_on_lobby_lost)
	code = str(lobby.get_attribute(ATTR_CODE).get("value", ""))
	var host_id := str(lobby.owner_product_user_id)
	NetSession.trace_load("EOS_LOBBY_JOINED code=%s" % code)
	changed.emit()
	if host_id.is_empty(): return {"ok": false, "error": "The lobby has no host any more."}
	return {"ok": true, "host_id": host_id}

func members() -> Array:
	var ids: Array = []
	if lobby and lobby.is_valid():
		for member in lobby.members: ids.append(str(member.product_user_id))
	return ids

func _on_lobby_updated() -> void:
	if not _requests.is_empty(): _review_requests()
	changed.emit()

func _on_lobby_lost() -> void:
	NetSession.trace_load("EOS_LOBBY_LOST")
	lobby = null
	code = ""
	changed.emit()

# ---------------------------------------------------------------- P2P peers
func make_server_peer():
	var candidate = ClassDB.instantiate("EOSGMultiplayerPeer")
	if candidate == null: return null
	candidate.set_auto_accept_connection_requests(false)
	candidate.incoming_connection_request.connect(_on_connection_request)
	var error: int = candidate.create_server(SOCKET)
	if error != OK:
		NetSession.trace_load("EOS_PEER_SERVER_FAILED error=%d" % error)
		return null
	peer = candidate
	_requests.clear()
	return candidate

func make_client_peer(host_id: String):
	var candidate = ClassDB.instantiate("EOSGMultiplayerPeer")
	if candidate == null or host_id.is_empty(): return null
	var error: int = candidate.create_client(SOCKET, host_id)
	if error != OK:
		NetSession.trace_load("EOS_PEER_CLIENT_FAILED error=%d" % error)
		return null
	peer = candidate
	return candidate

func _on_connection_request(_data) -> void:
	_review_requests()

# Only lobby members get through the P2P door. A member whose join has not reached us yet stays pending
# for REQUEST_GRACE seconds (the lobby update re-runs this), anyone else is turned away.
func _review_requests() -> void:
	if peer == null or not is_instance_valid(peer):
		_requests.clear()
		return
	var known := members()
	var waiting: Dictionary = {}
	for request in peer.get_all_connection_requests():
		var user := str(request.get("remote_user_id", "")) if request is Dictionary else str(request)
		if user.is_empty(): continue
		if known.has(user):
			peer.accept_connection_request(user)
			NetSession.trace_load("EOS_P2P_ACCEPTED")
		elif _elapsed - float(_requests.get(user, _elapsed)) > REQUEST_GRACE:
			peer.deny_connection_request(user)
			NetSession.trace_load("EOS_P2P_DENIED")
		else:
			waiting[user] = _requests.get(user, _elapsed)
	_requests = waiting

# ---------------------------------------------------------------- leaving
func cancel() -> void:
	_generation += 1

# Called by NetSession after it detached and closed the MultiplayerPeer: forget the peer, drop the lobby.
func leave() -> void:
	_generation += 1
	_login_pending = false
	peer = null
	_requests.clear()
	var current = lobby
	lobby = null
	code = ""
	if current != null and current.is_valid():
		_release_lobby_id(str(current.lobby_id), str(current.owner_product_user_id) == product_user_id)
	changed.emit()

func _release_lobby_id(lobby_id: String, owner: bool) -> void:
	if lobby_id.is_empty() or _eos == null: return
	if owner:
		var destroy = _eos.Lobby.DestroyLobbyOptions.new()
		destroy.lobby_id = lobby_id
		destroy.local_user_id = product_user_id
		_eos.Lobby.LobbyInterface.destroy_lobby(destroy)
	else:
		var leave_opts = _eos.Lobby.LeaveLobbyOptions.new()
		leave_opts.lobby_id = lobby_id
		leave_opts.local_user_id = product_user_id
		_eos.Lobby.LobbyInterface.leave_lobby(leave_opts)
	NetSession.trace_load("EOS_LOBBY_%s" % ["DESTROY" if owner else "LEAVE"])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and lobby != null: leave()

# Godot never returns from quit() while a created EOS platform is still alive (the SDK's threads keep the
# process up), so the platform is released here, when the autoloads leave the tree at shutdown.
func _exit_tree() -> void:
	if not _platform_ready or _eos == null: return
	# NetSession may already have left the tree (autoloads unload in reverse order): ask the tree itself.
	var api: MultiplayerAPI = get_tree().get_multiplayer() if get_tree() else null
	if api != null and api.multiplayer_peer != null and api.multiplayer_peer.get_class() == "EOSGMultiplayerPeer":
		api.multiplayer_peer.close()
		api.multiplayer_peer = OfflineMultiplayerPeer.new()
	if lobby != null: leave()
	# Give the leave / destroy request a moment on the wire; the backend closes an orphaned lobby anyway.
	for i in 10:
		_ieos.tick()
		OS.delay_msec(30)
	_eos.Platform.PlatformInterface.release()
	_eos.Platform.PlatformInterface.shutdown()
	_platform_ready = false
	state = "off"

# ---------------------------------------------------------------- helpers
# Awaits one emission of an EOS callback signal (its Dictionary), null after `seconds`.
func _wait(sig: Signal, seconds: float):
	var box := [null, false]
	var handler := func(data = null):
		box[0] = data
		box[1] = true
	sig.connect(handler, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not box[1] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not box[1] and sig.is_connected(handler): sig.disconnect(handler)
	return box[0]

# `RemZ.exe --headless -- --eos-check`: starts the platform, signs in, opens and finds a lobby, prints
# EOS_CHECK lines (never a credential) and quits. Used on the packed build after every export.
func _run_check() -> void:
	await get_tree().process_frame
	print("EOS_CHECK runtime=%s credentials=%s" % [runtime_loaded(), credentials_complete(credentials)])
	var ok := false
	if available():
		var ready: Dictionary = await ensure_ready("Check")
		print("EOS_CHECK login=%s puid=%s" % [ready.ok, "set" if not product_user_id.is_empty() else "none"])
		if ready.ok:
			_eos.P2P.P2PInterface.query_nat_type()
			var nat = await _wait(Signal(_ieos, "p2p_interface_query_nat_type_callback"), STEP_TIMEOUT)
			print("EOS_CHECK nat_type=%s" % (str(nat.get("nat_type", "?")) if nat else "timeout"))
			var created: Dictionary = await create_lobby("Check", version_tag())
			print("EOS_CHECK lobby=%s code=%s" % [created.ok, created.get("code", "")])
			if created.ok:
				var found: Dictionary = await find_lobby(created.code)
				print("EOS_CHECK search=%s host=%s" % [found.ok, found.get("host_name", "")])
				ok = found.ok
				leave()
				await get_tree().create_timer(1.0).timeout
	else:
		print("EOS_CHECK reason=", Lang.resolve(unavailable_reason(), "en"))
	print("EOS_CHECK_DONE ok=%s" % ok)
	get_tree().quit(0 if ok else 1)
