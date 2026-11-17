class_name CoreAffinity
extends RefCounted

# THE FASTEST CORE KEPT FOR THE MAIN THREAD, AND THE BUILD WORK OFF IT.
#
# Phones and handhelds are big.LITTLE: an 8-core Snapdragon is one prime core,
# three big ones and four little ones. Intel since Alder Lake is P-cores and
# E-cores. The game's frame is one thread. Input, the scripts, the physics step
# and, under the Compatibility renderer, the GL calls all run on it. So that thread
# wants the fastest core there is, and the terrain, plant and bake workers want to
# keep off that core.
#
# At boot (`AUTOLOAD_core_affinity.gd`, first in the autoload list) this:
#   1. scores every core this process may run on and picks the best one;
#   2. moves the engine's worker pool (its threads are named `WorkerThread N`)
#      onto every core but that one (`taskset -p`, a thread at a time);
# and later the long-running build threads move themselves off it as their first
# act (`pin_worker_self`, which `BuildLanes`, the bake loader and the tier probe
# call). So nothing the game itself computes on can take the fastest core, and
# the scheduler, which puts the busiest thread of the app in front on the biggest
# core it can, finds it free for the main thread.
#
# THE MAIN THREAD ITSELF IS NOT PINNED, AND NO OTHER THREAD IS MOVED. 0000033 and
# 0000034 pinned the main thread to that one core and every other thread of the
# process off it, and island 002 lost its frame rate on a phone. A main thread
# held to one core cannot move when that core is throttled or busy with another
# process's work, and a thread it starts afterwards (the GPU driver starts its
# own, lazily, from the thread making the GL calls) inherits that one core. And
# moving EVERY other thread put the driver's threads, the audio and Android's own
# threads in with the streaming workers, on as few as three cores. The pool's
# workers and our own build threads are the only work this game puts on other
# threads, so they are the only threads this touches.
#
# HOW A CORE IS SCORED, best source first:
#   * `cpu_capacity`, which ARM's scheduler uses itself, normalised to 1024 for
#     the biggest core;
#   * `acpi_cppc/highest_perf`, Intel and AMD's own ranking, which also picks out
#     the favoured cores on a hybrid chip;
#   * `cpufreq/cpuinfo_max_freq`.
# If every core scores the same, there is no fastest core, and nothing is pinned.
#
# LINUX AND ANDROID ONLY, the two platforms the game ships on. Both take
# `sched_setaffinity` through `taskset` (util-linux on a desktop, toybox on
# Android), and a process may always set its own threads' affinity. Windows and
# macOS are left to their own schedulers: Windows 11's Thread Director already
# gives the foreground window's busy thread a P-core, and macOS has no affinity
# call at all. Whatever cannot be read or run is skipped, and the reason printed.
# The game runs the same without it. `--no-core-pin` on the command line turns it
# all off.

## Fewer cores than this, and none is set aside for the main thread: leaving the
## workers one or two cores would cost more than it saves.
const MIN_CORES := 4

## True once the fastest core has been kept for the main thread.
static var pinned := false
## The core kept for the main thread, or -1.
static var main_core := -1
## The cores the workers may use. Empty when nothing was kept.
static var worker_cores: PackedInt32Array = PackedInt32Array()
## Why nothing was kept, for the log and the tests.
static var reason := ""
static var _worker_mask := ""
## The cores the process was given, read once, before anything here moved a
## thread (see `allowed_cpus`).
static var _allowed := PackedInt32Array()


## How many worker threads a builder should run: the measured tier less the main
## thread (`ThreadTier`), so 3, 7 or 15.
static func worker_cap() -> int:
	return ThreadTier.workers()


## Keep the fastest core for the main thread: the pool's workers off it. Called
## once, ON THE MAIN THREAD, by the autoload. Returns true if it kept one.
static func pin_main() -> bool:
	if OS.get_cmdline_user_args().has("--no-core-pin") \
			or OS.get_cmdline_args().has("--no-core-pin"):
		return _skip("turned off with --no-core-pin")
	if not (OS.get_name() in ["Linux", "Android"]):
		return _skip("%s has no affinity call here; its scheduler places the thread"
				% OS.get_name())
	var allowed := allowed_cpus()
	if allowed.size() < MIN_CORES:
		return _skip("%d cores is too few to set one aside" % allowed.size())
	var best := -1
	var top := -INF
	var low := INF
	for cpu in allowed:
		var s := score(cpu)
		if s <= 0.0:
			return _skip("cpu%d's speed cannot be read" % cpu)
		low = minf(low, s)
		# Ties go to the HIGHER-numbered core: on a phone the prime core is the
		# last, and core 0 is the one the kernel hands interrupts to first.
		if s >= top:
			top = s
			best = cpu
	if top <= low:
		return _skip("every core is as fast as every other")
	if not pin_to(best, allowed):
		return false
	print("[core_affinity] cpu%d kept for the main thread (score %.0f, slowest %.0f); %d other cores for workers"
			% [best, top, low, worker_cores.size()])
	return true


