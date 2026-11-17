class_name ThreadTier
extends RefCounted

# HOW MANY THREADS THIS MACHINE GETS: 4, 8 OR 16, COUNTING THE MAIN THREAD.
#
# The main thread runs the frame, on the fastest core (`CoreAffinity`). The rest
# are workers: the engine's pool, which streams the terrain and plant chunks, and
# the build lanes behind the loading screen. So a tier of 4 is the main thread
# and 3 workers, 8 is the main thread and 7, and 16 is the main thread and 15.
#
# THE TIER IS MEASURED, NOT ASSUMED FROM THE CORE COUNT. The core count says what
# the machine has. It does not say whether more threads make the game's work go
# faster. That work is GDScript, and on some machines it stops scaling well before
# the cores run out: a dual-socket Xeon peaked at three or four builds
# (`island_world._pregen_begin`). So, the first time the game starts on a machine:
#   1. it runs a GDScript workload shaped like the mesher's (float sums, array
#      writes, dictionary reads) on 3 worker threads for `PROBE_MS`, and counts
#      the work done. Tier 4 is the floor and is always taken;
#   2. if the machine has 8 hardware threads, it runs the same on 7. Tier 8 is
#      taken only if that does at least `MIN_GAIN` more work than tier 4 did;
#   3. then 16 against 8, the same way. It stops at the first tier that does not
#      pay.
# The workers run on the workers' cores, off the main thread's core, as they will
# in the game. The main thread waits while they run.
#
# THE ANSWER IS KEPT, in `user://thread_tier.cfg`, against a signature of the
# machine: the cores this process may use, their scores and the engine's version.
# Later launches read it back and run no probe. If the signature changes (another
# machine, a phone that has put the app on fewer cores, a new engine), it probes
# again. `--recalibrate-threads` probes regardless.
#
# THE ENGINE'S POOL TAKES THE TIER FROM THE NEXT LAUNCH. Its size is read once,
# before any script runs, from `threading/worker_pool/max_threads`. So the tier
# is also written to `user://thread_tier_override.cfg`, which project.godot names
# as its settings override (`application/config/project_settings_override`).
# On the first launch the pool runs at project.godot's own 7; the build lanes,
# which this game starts itself, take the tier at once (`workers()`).
#
# AND THE WORKERS GO ON THE FASTEST CORES LEFT. When the tier has fewer workers
# than there are cores besides the main thread's, `CoreAffinity.narrow_workers`
# keeps the pool's threads and the build lanes to that many of the fastest: on a
# phone's 1 + 3 + 4, tier 4 puts the three workers on the three big cores, not
# the little ones. No other thread is touched.
#
# STREAMING WHILE PLAYING TAKES ONLY PART OF THE POOL. The pool's size is the
# tier's; the share low-priority tasks may hold at once (the terrain, plant and
# grass tiles the world streams in while playing) is project.godot's
# `low_priority_thread_ratio`, 0.3: two of seven. The loading screen's lanes are
# threads of their own and use the whole tier.

## The tiers, in threads counting the main thread.
const TIERS: Array[int] = [4, 8, 16]
## Milliseconds of work at each tier.
const PROBE_MS := 150
## How much more work a tier must do than the last to be taken: 15%.
const MIN_GAIN := 1.15
## Bump when the probe itself changes, so every kept answer is measured again.
## 2: the probe saw the cores the process was given, not the one it had pinned
## its main thread to, so a phone could not reach tier 8 before.
const VERSION := 2
const SAVE := "user://thread_tier.cfg"
const OVERRIDE := "user://thread_tier_override.cfg"

## The tier in use: threads, counting the main thread.
static var total := 8
## Work done at each tier probed, tier -> units, for the log and the test. Empty
## when the answer was read back from `SAVE`.
static var measured := {}
## Where the tier came from: "probe", "saved", or "default" if neither ran.
static var source := "default"


## Worker threads for the build and the streaming: the tier less the main thread.
static func workers() -> int:
	return maxi(total - 1, 1)


