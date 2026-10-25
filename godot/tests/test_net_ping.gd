extends "res://tests/test_suite.gd"
## Keep-alive pings: the exact text {"t":"ping"} (the server auto-answers it), a pong without "now" still gives the
## round trip, the server clock comes from turn.now (and an older server's pong.now), silence still drops the socket.

class Stub extends NetTransport:
	var sent: Array = []
	var inbox: Array = []
	var closed := false
	func open(_url: String) -> int: return OK
	func state() -> int: return WebSocketPeer.STATE_CLOSED if closed else WebSocketPeer.STATE_OPEN
	func send(text: String) -> int:
		sent.append(text)
		return OK
	func receive() -> Array:
		var r := inbox
		inbox = []
		return r
	func close() -> void: closed = true

func run() -> void:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	var st := Stub.new()
	c.transport = st
	c._hello_sent = true
	c._welcomed = true
	c.ping()
	check("ping: the exact text, byte for byte", st.sent == ['{"t":"ping"}'], st.sent)
	check("ping: PING_TEXT constant", NetClient.PING_TEXT.to_utf8_buffer() == PackedByteArray([123, 34, 116, 34, 58, 34, 112, 105, 110, 103, 34, 125]))

	# pong without now: rtt from _ping_at, clock untouched
	c.clock_offset_ms = 123.0
	c._ping_at = Time.get_unix_time_from_system() * 1000.0 - 80.0
	c.handle({t = "pong"})
	check("pong without now: rtt measured", c.rtt_ms >= 80 and c.rtt_ms < 2000, c.rtt_ms)
	check("pong without now: clock offset kept", c.clock_offset_ms == 123.0)
	c._ping_at = Time.get_unix_time_from_system() * 1000.0 - 40.0
	c.handle({t = "pong", now = Time.get_unix_time_from_system() * 1000.0 + 5000.0})
	check("pong with now (older server): offset taken", absf(c.clock_offset_ms - 5000.0 + 20.0) < 200.0, c.clock_offset_ms)

	# turn.now sets the clock (plus half the last rtt)
	c.rtt_ms = 100
	var local := Time.get_unix_time_from_system() * 1000.0
	c.handle({t = "turn", c = 0, deadline = local + 40000.0, now = local - 7000.0})
	check("turn.now: server_now follows it (+ half rtt)", absf(c.server_now() - (local - 7000.0 + 50.0)) < 100.0, c.server_now() - local)
	var left := (local + 40000.0 - 7000.0 + 7000.0 - c.server_now()) # deadline - server_now
	check("turn.now: countdown from deadline - server_now", absf((local + 40000.0 - c.server_now()) - 47000.0 + 50.0) < 100.0, left)
	var before := c.clock_offset_ms
	c.handle({t = "turn", c = 1, deadline = local})
	check("turn without now: offset unchanged", c.clock_offset_ms == before)

	# silence: pong frames count, no frames drop
	c._silence = 40.0
	st.inbox = ['{"t":"pong"}']
	c._process(0.0)
	check("silence: an auto-response pong is a frame", c._silence < 1.0, c._silence)
	c._silence = NetClient.SILENCE_SEC - 0.5
	c._process(1.0)
	check("silence: SILENCE_SEC without a frame drops the socket", st.closed)
	c.free()
