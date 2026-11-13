class_name SteamProvider
extends AuthProvider
## Reservado para a fase da Steam.


func verify(_credentials: Dictionary, _ip: String) -> Dictionary:
	return {"ok": false, "err": "não suportado"}
