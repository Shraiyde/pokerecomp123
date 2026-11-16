class_name Gen2NetworkLinkTransport
extends Gen2LinkTransport

## The cable over a network: the same three operations the local transport
## offers, but the peer is the other game instance on the far end of the
## public MQTT broker, not another save slot on this machine. One player hosts
## and the other joins with the four-digit room code; the broker is the relay,
## so the two phones only need the same code and an internet connection.
##
## The link protocol is turn-based and synchronous — the session calls
## `exchange` and expects the peer's block back — so the transport keeps the
## peer's last block cached and answers from it, the way the local transport
## answers from a save slot. The network keeps that cache fresh: a `hello`
## when the room is joined, a `block` whenever this side's state is sent, and
## a heartbeat every few seconds carrying the current block. A message is a
## full snapshot, so a missed one is healed by the next.
##
## Reliability is threefold. Ordering: every message carries a per-sender
## sequence number; a duplicate or an older sequence is ignored, and the
## per-topic order the broker already gives is checked against it. Disconnect
## detection: a heartbeat every few seconds, and a peer unheard from for
## [constant PEER_TIMEOUT_MS] is gone — the session sees the same drop a
## pulled cable gives. Reconnection: the MQTT client re-opens, re-subscribes
## and re-hellos on its own, so a brief network blip re-joins the room and
## the cached peer comes back without the player doing anything.

## The room topic: `pokerecomp/link/<code>`. Both sides publish here and both
## subscribe, and each message names its sender so a side ignores its own echo.
const TOPIC_PREFIX: String = "pokerecomp/link/"
## Seconds between heartbeats while a room is joined.
const HEARTBEAT_SECONDS: float = 5.0
## A peer unheard from for this long is gone.
const PEER_TIMEOUT_MS: int = 15000

const MSG_HELLO: String = "hello"
const MSG_BLOCK: String = "block"
const MSG_NYBBLE: String = "nybble"
const MSG_ROOM: String = "room"
const MSG_TRADE_SLOT: String = "trade_slot"
const MSG_HEARTBEAT: String = "heartbeat"
const MSG_BYE: String = "bye"

const ROLE_HOST: String = "host"
const ROLE_JOIN: String = "join"

## This side's own peer block, the mirror of the save slot the local transport
## answers from: name, id, gender, generation, party and room.
var local_peer: Dictionary = {}
var room_code: String = ""
var role: String = ROLE_HOST

var _mqtt: Gen2MqttClient = null
var _next_seq: int = 1
var _last_seq: int = 0
var _last_nybble: int = -1
var _peer_trade_slot: int = -1
var _last_peer_ms: int = 0
var _last_heartbeat_ms: int = 0
var _started: bool = false


## A host transport: a fresh four-digit room code, the internal clock, and a
## client that joins the room topic. [param local] is this side's peer block.
static func host(local: Dictionary) -> Gen2NetworkLinkTransport:
	var transport := Gen2NetworkLinkTransport.new()
	transport.role = ROLE_HOST
	transport.room_code = _new_room_code()
	transport.local_peer = (local as Dictionary).duplicate(true)
	transport.local_peer["room"] = CABLECLUBROOM_NULL
	return transport


## A join transport: the room code the host showed, the external clock.
static func join(code: String, local: Dictionary) -> Gen2NetworkLinkTransport:
	var transport := Gen2NetworkLinkTransport.new()
	transport.role = ROLE_JOIN
	transport.room_code = code.strip_edges()
	transport.local_peer = (local as Dictionary).duplicate(true)
	transport.local_peer["room"] = CABLECLUBROOM_NULL
	return transport


static func _new_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return str(rng.randi_range(1000, 9999))


func topic() -> String:
	return TOPIC_PREFIX + room_code


func is_host() -> bool:
	return role == ROLE_HOST


## Opens the broker connection and subscribes to the room. The peer arrives
## through `hello`; until then this is a cable with nobody on the other end.
func start() -> void:
	if _started:
		return
	_started = true
	_mqtt = Gen2MqttClient.new()
	_mqtt.message_received.connect(_on_message)
	_mqtt.connected.connect(_on_mqtt_connected)
	_mqtt.disconnected.connect(_on_mqtt_disconnected)
	_mqtt.connect_to_broker()
	_mqtt.subscribe(topic())
	_last_heartbeat_ms = Time.get_ticks_msec()


## Pumps the broker, sends the heartbeat and drops a peer unheard from for
## [constant PEER_TIMEOUT_MS]. Call once a drawn frame.
func poll() -> void:
	if _mqtt == null:
		return
	_mqtt.poll()
	if not _mqtt.is_broker_connected():
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_heartbeat_ms >= int(HEARTBEAT_SECONDS * 1000.0):
		_last_heartbeat_ms = now
		_send(MSG_HEARTBEAT, {})
	if connected() and now - _last_peer_ms >= PEER_TIMEOUT_MS:
		peer = {}
		clock = CONNECTION_NOT_ESTABLISHED


func connected() -> bool:
	if peer.is_empty():
		return false
	return Time.get_ticks_msec() - _last_peer_ms < PEER_TIMEOUT_MS


