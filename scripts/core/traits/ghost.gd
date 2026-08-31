extends TraitEffect

## Ghost Fleet — the drowned do not stay down.
##
## A revive with no `until` never expires, so it is a once-per-fight second life
## rather than a window. Davy Grim's ability grants the windowed kind; the sim
## tells them apart by whether the dictionary carries an expiry.

func id() -> StringName:
	return &"ghost"


func apply(_sim: Sim, context: Dictionary) -> void:
	var pct := v(context, &"hp") / 100.0
	for u in context["holders"]:
		u.revive = { "pct": pct, "used": false }

	# At the top breakpoint the whole fleet rises, not just the ghosts — but only
	# if they have nothing better already.
	if context["count"] >= 6:
		for u in context["team"]:
			if u.revive.is_empty():
				u.revive = { "pct": 0.30, "used": false }
