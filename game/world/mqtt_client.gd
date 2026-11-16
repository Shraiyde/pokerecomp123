class_name Gen2MqttClient
extends RefCounted

## A minimal MQTT 3.1.1 client over a WebSocket, enough for the link-cable
## relay: CONNECT, PUBLISH (QoS 0/1), SUBSCRIBE, PINGREQ and DISCONNECT. The
## broker is the public EMQX one the phone-to-phone co-op already uses, so a
## room is a topic and the broker is the relay — no port forwarding, no direct
## connection, and the two phones only need the same four digits.
##
## The client is polled, not a node: the network link transport owns it and the
## world screen pumps the transport once a drawn frame, so a dropped socket is
## noticed on the next frame rather than on the next link call. Reconnection is
## the client's own job: it re-opens the socket, re-sends CONNECT and
## re-subscribes to every topic it held, so a brief network blip re-joins the
## room without the player doing anything.

signal connected()
signal disconnected()
signal message_received(topic: String, payload: PackedByteArray)

## The public broker's WebSocket listener, MQTT over WebSocket on the "mqtt"
## subprotocol.
const BROKER_URL: String = "wss://broker.emqx.io:8084/mqtt"
const MQTT_SUBPROTOCOL: String = "mqtt"

## MQTT 3.1.1 packet types, high nybble of the fixed header.
const TYPE_CONNECT: int = 1
const TYPE_CONNACK: int = 2
const TYPE_PUBLISH: int = 3
const TYPE_PUBACK: int = 4
const TYPE_SUBSCRIBE: int = 8
const TYPE_SUBACK: int = 9
const TYPE_PINGREQ: int = 12
const TYPE_PINGRESP: int = 13
const TYPE_DISCONNECT: int = 14

## Keep-alive in seconds: the client pings and the broker answers, and a
## missed answer is a dead connection. Short enough to notice a drop before
## the link session's own heartbeat timeout, long enough not to chatter.
const KEEP_ALIVE_SECONDS: int = 15
## Seconds between reconnection attempts, doubling to this cap.
const RECONNECT_BASE_SECONDS: float = 1.0
const RECONNECT_MAX_SECONDS: float = 16.0

var _socket: WebSocketPeer = null
var _client_id: String = ""
var _buffer: PackedByteArray = PackedByteArray()
var _subscriptions: Array[String] = []
var _next_packet_id: int = 1
var _mqtt_connected: bool = false
var _connecting: bool = false
var _want_connect: bool = false
var _connect_sent: bool = false
var _last_activity_ms: int = 0
var _last_ping_ms: int = 0
var _ping_outstanding: bool = false
var _reconnect_at_ms: int = 0
var _reconnect_delay: float = RECONNECT_BASE_SECONDS


func is_broker_connected() -> bool:
	return _mqtt_connected


func is_connecting() -> bool:
	return _connecting or (
		_socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING
	)


## Opens the socket and starts the MQTT handshake. Safe to call again after a
## drop: it re-opens, re-sends CONNECT and re-subscribes.
func connect_to_broker(client_id: String = "") -> void:
	_client_id = client_id if not client_id.is_empty() else _new_client_id()
	_want_connect = true
	_connecting = true
	_open_socket()


func disconnect_from_broker() -> void:
	_want_connect = false
	_mqtt_connected = false
	_connecting = false
	if _socket != null:
		if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_socket.put_packet(_packet_disconnect())
		_socket.close()
		_socket = null
	disconnected.emit()


func subscribe(topic: String) -> void:
	if topic.is_empty() or _subscriptions.has(topic):
		return
	_subscriptions.append(topic)
	if _mqtt_connected:
		_send_subscribe(topic)


func publish(topic: String, payload: PackedByteArray, qos: int = 1) -> bool:
	if not _mqtt_connected or topic.is_empty():
		return false
	var packet_id: int = 0
	if qos > 0:
		packet_id = _next_packet_id
		_next_packet_id = (_next_packet_id % 0xFFFF) + 1
	_socket.put_packet(_packet_publish(topic, payload, qos, packet_id))
	_last_activity_ms = Time.get_ticks_msec()
	return true


## Pumps the socket, parses complete MQTT packets out of the byte buffer,
## answers pings and reconnects after a drop. Call once a frame.
func poll() -> void:
	if _socket == null:
		if _want_connect and Time.get_ticks_msec() >= _reconnect_at_ms:
			_open_socket()
		return
	_socket.poll()
	var state: int = _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_on_socket_closed()
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	## The MQTT handshake opens on the WebSocket: CONNECT goes out once the
	## socket is open, CONNACK comes back and flips `_mqtt_connected`.
	if not _connect_sent:
		_socket.put_packet(_packet_connect())
		_connect_sent = true
		_last_activity_ms = Time.get_ticks_msec()
	while _socket.get_available_packet_count() > 0:
		var chunk: PackedByteArray = _socket.get_packet()
		_buffer.append_array(chunk)
		_last_activity_ms = Time.get_ticks_msec()
	_parse_buffer()
	if not _mqtt_connected:
		return
	var now: int = Time.get_ticks_msec()
	if not _ping_outstanding and now - _last_activity_ms >= KEEP_ALIVE_SECONDS * 500:
		_socket.put_packet(_packet_pingreq())
		_ping_outstanding = true
		_last_ping_ms = now
	elif _ping_outstanding and now - _last_ping_ms >= KEEP_ALIVE_SECONDS * 1000:
		_on_socket_closed()


func _open_socket() -> void:
	_socket = WebSocketPeer.new()
	_socket.supported_protocols = PackedStringArray([MQTT_SUBPROTOCOL])
	var err: Error = _socket.connect_to_url(BROKER_URL)
	if err != OK:
		_socket = null
		_schedule_reconnect()
		return
	_connecting = true
	_connect_sent = false
	_buffer = PackedByteArray()


