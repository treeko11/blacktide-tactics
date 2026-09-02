extends RefCounted
class_name DevStore

## **DEV BUILD ONLY. Deleted with the rest of `scripts/dev/`.**
##
## The playtest log, mirrored into browser storage one line at a time.
##
## On the desktop `Dev` writes a file and flushes it every line, for the reason
## written there: the part of a playtest log worth having is the last few lines
## before whatever went wrong. **On the web there was no equivalent.** The log
## lived in `Dev.lines`, a PackedStringArray in the WASM heap, and its only two
## exits were the menu's COPY LOG and DOWNLOAD LOG — Godot buttons, which need
## the main loop to be turning.
##
## The export sets `variant/thread_support=false`, so Godot runs on the browser's
## main thread: a hang inside the game's main loop is a hang of the page. No
## button, no timer, no JavaScript at all. And a crash takes the heap and the log
## with it. Either way the log was unreachable at exactly the moment it mattered,
## which is what this class fixes — every line is in storage the browser owns
## before the frame that wrote it ends.
##
## Two banks, `a` and `b`, alternating. A launch takes the bank the last one was
## not using, so the previous session survives intact next to the live one and
## can be recovered from the menu at any point during the next run. That is why
## the banks alternate rather than a new session copying the old one aside:
## copying is a boot-time cost paid on every launch, and the thing being copied
## is the log of a session that may have died mid-write.
##
## Lines go in as fixed-size chunks rather than one key per line, and never as
## one growing blob. A blob rewritten per line is O(n²) over a session, on the
## platform whose freezes this exists to diagnose; a key per line means a
## thousand keys to walk on recovery. A chunk is one small `setItem` per line,
## and the chunk being filled is rewritten whole each time, so the newest line is
## always already stored.
##
## The backend is injected so the suite can drive all of this headless. A store
## that looks perfect and records nothing is the DPS-meter problem again, and
## `test_dev.gd` asserts on what comes back out.

## Lines per chunk. Sets the size of the write that happens on every logged line:
## fifty lines is around 3 KB, small enough not to be felt.
const CHUNK_LINES := 50

## Chunks kept per bank. Twelve is six hundred lines, which is several rounds of
## play — comfortably more than anyone reads back, and around 40 KB against the
## 5 MB an origin gets.
const CHUNKS := 12

const PREFIX := "blacktide.playtest."

## Installed once, then called through a `JavaScriptObject` rather than by
## `eval`. `eval` parses its string on every call, and this one is called on
## every logged line.
##
## Every entry swallows its own exception. Storage throws in more situations than
## it is worth enumerating — a full quota, a browser set to block site data,
## Safari in private browsing — and none of them is a reason for a dev-build log
## to take the game down with it.
const _JS := """
window.__blacktide_store = window.__blacktide_store || (function () {
	function put(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
	function take(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
	function drop(k) { try { localStorage.removeItem(k); } catch (e) {} }
	function seal(k) {
		// `pagehide` fires when the tab is closed or navigated away from, and
		// does not fire when the page is killed under a hang. That asymmetry is
		// the whole signal: a session with no seal ended badly.
		window.addEventListener('pagehide', function () { put(k, '1'); });
	}
	return { put: put, take: take, drop: drop, seal: seal };
})();
"""

var _put: Callable
var _take: Callable
var _drop: Callable
var _seal: Callable

var _live := ""
var _previous := ""
var _head := 0
var _wrapped := false
var _buffer := PackedStringArray()
var _open := false


## Pass nothing for browser storage. The suite passes its own Callables and
## drives the same code against a Dictionary.
func _init(put := Callable(), take := Callable(), drop := Callable(),
		seal := Callable()) -> void:
	if put.is_valid():
		_put = put
		_take = take
		_drop = drop
		_seal = seal if seal.is_valid() else func(_k: String) -> void: pass
		return
	_install_browser_backend()


func _install_browser_backend() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(_JS, true)
	var js: JavaScriptObject = JavaScriptBridge.get_interface("__blacktide_store")
	if js == null:
		push_warning("DevStore: no browser storage, the web log is memory only")
		return
	_put = func(k: String, v: String) -> void: js.put(k, v)
	_take = func(k: String) -> Variant: return js.take(k)
	_drop = func(k: String) -> void: js.drop(k)
	_seal = func(k: String) -> void: js.seal(k)


