extends Node
## Runs tools/game_bridge.py (the Python sim) in a background thread so the
## game never freezes, then emits `replied` with the JSON reply.
##
## Python is found at <repo>/.venv (Windows or Linux layout), else on PATH.

signal replied(tag: String, data: Dictionary)

var python := ""
var bridge := ""
var busy := false
var _thread: Thread


func _ready() -> void:
	var godot_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repo := godot_dir.get_base_dir()
	bridge = repo.path_join("tools").path_join("game_bridge.py")
	for candidate in [repo.path_join(".venv/Scripts/python.exe"), repo.path_join(".venv/bin/python")]:
		if FileAccess.file_exists(candidate):
			python = candidate
			return
	for candidate in ["python", "python3"]:
		if OS.execute(candidate, ["--version"]) == 0:
			python = candidate
			return


func ready_to_use() -> String:
	## "" if the bridge can run, otherwise what's wrong.
	if python == "":
		return "Python not found. Create the .venv in the repo (see CLAUDE.md)."
	if not FileAccess.file_exists(bridge):
		return "Bridge not found at %s" % bridge
	return ""


func request(tag: String, args: Array) -> void:
	if busy:
		push_error("Bridge busy; ignoring request '%s'" % tag)
		return
	busy = true
	_thread = Thread.new()
	_thread.start(_run.bind(tag, args))


func _run(tag: String, args: Array) -> void:
	var output := []
	var code := OS.execute(python, [bridge] + args, output, false)
	var text := "" if output.is_empty() else str(output[0]).strip_edges()
	var data = JSON.parse_string(text.get_slice("\n", text.get_slice_count("\n") - 1))
	if typeof(data) != TYPE_DICTIONARY:
		data = {"ok": false, "error": "Bridge failed (exit code %d). Output:\n%s" % [code, text]}
	call_deferred("_finish", tag, data)


func _finish(tag: String, data: Dictionary) -> void:
	_thread.wait_to_finish()
	busy = false
	replied.emit(tag, data)