func _on_socket_closed() -> void:
	var was_connected: bool = _mqtt_connected
	_mqtt_connected = false
	_connecting = false
	_connect_sent = false
	_ping_outstanding = false
	_buffer = PackedByteArray()
	if _socket != null:
		_socket.close()
		_socket = null
	if was_connected:
		disconnected.emit()
	if _want_connect:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	_reconnect_at_ms = Time.get_ticks_msec() + int(_reconnect_delay * 1000.0)
	_reconnect_delay = minf(_reconnect_delay * 2.0, RECONNECT_MAX_SECONDS)


func _new_client_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "pokerecomp-%d" % rng.randi_range(100000, 999999)


## Parses complete MQTT packets out of `_buffer`, leaving a partial packet for
## the next poll. A WebSocket message can hold several packets, or half of one.
func _parse_buffer() -> void:
	while _buffer.size() >= 2:
		var header: int = _buffer[0]
		var packet_type: int = (header >> 4) & 0x0F
		var length: int = 0
		var multiplier: int = 1
		var index: int = 1
		var length_done: bool = false
		while index < _buffer.size() and index <= 4:
			var encoded: int = _buffer[index]
			length += (encoded & 0x7F) * multiplier
			multiplier *= 128
			index += 1
			if (encoded & 0x80) == 0:
				length_done = true
				break
		if not length_done:
			return
		if _buffer.size() < index + length:
			return
		var body: PackedByteArray = _buffer.slice(index, index + length)
		_buffer = _buffer.slice(index + length)
		_handle_packet(packet_type, header, body)


func _handle_packet(packet_type: int, header: int, body: PackedByteArray) -> void:
	match packet_type:
		TYPE_CONNACK:
			if body.size() >= 2 and body[1] == 0:
				_mqtt_connected = true
				_connecting = false
				_reconnect_delay = RECONNECT_BASE_SECONDS
				_last_activity_ms = Time.get_ticks_msec()
				for topic: String in _subscriptions:
					_send_subscribe(topic)
				connected.emit()
			else:
				_on_socket_closed()
		TYPE_PUBLISH:
			var qos: int = (header >> 1) & 0x03
			var topic: String = _read_string(body, 0)
			var topic_len: int = 2 + topic.to_utf8_buffer().size()
			var payload_start: int = topic_len
			if qos > 0:
				var packet_id: int = (int(body[topic_len]) << 8) | int(body[topic_len + 1])
				payload_start = topic_len + 2
				_socket.put_packet(_packet_puback(packet_id))
			var payload: PackedByteArray = body.slice(payload_start)
			_last_activity_ms = Time.get_ticks_msec()
			message_received.emit(topic, payload)
		TYPE_PUBACK:
			pass
		TYPE_SUBACK:
			pass
		TYPE_PINGRESP:
			_ping_outstanding = false
			_last_activity_ms = Time.get_ticks_msec()
		_:
			pass


func _send_subscribe(topic: String) -> void:
	var packet_id: int = _next_packet_id
	_next_packet_id = (_next_packet_id % 0xFFFF) + 1
	var body := PackedByteArray()
	body.append((packet_id >> 8) & 0xFF)
	body.append(packet_id & 0xFF)
	_append_string(body, topic)
	body.append(1)
	_socket.put_packet(_packet_with_header(0x82, body))


func _packet_publish(
	topic: String, payload: PackedByteArray, qos: int, packet_id: int
) -> PackedByteArray:
	var body := PackedByteArray()
	_append_string(body, topic)
	if qos > 0:
		body.append((packet_id >> 8) & 0xFF)
		body.append(packet_id & 0xFF)
	body.append_array(payload)
	var flags: int = (qos & 0x03) << 1
	return _packet_with_header((TYPE_PUBLISH << 4) | flags, body)


func _packet_puback(packet_id: int) -> PackedByteArray:
	var body := PackedByteArray()
	body.append((packet_id >> 8) & 0xFF)
	body.append(packet_id & 0xFF)
	return _packet_with_header(TYPE_PUBACK << 4, body)


func _packet_pingreq() -> PackedByteArray:
	return _packet_with_header(TYPE_PINGREQ << 4, PackedByteArray())


func _packet_disconnect() -> PackedByteArray:
	return _packet_with_header(TYPE_DISCONNECT << 4, PackedByteArray())


func _packet_connect() -> PackedByteArray:
	var body := PackedByteArray()
	_append_string(body, "MQTT")
	body.append(4)
	body.append(0x02)
	body.append((KEEP_ALIVE_SECONDS >> 8) & 0xFF)
	body.append(KEEP_ALIVE_SECONDS & 0xFF)
	_append_string(body, _client_id)
	return _packet_with_header(TYPE_CONNECT << 4, body)


func _packet_with_header(first: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.append(first)
	_append_remaining_length(out, body.size())
	out.append_array(body)
	return out


func _append_remaining_length(out: PackedByteArray, length: int) -> void:
	var remaining: int = length
	while true:
		var encoded: int = remaining % 128
		remaining /= 128
		if remaining > 0:
			encoded |= 0x80
		out.append(encoded)
		if remaining <= 0:
			break


func _append_string(out: PackedByteArray, text: String) -> void:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	out.append((bytes.size() >> 8) & 0xFF)
	out.append(bytes.size() & 0xFF)
	out.append_array(bytes)


func _read_string(body: PackedByteArray, offset: int) -> String:
	if body.size() < offset + 2:
		return ""
	var length: int = (int(body[offset]) << 8) | int(body[offset + 1])
	if body.size() < offset + 2 + length:
		return ""
	return body.slice(offset + 2, offset + 2 + length).get_string_from_utf8()