## False when there is nowhere to write, which is every platform but the web, and
## a browser with storage switched off. Everything below is then a no-op.
func available() -> bool:
	return _put.is_valid()


# =============================================================================
#  The session
# =============================================================================

## Claims the bank the last session was not using, and clears it.
##
## The bank it releases is the previous session, readable from `recover()` for as
## long as this one lasts.
func open() -> void:
	if not available():
		return

	_previous = _string(_take.call(PREFIX + "live"))
	_live = "b" if _previous == "a" else "a"
	if _previous == "":
		_previous = "b" if _live == "a" else "a"

	for i in CHUNKS:
		_drop.call(_chunk_key(_live, i))
	_drop.call(_clean_key(_live))

	_head = 0
	_wrapped = false
	_buffer.clear()
	_open = true
	_write_meta()

	# Claimed only once the bank is cleared and its meta written. A launch
	# interrupted halfway through this leaves `live` naming the older session,
	# which is one session lost rather than two sessions interleaved.
	_put.call(PREFIX + "live", _live)

	# Arranged now rather than at shutdown, because the shutdowns worth telling
	# apart are exactly the ones where nothing of ours gets to run.
	_seal.call(_clean_key(_live))


## Adds one line. Called from `Dev.record`, so it sits on the path of every
## logged event and does exactly one small write.
func append(line: String) -> void:
	if not _open:
		return

	if _buffer.size() >= CHUNK_LINES:
		_head += 1
		if _head >= CHUNKS:
			_head = 0
			_wrapped = true
		_buffer.clear()
		# Written at the roll rather than per line: `head` is the only thing in
		# it that moves, and it moves here.
		_write_meta()

	_buffer.append(line)
	_put.call(_chunk_key(_live, _head), "\n".join(_buffer))


## What the browser does for us on a clean exit, done by hand. Only the tests
## call this; a real session is sealed by the page's own `pagehide`.
func mark_clean() -> void:
	if _open:
		_put.call(_clean_key(_live), "1")


# =============================================================================
#  Reading it back
# =============================================================================

## The previous session, or `{}` if there is not one.
##
## `text` is the log, `count` its lines, `clean` false when the session never
## reached a `pagehide` — a freeze, a crash, or a tab killed by the browser —
## and `trimmed` true when it ran past what a bank holds.
func recover() -> Dictionary:
	if not available() or _previous == "":
		return {}

	var meta_raw := _string(_take.call(_meta_key(_previous)))
	if meta_raw == "":
		return {}
	var parsed: Variant = JSON.parse_string(meta_raw)
	if not (parsed is Dictionary):
		return {}
	var meta: Dictionary = parsed

	var head := int(meta.get("head", 0))
	var wrapped := bool(meta.get("wrapped", false))

	# Oldest first. A wrapped ring starts one past the chunk that was being
	# written, which is the oldest one still standing.
	var order: Array[int] = []
	if wrapped:
		for i in CHUNKS:
			order.append((head + 1 + i) % CHUNKS)
	else:
		for i in head + 1:
			order.append(i)

	var parts := PackedStringArray()
	for i in order:
		var chunk := _string(_take.call(_chunk_key(_previous, i)))
		if chunk != "":
			parts.append(chunk)

	var text := "\n".join(parts)
	if text == "":
		return {}
	return {
		"text": text,
		"count": text.split("\n").size(),
		"started": String(meta.get("started", "")),
		"clean": _string(_take.call(_clean_key(_previous))) == "1",
		"trimmed": wrapped,
	}


# =============================================================================
#  Keys
# =============================================================================

func _write_meta() -> void:
	_put.call(_meta_key(_live), JSON.stringify({
		"head": _head,
		"wrapped": _wrapped,
		"started": Time.get_datetime_string_from_system(false, true),
	}))


func _meta_key(bank: String) -> String:
	return "%s%s.meta" % [PREFIX, bank]


func _clean_key(bank: String) -> String:
	return "%s%s.clean" % [PREFIX, bank]


func _chunk_key(bank: String, index: int) -> String:
	return "%s%s.c%d" % [PREFIX, bank, index]


## Storage answers a missing key with null, and the bridge hands that back as a
## null Variant rather than as an empty string.
func _string(value: Variant) -> String:
	return "" if value == null else str(value)