## Settle the tier, by reading it back or by probing, then write it out for the
## pool and narrow the workers' cores to it. ON THE MAIN THREAD, after
## `CoreAffinity.pin_main`, so the probe's threads run where the workers will.
static func configure() -> void:
	var sig := signature()
	var force := OS.get_cmdline_user_args().has("--recalibrate-threads") \
			or OS.get_cmdline_args().has("--recalibrate-threads")
	var cfg := ConfigFile.new()
	if not force and cfg.load(SAVE) == OK and cfg.get_value("tier", "signature", "") == sig:
		total = int(cfg.get_value("tier", "total", 4))
		source = "saved"
	else:
		total = probe()
		source = "probe"
		cfg.set_value("tier", "signature", sig)
		cfg.set_value("tier", "total", total)
		for t in measured:
			cfg.set_value("measured", str(t), measured[t])
		cfg.save(SAVE)
	_write_override()
	CoreAffinity.narrow_workers(workers())
	var pool := int(ProjectSettings.get_setting("threading/worker_pool/max_threads", -1))
	print("[thread_tier] %d threads: the main thread and %d workers (%s%s); the pool has %d%s"
			% [total, workers(), source,
				"" if measured.is_empty() else ", work %s" % str(measured),
				pool, "" if pool == workers() else ", %d from the next launch" % workers()])


## Run the probe and return the tier it settles on. See the header.
static func probe() -> int:
	measured = {}
	var hw := maxi(CoreAffinity.allowed_cpus().size(), 1)
	var chosen := TIERS[0]
	var last := 0.0
	for t in TIERS:
		if t != TIERS[0] and t > hw:
			break   # not enough hardware threads to run the tier at all
		var work := float(run_load(t - 1, PROBE_MS))
		measured[t] = int(work)
		if t != TIERS[0] and work < last * MIN_GAIN:
			break
		chosen = t
		last = work
	return chosen


## Run the load on `n` threads at once for `ms` milliseconds and return the work
## they did between them. Blocks the calling thread for about that long.
static func run_load(n: int, ms: int) -> int:
	var probe := _Load.new()
	var threads: Array[Thread] = []
	for i in n:
		var t := Thread.new()
		t.start(probe.body.bind(ms))
		threads.append(t)
	# Start them together, once each has moved itself off the main core: that
	# move is a `taskset` call, and timing it would measure process start-up.
	while probe.ready_count() < n:
		OS.delay_usec(200)
	probe.go = true
	var total_work := 0
	for t in threads:
		total_work += int(t.wait_to_finish())
	return total_work


## What a kept answer has to match: the cores this process may use, how fast each
## is, and the engine and probe versions.
static func signature() -> String:
	var parts := PackedStringArray([str(VERSION), Engine.get_version_info()["string"]])
	for cpu in CoreAffinity.allowed_cpus():
		parts.append("%d:%d" % [cpu, int(CoreAffinity.score(cpu))])
	return ",".join(parts).md5_text()


static func _write_override() -> void:
	var f := FileAccess.open(OVERRIDE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("; Written by SCRIPT_thread_tier.gd at every launch. Delete it to\n"
			+ "; fall back to project.godot's pool size.\n"
			+ "[threading]\n\nworker_pool/max_threads=%d\n" % workers())
	f.close()


# One probe run: the threads' start line and their shared counter.
class _Load:
	var go := false
	var _ready := 0
	var _mutex := Mutex.new()

	func ready_count() -> int:
		_mutex.lock()
		var n := _ready
		_mutex.unlock()
		return n

	# Work like the mesher's, in units of one small grid, until the clock runs out.
	func body(ms: int) -> int:
		CoreAffinity.pin_worker_self()
		_mutex.lock()
		_ready += 1
		_mutex.unlock()
		while not go:
			OS.delay_usec(50)
		var grid := PackedFloat32Array()
		grid.resize(256)
		var lookup := {}
		for i in 64:
			lookup[i] = float(i) * 0.37
		var units := 0
		var deadline := Time.get_ticks_usec() + ms * 1000
		while Time.get_ticks_usec() < deadline:
			var acc := 0.0
			for i in 256:
				var x := float(i) * 0.013 + float(units)
				var h: float = sin(x) * 3.0 + cos(x * 1.7) + float(lookup[i & 63])
				grid[i] = h
				acc += h * 0.5
			if acc > 1e30:
				grid[0] = acc   # never true; keeps the sum from being dead code
			units += 1
		return units
