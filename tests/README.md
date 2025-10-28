# Testes do template

Este diretório contém os testes que acompanham o template e devem permanecer
intactos para facilitar atualizações futuras. Para adicionar testes específicos
em projetos derivados, crie-os fora deste diretório e orquestre a execução por
meio do workflow sobrescrito `.github/workflows/project-tests.yml`. Consulte
`docs/ci-overrides.md` para o passo a passo completo.

## Como rodar

Para validar rapidamente a suíte do template localmente, utilize `pytest -q` na
raiz do repositório. Como alternativa mais abrangente, execute o script
`scripts/run_quality_checks.sh`, que reproduz a sequência de verificações
invocada pelo workflow `project-tests.yml` no GitHub Actions.
