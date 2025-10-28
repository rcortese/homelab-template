# Testes do template

Este diretório contém os testes que acompanham o template e devem permanecer
intactos para facilitar atualizações futuras. Para adicionar testes específicos
em projetos derivados, crie-os fora deste diretório e orquestre a execução por
meio do workflow sobrescrito `.github/workflows/project-tests.yml`. Consulte
`docs/ci-overrides.md` para o passo a passo completo.

## Organização dos testes

Os casos que exercitam os comandos distribuídos em `scripts/` ficam centralizados
em `tests/scripts/`. Cada subdiretório leva o nome do comando correspondente
(por exemplo, `tests/scripts/check_all/` cobre o wrapper `scripts/check_all.sh`)
e deve conter um `__init__.py` para permitir imports relativos entre os módulos
de teste. Ao adicionar verificações para um novo comando, crie um diretório
homônimo em `tests/scripts/`, mova/adicione os arquivos `test_*.py` dentro dele e
consuma utilitários compartilhados via `tests/helpers/`.

## Como rodar

Para validar rapidamente a suíte do template localmente, utilize `pytest -q` na
raiz do repositório. Como alternativa mais abrangente, execute o script
`scripts/run_quality_checks.sh`, que reproduz a sequência de verificações
invocada pelo workflow `project-tests.yml` no GitHub Actions.
