# Skills de produção adaptadas do Claude Code Game Studios

As skills `balance-check`, `smoke-check`, `perf-profile`, `patch-notes` e
`reverse-document` vieram de `Donchitos/Claude-Code-Game-Studios` (MIT, ver
`LICENSE-game-studios-skills`) e foram reescritas para este projeto.

O que mudou em relação ao original:

- Sem `project.yaml`, hooks, `.claude/scripts/` nem as pastas `design/` e
  `production/` do template: cada skill aponta direto para os arquivos, comandos e
  convenções deste repositório (Godot 4.7.2, testes `--smoketest`/`--colonytest`/
  `--nettest`, tags `vX.Y.Z`, CI em `.github/workflows/deploy.yml`).
- Texto e saídas em português.
- Mantida a regra central do original: **sem dado, sem veredito**. Seção sem dado
  ou sem meta é `NÃO AVALIADO`, nunca um "tudo certo" presumido.
- Relatórios ficam no chat; só vão para `docs/` se o usuário pedir.

`balance-check/dump_data.tscn` é uma cena auxiliar que imprime as tabelas de
balanceamento em JSON (roda como cena para que os autoloads existam).
