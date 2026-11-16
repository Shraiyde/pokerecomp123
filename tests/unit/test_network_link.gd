extends GutTest

## The network cable without a broker: the transport's own answers, its
## message ordering, and the disconnect it reports when the peer goes quiet.
##
## No socket is opened here. The transport is fed the JSON a peer would have
## published, straight into `_on_message`, which is the whole of what the
## broker delivers. The MQTT client's own handshake is a live-broker concern
## and is not faked.

const ROOM: String = "1234"


func _local_peer() -> Dictionary:
	return {
		"name": "RED", "id": 1234, "gender": 0,
		"generation": Gen2LinkTransport.GENERATION_2,
		"room": Gen2LinkSession.CABLECLUBROOM_NULL,
		"party": [{"species": 1, "level": 5, "hp": 20}],
	}


func _peer_block() -> Dictionary:
	return {
		"name": "BLUE", "id": 4242, "gender": 0,
		"generation": Gen2LinkTransport.GENERATION_2,
		"room": Gen2LinkSession.CABLECLUBROOM_TRADECENTER,
		"party": [{"species": 4, "level": 5, "hp": 20}],
	}


## A message the peer published, as the broker would deliver it.
func _msg(
	type: String, seq: int, from: String = "join", fields: Dictionary = {}
) -> PackedByteArray:
	var msg: Dictionary = {"type": type, "from": from, "seq": seq}
	for key: String in fields:
		msg[key] = fields[key]
	return JSON.stringify(msg).to_utf8_buffer()


func _host() -> Gen2NetworkLinkTransport:
	return Gen2NetworkLinkTransport.host(_local_peer())


## A host makes its own four-digit room code.
func test_host_generates_a_four_digit_room_code() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	assert_eq(transport.room_code.length(), 4)
	assert_true(transport.room_code.is_valid_int())
	assert_true(transport.is_host())


## A joiner uses the code it was given.
func test_join_uses_the_given_room_code() -> void:
	var transport: Gen2NetworkLinkTransport = Gen2NetworkLinkTransport.join(
		ROOM, _local_peer()
	)
	assert_eq(transport.room_code, ROOM)
	assert_false(transport.is_host())


## No peer, no connection: the receptionist's FALSE, the same as a cable
## with nobody on the other end.
func test_a_transport_with_no_peer_never_connects() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	assert_false(transport.connected())
	assert_eq(
		transport.status(), Gen2LinkTransport.CONNECTION_NOT_ESTABLISHED
	)
	assert_eq(transport.exchange({}), {})
	assert_eq(transport.exchange_nybble(4), -1)


## A hello populates the peer: name, party and room, the way the local
## transport answers from a save slot.
func test_hello_populates_the_peer() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	assert_true(transport.connected())
	assert_eq(String(transport.peer.get("name", "")), "BLUE")
	assert_eq(
		(transport.peer.get("party", []) as Array).size(), 1
	)
	assert_eq(
		int(transport.peer.get("room", 0)),
		Gen2LinkSession.CABLECLUBROOM_TRADECENTER
	)


## The host holds the internal clock and the joiner the external one, the way
## the two ends of a cable do.
func test_host_holds_the_internal_clock_joiner_the_external() -> void:
	var host: Gen2NetworkLinkTransport = _host()
	host._on_message(
		host.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	assert_eq(host.status(), Gen2LinkTransport.USING_INTERNAL_CLOCK)
	var joiner: Gen2NetworkLinkTransport = Gen2NetworkLinkTransport.join(
		ROOM, _local_peer()
	)
	joiner._on_message(
		joiner.topic(), _msg("hello", 1, "host", {"peer": _peer_block()})
	)
	assert_eq(joiner.status(), Gen2LinkTransport.USING_EXTERNAL_CLOCK)


## Ordering: a duplicate sequence and an older one are ignored, and the
## newer one is the peer that stands.
func test_a_duplicate_or_older_sequence_is_ignored() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 5, "join", {"peer": _peer_block()})
	)
	assert_eq(String(transport.peer.get("name", "")), "BLUE")
	var stale: Dictionary = _peer_block()
	stale["name"] = "STALE"
	transport._on_message(
		transport.topic(), _msg("hello", 5, "join", {"peer": stale})
	)
	transport._on_message(
		transport.topic(), _msg("hello", 3, "join", {"peer": stale})
	)
	assert_eq(String(transport.peer.get("name", "")), "BLUE")


## A message from this side's own role is its own echo off the broker, not
## the peer.
func test_a_message_from_the_same_role_is_ignored() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "host", {"peer": _peer_block()})
	)
	assert_false(transport.connected())


## The nybble the peer sent is the one `exchange_nybble` answers with.
func test_exchange_nybble_returns_the_peers_last_nybble() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	transport._on_message(
		transport.topic(), _msg("nybble", 2, "join", {"value": 7})
	)
	assert_eq(transport.exchange_nybble(4), 7)


## `exchange` answers with the peer's cached block, the way the local
## transport answers from its save slot.
func test_exchange_returns_the_peers_cached_block() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	var block: Dictionary = transport.exchange(
		{"room": Gen2LinkSession.CABLECLUBROOM_TRADECENTER}
	)
	assert_eq(String(block.get("name", "")), "BLUE")
	assert_eq(
		(block.get("party", []) as Array).size(), 1
	)


## A room message is the room `peer_room` answers with.
func test_a_room_message_sets_the_peers_room() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	var block: Dictionary = _peer_block()
	block["room"] = Gen2LinkSession.CABLECLUBROOM_COLOSSEUM
	transport._on_message(
		transport.topic(), _msg("room", 2, "join", {"peer": block})
	)
	assert_eq(
		transport.peer_room(Gen2LinkSession.CABLECLUBROOM_TRADECENTER),
		Gen2LinkSession.CABLECLUBROOM_COLOSSEUM
	)


## A trade-slot message is the row `choose_trade_slot` answers with.
func test_a_trade_slot_message_sets_the_peers_offered_row() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	transport._on_message(
		transport.topic(), _msg("trade_slot", 2, "join", {"slot": 0})
	)
	assert_eq(
		transport.choose_trade_slot({"ot_cursor": 0, "ot_count": 1}), 0
	)


## A bye clears the peer: the same drop a pulled cable gives.
func test_a_bye_clears_the_peer() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	assert_true(transport.connected())
	transport._on_message(
		transport.topic(), _msg("bye", 2, "join", {})
	)
	assert_false(transport.connected())
	assert_eq(
		transport.status(), Gen2LinkTransport.CONNECTION_NOT_ESTABLISHED
	)


## A peer unheard from for the timeout is gone, even though its last block is
## still cached.
func test_a_peer_unheard_from_for_the_timeout_is_gone() -> void:
	var transport: Gen2NetworkLinkTransport = _host()
	transport._on_message(
		transport.topic(), _msg("hello", 1, "join", {"peer": _peer_block()})
	)
	assert_true(transport.connected())
	transport._last_peer_ms = Time.get_ticks_msec() \
		- Gen2NetworkLinkTransport.PEER_TIMEOUT_MS - 1000
	assert_false(transport.connected())
	assert_eq(
		transport.status(), Gen2LinkTransport.CONNECTION_NOT_ESTABLISHED
	)
