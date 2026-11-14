class_name PasswordProvider
extends AuthProvider
## Login por usuário e senha; credenciais: {"username", "password"}.

var store: AccountStore


func _init(p_store: AccountStore = null) -> void:
	store = p_store


func verify(credentials: Dictionary, ip: String) -> Dictionary:
	return store.login(str(credentials.get("username", "")), str(credentials.get("password", "")), ip)
