extends Node

# Autoload `CorePin`: keeps the fastest core for the main thread, then settles how
# many threads the machine gets (4, 8 or 16, counting the main thread), once, at
# boot. FIRST in the autoload list, so it runs before any autoload starts a thread
# of its own. The why is in `SCRIPT_core_affinity.gd` and `SCRIPT_thread_tier.gd`.


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	CoreAffinity.pin_main()
	ThreadTier.configure()
