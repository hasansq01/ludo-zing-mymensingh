class_name NetTransport
extends RefCounted
## The socket under NetClient: text frames in and out, polled once a frame. NetClient uses NetTransport.WS (a
## WebSocketPeer) in the app; tests and dev scenes plug in NetFake.Pipe (an in-process room) instead.
## state() uses WebSocketPeer's ready states (STATE_CONNECTING, STATE_OPEN, STATE_CLOSING, STATE_CLOSED).

func open(_url: String) -> int:
	return OK

func poll() -> void:
	pass

func state() -> int:
	return WebSocketPeer.STATE_CLOSED

func send(_text: String) -> int:
	return OK

## The text frames that arrived since the last call.
func receive() -> Array:
	return []

func close() -> void:
	pass


## The real socket.
class WS extends NetTransport:
	var ws := WebSocketPeer.new()

	func open(url: String) -> int:
		ws = WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 18          # a full sync (state + seats) is a few KB; room to spare
		ws.heartbeat_interval = 0.0               # NetClient pings itself (protocol "ping" every 20 s)
		return ws.connect_to_url(url)

	func poll() -> void:
		ws.poll()

	func state() -> int:
		return ws.get_ready_state()

	func send(text: String) -> int:
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return ERR_UNAVAILABLE
		return ws.send_text(text)

	func receive() -> Array:
		var out := []
		while ws.get_available_packet_count() > 0:
			out.append(ws.get_packet().get_string_from_utf8())
		return out

	func close() -> void:
		if ws.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]:
			ws.close(1000, "bye")
