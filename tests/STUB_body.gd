extends CharacterBody3D

# A body for tests: the handful of things SCRIPT_vitals.gd reads off the explorer.
var arrived := true
var flying := false
var running := false
var run_allowed := true
var deep := 0.0
var grounded := true
var arrivals := 0


func arrive() -> void:
	arrivals += 1