## The keeping itself, once the core is chosen: the pool's workers onto
## everything in `allowed` but `best`. Public for the test, which picks a core
## itself on a machine whose cores are all alike.
static func pin_to(best: int, allowed: PackedInt32Array) -> bool:
	var rest := PackedInt32Array()
	for cpu in allowed:
		if cpu != best:
			rest.append(cpu)
	var mask := _mask(rest)
	if _move_pool(mask) < 0:
		return _skip("taskset could not move the pool's threads")
	_worker_mask = mask
	pinned = true
	main_core = best
	worker_cores = rest
	reason = ""
	return true


## Keep the workers to the `n` fastest cores besides the main thread's, when
## there are more than that. Called by `ThreadTier.configure` once the tier is
## known, on the main thread. Does nothing unless a core was kept.
static func narrow_workers(n: int) -> void:
	if not pinned or n <= 0 or n >= worker_cores.size():
		return
	var ranked := Array(worker_cores)
	# Fastest first; on a tie the higher-numbered core, as in `pin_main`.
	ranked.sort_custom(func(a, b):
			var sa := score(a)
			var sb := score(b)
			return sa > sb if sa != sb else a > b)
	var keep := PackedInt32Array(ranked.slice(0, n))
	keep.sort()
	var mask := _mask(keep)
	if _move_pool(mask) < 0:
		return
	_worker_mask = mask
	worker_cores = keep
	print("[core_affinity] workers kept to the %d fastest other cores: %s" % [n, str(keep)])


## The engine's pool threads, by kernel id: the threads of this process named
## `WorkerThread N`.
static func pool_threads() -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in DirAccess.get_directories_at("/proc/self/task"):
		var f := FileAccess.open("/proc/self/task/%s/comm" % t, FileAccess.READ)
		if f == null:
			continue
		if f.get_line().begins_with("WorkerThread"):
			out.append(t.to_int())
		f.close()
	return out


# Put every pool thread on `mask`. The number moved, or -1 if one would not go.
static func _move_pool(mask: String) -> int:
	var moved := 0
	for tid in pool_threads():
		if not _taskset(["-p", mask, str(tid)]):
			return -1
		moved += 1
	return moved


## Move the calling thread onto the workers' cores. Safe from any thread; does
## nothing unless a core was kept. A long-running worker the game starts itself
## calls this first.
static func pin_worker_self() -> void:
	if not pinned or _worker_mask == "":
		return
	var tid := thread_id()
	if tid > 0:
		_taskset(["-p", _worker_mask, str(tid)])


## The kernel's id for the calling thread, or -1. Not `OS.get_thread_caller_id`,
## which is the engine's own number and means nothing to the kernel.
static func thread_id() -> int:
	var f := FileAccess.open("/proc/thread-self/stat", FileAccess.READ)
	if f == null:
		return -1
	# get_line, not get_as_text: a /proc file reports its length as 0.
	var line := f.get_line()
	f.close()
	var sp := line.find(" ")
	return line.substr(0, sp).to_int() if sp > 0 else -1


## How fast `cpu` is, on whichever scale the machine offers (see the header), or
## 0 when none can be read. Only comparable between cores of one machine.
static func score(cpu: int) -> float:
	var base := "/sys/devices/system/cpu/cpu%d/" % cpu
	for rel in ["cpu_capacity", "acpi_cppc/highest_perf", "cpufreq/cpuinfo_max_freq"]:
		var v := _read_number(base + rel)
		if v > 0.0:
			return v
	return 0.0


# The cores this process may run on, from its own status. An Android app is
# usually in a cpuset; picking a core outside it would fail. READ ONCE and kept:
# /proc/self/status is the first thread's, and once any thread has been moved it
# would answer for that one thread, not the process. (Reading it after the main
# thread was pinned made it one core on a desktop and seven on a phone, so the
# tier probe never tried 8.)
static func allowed_cpus() -> PackedInt32Array:
	if _allowed.is_empty():
		_allowed = _read_allowed()
	return _allowed


static func _read_allowed() -> PackedInt32Array:
	var out := PackedInt32Array()
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		for i in OS.get_processor_count():
			out.append(i)
		return out
	var list := ""
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("Cpus_allowed_list:"):
			list = line.substr(line.find(":") + 1).strip_edges()
			break
	f.close()
	for part in list.split(",", false):
		var ends := part.split("-")
		var a := ends[0].to_int()
		var b := ends[1].to_int() if ends.size() > 1 else a
		for i in range(a, b + 1):
			out.append(i)
	return out


static func _read_number(path: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0.0
	var line := f.get_line().strip_edges()
	f.close()
	return float(line.to_int()) if line.is_valid_int() else 0.0


# A taskset hex mask, built a nibble at a time so a machine past 64 cores still
# gets the right one.
static func _mask(cpus: PackedInt32Array) -> String:
	var top := 0
	for c in cpus:
		top = maxi(top, c)
	var nibbles := PackedInt32Array()
	nibbles.resize(top / 4 + 1)
	nibbles.fill(0)
	for c in cpus:
		nibbles[c / 4] |= 1 << (c % 4)
	var s := ""
	for i in range(nibbles.size() - 1, -1, -1):
		s += "%x" % nibbles[i]
	return s


static func _taskset(args: Array) -> bool:
	var out := []
	var code := OS.execute("taskset", PackedStringArray(args), out, true)
	return code == 0


static func _skip(why: String) -> bool:
	reason = why
	print("[core_affinity] no core kept for the main thread: %s" % why)
	return false

