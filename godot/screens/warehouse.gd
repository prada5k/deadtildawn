extends Control
## HOME content. The persistent shell supplies cash, followers, location chrome,
## and navigation while this screen owns the garage view and Civic identity.

signal go(target: String)

@onready var home_garage: Node3D = %HomeGarage


func _ready() -> void:
	%LocalStraightButton.pressed.connect(func(): go.emit("local_straight"))
	%LocalCurvesButton.pressed.connect(func(): go.emit("local_curves"))


## Called by game.gd after the screen is added.
func setup(info: Dictionary) -> void:
	var civic: Dictionary = info.get("civic", {})
	home_garage.apply_civic_state(civic)
	var chassis_id := str(civic.get("chassis_id", "UNKNOWN CHASSIS"))
	var base_car_id := str(civic.get("base_car_id", ""))
	%CivicName.text = base_car_name(base_car_id)
	%CivicIdentity.text = "%s / E-EG6" % chassis_id
	var installed: Dictionary = civic.get("installed", {})
	%InstalledState.text = "%d AFTERMARKET %s INSTALLED" % [
		installed.size(), "COMPONENT" if installed.size() == 1 else "COMPONENTS"]
	var spares := int(info.get("owned_spares", 0))
	%SpareState.text = "%d OWNED SPARE %s" % [spares, "PART" if spares == 1 else "PARTS"]
	%Today.text = str(info.get("today", ""))
	%NextCalendar.text = "NEXT CALENDAR / %s" % str(info.get("next_calendar", ""))
	%TapeDate.text = str(info.get("tape_date", ""))
	%CashOnHand.text = home_money(int(info.get("cash", 0)))
	%Followers.text = str(int(info.get("followers", 0)))


func base_car_name(base_car_id: String) -> String:
	if base_car_id == "eg6_sir_ii_1995":
		return "1995 CIVIC SiR-II"
	return base_car_id.to_upper()


func home_money(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + "$" + digits + grouped


## Used by the headless game regression to verify the presentation receives a
## copy of the authoritative saved state whenever HOME is entered.
func current_civic_state() -> Dictionary:
	return home_garage.current_civic_state()


func current_vehicle_visual_state() -> Dictionary:
	return home_garage.current_vehicle_visual_state()
