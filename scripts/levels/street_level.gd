extends "res://scripts/levels/level.gd"
## Mapa "Osiedle": trzy domy do opróżnienia i ciężarówka na ulicy.
## Zlecenie (czas, licznik w ciężarówce, podsumowanie) prowadzi JobManager;
## strefą załadunku jest $Truck/LoadZone.

@export var job_time_limit: float = 900.0
@export var job_base_pay: int = 6000


func _ready() -> void:
	var job := JobManager.new()
	job.name = "Job"  # ta sama nazwa na każdym peerze (ścieżka RPC)
	job.zone = $Truck/LoadZone
	job.time_limit = job_time_limit
	job.base_pay = job_base_pay
	add_child(job)
	super()
