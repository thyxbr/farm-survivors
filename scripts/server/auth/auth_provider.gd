class_name AuthProvider
extends RefCounted
## Base dos provedores de login (senha agora, Steam depois).


## Mesmo formato de AccountStore.login: {"ok":true,"id","name","token","expires","is_admin"} ou {"ok":false,"err"}.
func verify(_credentials: Dictionary, _ip: String) -> Dictionary:
	return {"ok": false, "err": "não suportado"}
