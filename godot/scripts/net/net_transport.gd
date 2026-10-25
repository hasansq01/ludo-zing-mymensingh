class_name NetTransport
extends RefCounted
## The socket under NetClient / NetQuick: text frames in and out, polled once a frame. The app uses
## NetTransport.make() = NetTransport.Raw (a small RFC 6455 client over StreamPeerTCP / StreamPeerTLS); tests and
## dev scenes plug in NetFake.Pipe (an in-process server) instead. NetTransport.WS (WebSocketPeer) is kept for
## comparison: Godot's WebSocketPeer drops the frames that arrive in the same read as the server's close frame
## (its buffers are cleared on close), which over TLS loses the matchmaker's `matched` (sent right before its
## close 1000 "matched") and any `error` sent right before a close (banned, kicked, not_found, full). Raw delivers
## every frame received before the close.
## state() uses WebSocketPeer's ready states (STATE_CONNECTING, STATE_OPEN, STATE_CLOSING, STATE_CLOSED).

## The transport the app uses.
static func make() -> NetTransport:
	return Raw.new()

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


## A minimal WebSocket client (RFC 6455, client side) over StreamPeerTCP, with StreamPeerTLS for wss://: text
## frames, ping -> pong, close; frames are unmasked from the server, masked to it. The hostname resolves without
## blocking (IP.resolve_hostname_queue_item); the TLS certificate is checked against the host name.
class Raw extends NetTransport:
	const GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	const MAX_FRAME := 1 << 20
	var close_code := -1
	var close_reason := ""
	var _host := ""
	var _port := 80
	var _path := "/"
	var _secure := false
	var _phase := "closed"                ## dns | tcp | tls | upgrade | open | closed
	var _resolve := -1
	var _addrs: Array = []                ## resolved addresses still to try (IPv4 first)
	var _tcp: StreamPeerTCP
	var _tls: StreamPeerTLS
	var _peer: StreamPeer
	var _key := ""
	var _buf := PackedByteArray()
	var _in: Array = []
	var _frag := PackedByteArray()
	var _close_sent := false

	func open(url: String) -> int:
		_reset()
		var u := url.strip_edges()
		if u.begins_with("wss://"):
			_secure = true
			u = u.substr(6)
		elif u.begins_with("ws://"):
			_secure = false
			u = u.substr(5)
		else:
			return ERR_INVALID_PARAMETER
		var slash := u.find("/")
		var hostport := u if slash < 0 else u.substr(0, slash)
		_path = "/" if slash < 0 else u.substr(slash)
		var colon := hostport.rfind(":")
		if colon > 0 and not hostport.ends_with("]"):
			_host = hostport.substr(0, colon)
			_port = int(hostport.substr(colon + 1))
		else:
			_host = hostport
			_port = 443 if _secure else 80
		if _host == "":
			return ERR_INVALID_PARAMETER
		if _host.is_valid_ip_address():
			return _connect(_host)
		_resolve = IP.resolve_hostname_queue_item(_host, IP.TYPE_ANY)
		if _resolve < 0:
			return FAILED
		_phase = "dns"
		return OK

	func _next_addr() -> void:
		while not _addrs.is_empty():
			if _connect(str(_addrs.pop_front())) == OK:
				return
		_drop()

	func _connect(ip: String) -> int:
		_tcp = StreamPeerTCP.new()
		var err := _tcp.connect_to_host(ip, _port)
		if err != OK:
			_phase = "closed"
			return err
		_tcp.set_no_delay(true)
		_peer = _tcp
		_phase = "tcp"
		return OK

	func poll() -> void:
		match _phase:
			"dns":
				var st := IP.get_resolve_item_status(_resolve)
				if st == IP.RESOLVER_STATUS_DONE:
					var all: Array = Array(IP.get_resolve_item_addresses(_resolve))
					IP.erase_resolve_item(_resolve)
					_resolve = -1
					_addrs = all.filter(func(a): return not str(a).contains(":")) + all.filter(func(a): return str(a).contains(":"))
					_next_addr()
				elif st == IP.RESOLVER_STATUS_ERROR or st == IP.RESOLVER_STATUS_NONE:
					_drop()
			"tcp":
				_tcp.poll()
				match _tcp.get_status():
					StreamPeerTCP.STATUS_CONNECTED:
						if _secure:
							_tls = StreamPeerTLS.new()
							if _tls.connect_to_stream(_tcp, _host, TLSOptions.client()) != OK:
								_drop()
								return
							_peer = _tls
							_phase = "tls"
						else:
							_send_upgrade()
					StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
						_next_addr()                    # (the next address, if any: IPv6 after IPv4)
			"tls":
				_tls.poll()
				match _tls.get_status():
					StreamPeerTLS.STATUS_CONNECTED:
						_send_upgrade()
					StreamPeerTLS.STATUS_HANDSHAKING:
						pass
					_:
						_drop()
			"upgrade":
				if not _read():
					return
				var text := _buf.get_string_from_ascii()
				var end := text.find("\r\n\r\n")
				if end < 0:
					if _buf.size() > 16384:
						_drop()
					return
				var head := text.substr(0, end)
				var lines := head.split("\r\n")
				var ok := lines.size() > 0 and lines[0].begins_with("HTTP/1.1 101")
				var accept := ""
				for ln in lines:
					if ln.to_lower().begins_with("sec-websocket-accept:"):
						accept = ln.substr(ln.find(":") + 1).strip_edges()
				if not ok or accept != _accept_for(_key):
					_drop()
					return
				_buf = _buf.slice(end + 4)
				_phase = "open"
				_frames()
			"open":
				if _read():
					_frames()

	## Reads what has arrived into _buf. False when the connection is gone.
	func _read() -> bool:
		if _tls:
			_tls.poll()
			if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
				_drop()
				return false
		else:
			_tcp.poll()
			if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_drop()
				return false
		while true:
			var n := _peer.get_available_bytes()
			if n <= 0:
				break
			var got: Array = _peer.get_partial_data(n)
			if int(got[0]) != OK:
				_drop()
				return false
			_buf.append_array(got[1])
			if _buf.size() > MAX_FRAME * 2:
				_drop()
				return false
		return true

	## Every complete frame in _buf: text to the inbox, ping -> pong, close -> closed (after the frames before it).
	func _frames() -> void:
		while _phase == "open":
			if _buf.size() < 2:
				return
			var b0 := _buf[0]
			var b1 := _buf[1]
			var fin := (b0 & 0x80) != 0
			var op := b0 & 0x0F
			var masked := (b1 & 0x80) != 0
			var plen := b1 & 0x7F
			var at := 2
			if plen == 126:
				if _buf.size() < 4:
					return
				plen = (_buf[2] << 8) | _buf[3]
				at = 4
			elif plen == 127:
				if _buf.size() < 10:
					return
				plen = 0
				for k in 8:
					plen = (plen << 8) | _buf[2 + k]
				at = 10
			if plen > MAX_FRAME or plen < 0:
				_drop()
				return
			var mask := PackedByteArray()
			if masked:
				if _buf.size() < at + 4:
					return
				mask = _buf.slice(at, at + 4)
				at += 4
			if _buf.size() < at + plen:
				return
			var payload := _buf.slice(at, at + plen)
			_buf = _buf.slice(at + plen)
			if masked:
				for k in payload.size():
					payload[k] = payload[k] ^ mask[k % 4]
			match op:
				0x1, 0x0:
					_frag.append_array(payload)
					if fin:
						_in.append(_frag.get_string_from_utf8())
						_frag = PackedByteArray()
				0x9:
					_send_frame(0xA, payload)
				0x8:
					close_code = (payload[0] << 8) | payload[1] if payload.size() >= 2 else 1005
					close_reason = payload.slice(2).get_string_from_utf8() if payload.size() > 2 else ""
					if not _close_sent:
						_send_frame(0x8, payload.slice(0, 2) if payload.size() >= 2 else PackedByteArray())
					_drop()
					return

	func state() -> int:
		match _phase:
			"open":
				return WebSocketPeer.STATE_OPEN
			"closed":
				return WebSocketPeer.STATE_CLOSED
		return WebSocketPeer.STATE_CONNECTING

	func send(text: String) -> int:
		if _phase != "open":
			return ERR_UNAVAILABLE
		return _send_frame(0x1, text.to_utf8_buffer())

	## The frames that arrived since the last call (also those just before a close).
	func receive() -> Array:
		var out := _in
		_in = []
		return out

	func close() -> void:
		if _phase == "open" and not _close_sent:
			var p := PackedByteArray([0x03, 0xE8])          # 1000
			p.append_array("bye".to_utf8_buffer())
			_send_frame(0x8, p)
		_drop()

	func _send_upgrade() -> void:
		var raw := PackedByteArray()
		for k in 16:
			raw.append(randi() % 256)
		_key = Marshalls.raw_to_base64(raw)
		var host_h := _host if (_port == (443 if _secure else 80)) else "%s:%d" % [_host, _port]
		var req := "GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nUser-Agent: LudoZing\r\n\r\n" % [_path, host_h, _key]
		if _peer.put_data(req.to_utf8_buffer()) != OK:
			_drop()
			return
		_buf = PackedByteArray()
		_phase = "upgrade"

	static func _accept_for(key: String) -> String:
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA1)
		h.update((key + GUID).to_utf8_buffer())
		return Marshalls.raw_to_base64(h.finish())

	func _send_frame(op: int, payload: PackedByteArray) -> int:
		if _peer == null or _phase != "open":
			return ERR_UNAVAILABLE
		var f := PackedByteArray([0x80 | op])
		var n := payload.size()
		if n < 126:
			f.append(0x80 | n)
		elif n < 65536:
			f.append(0x80 | 126)
			f.append((n >> 8) & 0xFF)
			f.append(n & 0xFF)
		else:
			f.append(0x80 | 127)
			for k in range(7, -1, -1):
				f.append((n >> (8 * k)) & 0xFF)
		var mask := PackedByteArray([randi() % 256, randi() % 256, randi() % 256, randi() % 256])
		f.append_array(mask)
		var body := payload.duplicate()
		for k in body.size():
			body[k] = body[k] ^ mask[k % 4]
		f.append_array(body)
		if op == 0x8:
			_close_sent = true
		return _peer.put_data(f)

	func _drop() -> void:
		if _resolve >= 0:
			IP.erase_resolve_item(_resolve)
			_resolve = -1
		if _tls:
			_tls.disconnect_from_stream()
		if _tcp:
			_tcp.disconnect_from_host()
		_tls = null
		_tcp = null
		_peer = null
		_phase = "closed"

	func _reset() -> void:
		_drop()
		_addrs = []
		close_code = -1
		close_reason = ""
		_buf = PackedByteArray()
		_in = []
		_frag = PackedByteArray()
		_close_sent = false
		_key = ""