## `hSerialConnectionStatus`. The host holds the internal clock and the joiner
## the external one, the way the two ends of a cable do.
func status() -> int:
	if not connected():
		return CONNECTION_NOT_ESTABLISHED
	clock = USING_INTERNAL_CLOCK if is_host() else USING_EXTERNAL_CLOCK
	return clock


## `Link_EnsureSync`: this side's nybble goes out and the peer's last one
## comes back. `-1` is no peer, which the caller reads as no cable.
func exchange_nybble(value: int) -> int:
	if not connected():
		return -1
	_send(MSG_NYBBLE, {"value": value & 0xF})
	return peer_nybble(value)


## The peer's last nybble, or the proposed one when none has arrived yet —
## the same agreement the local transport gives.
func peer_nybble(value: int) -> int:
	return _last_nybble if _last_nybble >= 0 else value


## `Serial_ExchangeBytes`: this side's block goes out and the peer's cached
## one comes back. Empty means the cable dropped.
func exchange(payload: Dictionary) -> Dictionary:
	if not connected():
		return {}
	if payload.has("room"):
		set_local_room(int(payload.get("room", CABLECLUBROOM_NULL)))
	_send(MSG_BLOCK, {"peer": local_peer})
	return peer_block(payload)


## The peer's cached block, or empty when nobody is there.
func peer_block(_payload: Dictionary) -> Dictionary:
	return peer.duplicate(true) if connected() else {}


## The room the peer walked up to, from its cached block, or the chosen room
## when the peer has not said yet — the same agreement the local transport gives.
func peer_room(chosen_room: int) -> int:
	return int(peer.get("room", chosen_room)) if connected() else chosen_room


## The row the peer offered, or the base fallback when it has not said yet.
func choose_trade_slot(context: Dictionary) -> int:
	if _peer_trade_slot >= 0:
		var rows: int = int(context.get("ot_count", 0))
		if rows > 0:
			return clampi(_peer_trade_slot, 0, rows - 1)
	return super.choose_trade_slot(context)


## This side's room, published at once so the peer's `peer_room` sees it
## before the receptionist asks again.
func set_local_room(room: int) -> void:
	local_peer["room"] = room
	if _mqtt != null and _mqtt.is_broker_connected():
		_send(MSG_ROOM, {"room": room, "peer": local_peer})


## This side's offered row, published at once so the peer's `choose_trade_slot`
## sees it.
func set_local_trade_slot(slot: int) -> void:
	if _mqtt != null and _mqtt.is_broker_connected():
		_send(MSG_TRADE_SLOT, {"slot": slot})


## `Link_ResetSerialRegistersAfterLinkClosure`. The peer is told, the clock is
## forgotten and the broker connection closes; a new session starts a new
## transport.
func close() -> void:
	if _mqtt != null and _mqtt.is_broker_connected():
		_send(MSG_BYE, {})
	clock = CONNECTION_NOT_ESTABLISHED
	peer = {}
	_last_nybble = -1
	_peer_trade_slot = -1
	if _mqtt != null:
		_mqtt.disconnect_from_broker()
		_mqtt = null
	_started = false


func _on_mqtt_connected() -> void:
	_send(MSG_HELLO, {"peer": local_peer})


func _on_mqtt_disconnected() -> void:
	pass


## A message from the room, ignored when it is this side's own echo or a
## duplicate. Each message is a full snapshot, so a gap is healed by the next
## one that arrives.
func _on_message(_topic: String, payload: PackedByteArray) -> void:
	var text: String = payload.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var msg: Dictionary = parsed
	if String(msg.get("from", "")) == role:
		return
	var seq: int = int(msg.get("seq", 0))
	if seq > 0 and seq <= _last_seq:
		return
	if seq > 0:
		_last_seq = seq
	_last_peer_ms = Time.get_ticks_msec()
	match String(msg.get("type", "")):
		MSG_HELLO, MSG_BLOCK, MSG_HEARTBEAT:
			var incoming: Dictionary = msg.get("peer", {})
			if not incoming.is_empty():
				peer = (incoming as Dictionary).duplicate(true)
			if String(msg.get("type", "")) == MSG_HELLO:
				_send(MSG_HELLO, {"peer": local_peer})
		MSG_NYBBLE:
			_last_nybble = int(msg.get("value", 0)) & 0xF
		MSG_ROOM:
			var incoming_room: Dictionary = msg.get("peer", {})
			if not incoming_room.is_empty():
				peer = (incoming_room as Dictionary).duplicate(true)
			else:
				peer["room"] = int(msg.get("room", CABLECLUBROOM_NULL))
		MSG_TRADE_SLOT:
			_peer_trade_slot = int(msg.get("slot", -1))
		MSG_BYE:
			peer = {}
			clock = CONNECTION_NOT_ESTABLISHED
			_last_nybble = -1
			_peer_trade_slot = -1


func _send(type: String, fields: Dictionary) -> void:
	if _mqtt == null:
		return
	var msg: Dictionary = {"type": type, "from": role, "seq": _next_seq}
	_next_seq += 1
	for key: String in fields:
		msg[key] = fields[key]
	var text: String = JSON.stringify(msg)
	_mqtt.publish(topic(), text.to_utf8_buffer(), 1)
