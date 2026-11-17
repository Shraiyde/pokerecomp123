class_name Gen3CoopTransport
extends RefCounted

## Phone-to-phone co-op for a Gen 3 game, the recomp's version of the
## ROM's `HnsCoopMailbox` (`overworld.c`): two players, each on their own
## phone and their own game, share one story. Flags and vars set on one
## side are queued to the other and applied there, so gym badges, story
## beats and Mom's errands land in both games. The relay is the same
## public MQTT broker the link cable uses: the host shows a four-digit
## PIN, the other player joins with it, and the two phones only need the
## same PIN and an internet connection.
##
## Sync is snapshot-diff, the mailbox's flag/var queues by another name:
## each frame the local flags/vars are compared with the last snapshot
## sent, and only the changes go out. An incoming change is applied and
## merged into the sent snapshot, so it is never echoed back. A `hello`
## asks the peer for a full snapshot, which is how a late joiner catches
## up with a story already in progress.

const TOPIC_PREFIX: String = "pokerecomp/coop/"
const PEER_TIMEOUT_MS: int = 15000

var room_code: String = ""
var role: String = "host"
var peer_name: String = ""

var _mqtt: Gen2MqttClient = null
var _id: String = ""
var _events: Gen3EventData = null
var _sent_flags: Dictionary = {}
var _sent_vars: Dictionary = {}
var _need_full: bool = true
var _last_peer_ms: int = 0
var _started: bool = false
## Battle and trade messages for the link UI, oldest first; the story
## sync consumes its own types straight into the event data.
var inbox: Array = []


static func host() -> Gen3CoopTransport:
	var transport := Gen3CoopTransport.new()
	transport.role = "host"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	transport.room_code = str(rng.randi_range(1000, 9999))
	return transport


static func join(code: String) -> Gen3CoopTransport:
	var transport := Gen3CoopTransport.new()
	transport.role = "join"
	transport.room_code = code.strip_edges()
	return transport


func topic() -> String:
	return TOPIC_PREFIX + room_code


func is_host() -> bool:
	return role == "host"


func connected() -> bool:
	return _last_peer_ms > 0 and Time.get_ticks_msec() - _last_peer_ms < PEER_TIMEOUT_MS


## Opens the broker connection and subscribes to the room topic.
func start() -> void:
	if _started:
		return
	_started = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_id = "%08x" % rng.randi()
	_mqtt = Gen2MqttClient.new()
	_mqtt.message_received.connect(_on_message)
	_mqtt.connected.connect(_on_connected)
	_mqtt.connect_to_broker()
	_mqtt.subscribe(topic())


func close() -> void:
	if _mqtt != null:
		if _mqtt.is_broker_connected():
			_send("bye", {})
		_mqtt.disconnect_from_broker()
		_mqtt = null
	_started = false
	_last_peer_ms = 0
	peer_name = ""


## Pumps the broker and pushes any local flag/var changes to the peer.
## Call once a frame with the field's live event data.
func poll(events: Gen3EventData) -> void:
	if _mqtt == null:
		return
	_events = events
	_mqtt.poll()
	if events == null or not _mqtt.is_broker_connected():
		return
	var snapshot: Dictionary = events.to_dict()
	var flags_now: Dictionary = {}
	for id: Variant in snapshot["flags"]:
		flags_now[int(id)] = true
	var vars_now: Dictionary = {}
	for pair: Variant in snapshot["vars"]:
		vars_now[int((pair as Array)[0])] = int((pair as Array)[1])
	if _need_full:
		_send("sync", {"full": true, "name": events.player_name,
			"flags": flags_now.keys(), "clears": [], "vars": _var_pairs(vars_now)})
		_sent_flags = flags_now
		_sent_vars = vars_now
		_need_full = false
		return
	var added: Array = []
	var cleared: Array = []
	for id: int in flags_now:
		if not _sent_flags.has(id):
			added.append(id)
	for id: int in _sent_flags:
		if not flags_now.has(id):
			cleared.append(id)
	var changed: Dictionary = {}
	for id: int in vars_now:
		if int(_sent_vars.get(id, -1)) != int(vars_now[id]):
			changed[id] = int(vars_now[id])
	if added.is_empty() and cleared.is_empty() and changed.is_empty():
		return
	_send("sync", {"full": false, "name": events.player_name,
		"flags": added, "clears": cleared, "vars": _var_pairs(changed)})
	_sent_flags = flags_now
	_sent_vars = vars_now


func _var_pairs(vars_now: Dictionary) -> Array:
	var out: Array = []
	for id: int in vars_now:
		out.append([id, int(vars_now[id])])
	return out


func _on_connected() -> void:
	_send("hello", {"name": _events.player_name if _events != null else ""})
	_need_full = true


func _on_message(_topic: String, payload: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var msg: Dictionary = parsed
	if String(msg.get("from", "")) == _id:
		return
	_last_peer_ms = Time.get_ticks_msec()
	match String(msg.get("type", "")):
		"hello":
			peer_name = String(msg.get("name", ""))
			_need_full = true # A (re)joining peer gets the full story.
			if not bool(msg.get("reply", false)):
				_send("hello", {"name": _events.player_name if _events != null else "",
					"reply": true})
		"sync":
			peer_name = String(msg.get("name", peer_name))
			_apply(msg)
		"bye":
			_last_peer_ms = 0
			peer_name = ""
		"battle", "battle_accept", "battle_decline", "round", "trade", "trade_accept", "trade_decline":
			inbox.append(msg)


## Applies the peer's changes locally and folds them into the sent
## snapshot, so nothing the peer sent is ever echoed back to them.
func _apply(msg: Dictionary) -> void:
	if _events == null:
		return
	for id: Variant in msg.get("flags", []):
		_events.flag_set(int(id))
	for id: Variant in msg.get("clears", []):
		_events.flag_clear(int(id))
	for pair: Variant in msg.get("vars", []):
		if pair is Array and (pair as Array).size() == 2:
			_events.var_set(int((pair as Array)[0]), int((pair as Array)[1]))
	var snapshot: Dictionary = _events.to_dict()
	_sent_flags.clear()
	for id: Variant in snapshot["flags"]:
		_sent_flags[int(id)] = true
	_sent_vars.clear()
	for pair: Variant in snapshot["vars"]:
		_sent_vars[int((pair as Array)[0])] = int((pair as Array)[1])
	_need_full = false


## The party in link shape: species, level and moves only, the same
## rows both ends build combatants from.
static func compact_party(party: Array) -> Array:
	var out: Array = []
	var index: int = 0
	for mon: Variant in party:
		var row: int = index
		index += 1
		if not mon is Dictionary:
			continue
		out.append({"i": row, "egg": bool((mon as Dictionary).get("egg", false)),
			"species": int((mon as Dictionary).get("species", 0)),
			"level": int((mon as Dictionary).get("level", 5)),
			"moves": ((mon as Dictionary).get("moves", []) as Array).duplicate()})
	return out


## One link-protocol message (battle challenge, round choice, trade
## offer): the story sync keeps its own sender.
func send_link(type: String, fields: Dictionary) -> void:
	_send(type, fields)


func _send(type: String, fields: Dictionary) -> void:
	if _mqtt == null:
		return
	var msg: Dictionary = {"type": type, "from": _id}
	for key: String in fields:
		msg[key] = fields[key]
	_mqtt.publish(topic(), JSON.stringify(msg).to_utf8_buffer(), 1)
