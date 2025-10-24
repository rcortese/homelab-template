# Apontamentos locais da stack

> Este diretório é reservado para documentar adaptações específicas de repositórios derivados.
>
> Alterar estes arquivos não deve causar conflitos significativos ao sincronizar com o template, desde que os mantenedores do
> template evitem modificá-los após a criação inicial.

Use este espaço para centralizar informações que fogem ao escopo genérico do template:

- Descrições da stack, contexto de negócio e objetivos do serviço.
- Runbooks particulares (incident response, deploys alternativos, integrações exclusivas).
- Dependências opcionais ou ferramentas adicionais presentes apenas no repositório derivado.
- Registro rápido de customizações aplicadas (com links para ADRs, issues ou PRs relevantes).

## Sugestões de organização

1. Crie subpastas para separar ambientes (`producao/`, `homolog/`) ou domínios funcionais.
2. Use um arquivo `CHANGELOG.md` local para listar sincronizações com o template e ajustes relevantes.
3. Aponte para estes documentos a partir do `README.md` específico do projeto derivado, evitando duplicar conteúdo.

## Convenções de merge

- O arquivo `.gitattributes` do template configura `merge=ours` para manter suas alterações em `docs/local/` durante updates.
- Ainda assim, revise diffs após rodar `scripts/update_from_template.sh` para garantir que nenhum apontamento essencial foi perdido.

Sinta-se livre para reorganizar este diretório conforme necessário — apenas mantenha um índice claro neste `README.md` ou no
arquivo equivalente que você escolher.
