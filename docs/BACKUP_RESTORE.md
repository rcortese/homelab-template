# Backup & restauração genéricos

> Ajuste este documento para refletir os artefatos e ferramentas utilizados pela sua stack. Utilize-o em conjunto com os runbooks dos ambientes.

## Estratégia recomendada

1. **Catálogo de artefatos** — liste tudo que precisa ser preservado (bases de dados, exports, volumes, manifests).
2. **Frequência** — defina políticas para cada artefato (ex.: diário para dados críticos, semanal para configurações).
3. **Armazenamento** — documente onde os backups ficam (local, nuvem, storage externo) e como acessar.
4. **Testes de restauração** — planeje execuções periódicas para garantir que os artefatos funcionam.

## Processo de backup

- Identifique o comando/script responsável pela extração (ex.: `scripts/export_*.sh`, `pg_dump`, `restic`).
- Utilize `scripts/backup.sh <instancia>` para pausar a stack, copiar os dados persistidos para `backups/` e retomá-la ao final.
- Documente parâmetros obrigatórios (alvos, datas, diretórios temporários).
- Registre como versionar ou etiquetar os artefatos resultantes.
- Explique onde arquivar os relatórios de sucesso/erro.

### Script de backup automatizado

O `scripts/backup.sh` encapsula a sequência padrão de **parar ➜ copiar dados ➜ religar**. Alguns pontos de atenção:

- Pré-requisitos: `env/local/<instancia>.env` configurado, diretórios de dados acessíveis e espaço livre em `backups/`.
- O diretório final seguirá o padrão `backups/<instancia>-<YYYYMMDD-HHMMSS>`. Utilize `date` com `TZ` apropriado se precisar gerar snapshots em fusos distintos.
- Logs são emitidos na saída padrão/erro; redirecione para arquivos quando integrar a automações (ex.: `scripts/backup.sh core >> logs/backup.log 2>&1`).
- Para cenários com dados adicionais, exporte-os antes de executar o script (ex.: dumps de banco) e mova os artefatos para dentro do diretório gerado.
- Antes de interromper a stack, o script lista os serviços em execução chamando `docker compose ps --status running --services` via `scripts/compose.sh`. Os nomes retornados são combinados com o `deploy_context` para preservar a ordem esperada ao religar.
- Apenas os serviços identificados como ativos no início são religados ao final. Se nenhum serviço estava em execução antes do backup, o script finaliza sem subir novos serviços, mantendo o estado da stack.

#### Testando o fluxo

- Lint do script: `shfmt -d scripts/backup.sh` e `shellcheck scripts/backup.sh`.
- Testes automatizados que validam a parada, cópia e religamento: `pytest tests/backup_script -q`.
- Inclua checagens de restauração com frequência definida (ex.: mensal) copiando o snapshot para um ambiente isolado.

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
