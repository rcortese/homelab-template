# Backup & restauração genéricos

> Ajuste este documento para refletir os artefatos e ferramentas utilizados pela sua stack. Utilize-o em conjunto com os runbooks dos ambientes.

## Estratégia recomendada

1. **Catálogo de artefatos** — liste tudo que precisa ser preservado (bases de dados, exports, volumes, manifests).
2. **Frequência** — defina políticas para cada artefato (ex.: diário para dados críticos, semanal para configurações).
3. **Armazenamento** — documente onde os backups ficam (local, nuvem, storage externo) e como acessar.
4. **Testes de restauração** — planeje execuções periódicas para garantir que os artefatos funcionam.

## Processo de backup

- Identifique o comando/script responsável pela extração (ex.: `scripts/export_*.sh`, `pg_dump`, `restic`).
- Documente parâmetros obrigatórios (alvos, datas, diretórios temporários).
- Registre como versionar ou etiquetar os artefatos resultantes.
- Explique onde arquivar os relatórios de sucesso/erro.

## Processo de restauração

1. Valide a integridade do artefato (checksums, assinaturas, versões de schema).
2. Restaure em ambiente controlado utilizando os mesmos manifests/variáveis do ambiente principal.
3. Documente etapas manuais (migrações, reindexações, invalidação de caches) e responsáveis.
4. Após o sucesso, atualize o runbook correspondente com data, origem do backup e observações.

## Referências cruzadas

- `docs/core.md` e `docs/media.md` (ou equivalentes) devem apontar para os backups relevantes por ambiente.
- ADRs podem registrar decisões de retenção, criptografia ou ferramentas adotadas.
- Scripts específicos devem linkar para esta página explicando os argumentos aceitos e pré-requisitos.

Mantenha o documento atualizado conforme novos serviços forem incorporados ao projeto derivado.
