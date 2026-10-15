# Aeródromos da Região Norte (ANAC) — banco em PostgreSQL

## Como rodar (banco vazio)
```bash
createdb aerodromos
psql -d aerodromos -v ON_ERROR_STOP=1 -f 01_ddl.sql
psql -d aerodromos -v ON_ERROR_STOP=1 -f 02_carga.sql
```
Testado no PostgreSQL 16: roda sem erros e carrega 809 aeródromos, 653 pistas,
242 municípios, 1163 linhas de operação diurna/noturna e 13 de operação internacional.
`03_consultas_exemplo.sql` tem consultas para treinar para a apresentação.

## Tabelas e por que cada uma existe
| Tabela | Origem no CSV | Motivo |
|---|---|---|
| `uf` | `uf`, `uf_servido` | Domínio das siglas; o nome do estado fica num lugar só. |
| `municipio` | `municipio`+`uf`, `municipio_servido`+`uf_servido` | Os **dois pares de localização** apontam para a mesma tabela (`aerodromo.id_municipio` e `aerodromo.id_municipio_servido`), então nenhum município é gravado duas vezes. |
| `aerodromo` | colunas do aeródromo | Entidade principal. PK `id_aerodromo`; `ciad` e `codigo_oaci` são chaves candidatas (UNIQUE). |
| `pista` | colunas `pista1_*` | É **outra entidade** (tem id próprio, `pista1_id`). Relação 1:N com aeródromo: hoje cada aeródromo tem no máximo uma, mas o modelo aceita várias sem mudar nada. 156 aeródromos não têm pista (helipontos etc.). |
| `superficie` | `pista1_superficie` | Domínio que se repete (Asfalto, Terra...). |
| `regra_voo` + `aerodromo_operacao` | `operacao_diurna`, `operacao_noturna` | **Multivalorada** ("VFR / IFR"). Vira uma linha por (aeródromo, período, regra). "Sem Operação" virou o código `SEM`, diferente de célula vazia (não informado). |
| `modalidade_internacional` + `aerodromo_operacao_internacional` | `operacao_internacional` | **Multivalorada** ("... (RNS) / ... (AS)"). Uma linha por modalidade; a descrição longa fica só na tabela de domínio. |

## Normalização
- **1FN**: células com vários valores (" / ") viraram tabelas associativas. O PCN da pista
  (`78/F/D/X/T`) é um valor composto, então foi decomposto em 5 colunas atômicas
  (`pcn_valor`, `pcn_pavimento`, `pcn_subleito`, `pcn_pressao_pneu`, `pcn_avaliacao`).
- **2FN**: as tabelas associativas têm chave composta e nenhum atributo que dependa só de parte dela.
- **3FN**: dados que dependiam de outra coisa que não a chave saíram do aeródromo:
  dados da pista dependem de `pista1_id`; o nome do estado depende da UF; as descrições
  de superfície, regra de voo e modalidade dependem dos seus códigos.

## Dependências testadas nos dados (e mantidas no aeródromo)
- `amazonia_legal` **não** depende do município: SÃO GABRIEL DA CACHOEIRA, UIRAMUTÃ, NORMANDIA
  e MATEIROS aparecem com `true` e `false`. Por isso fica no aeródromo.
- `validade_cadastro` **não** depende de `link_portaria_cadastro`: o mesmo link aparece com
  duas validades diferentes. Por isso não virou tabela de portaria.
- A UF do aeródromo não é sempre o prefixo do CIAD (ex.: PI0035, GO0132 e BA0296 ficam em TO),
  então a UF vem do município, não do código.
- Quando `municipio_servido` está preenchido (77 casos) ele é sempre o próprio município do
  aeródromo; a FK aponta para o mesmo registro, sem duplicar.

## Restrições
PK e FK em todas as tabelas; NOT NULL onde o CSV nunca tem vazio; UNIQUE em `ciad`, `codigo_oaci`,
(`nome`,`uf`) do município e (`id_aerodromo`,`designacao`) da pista; CHECK de domínio
(tipo de uso, situação, classes RBAC, faixas de latitude/longitude, formato de CIAD/OACI/designação,
letras do PCN) e CHECKs de consistência da pista (PCN completo ou vazio; PCN **ou** peso/pressão).
Índices nas FKs usadas em JOIN (município, município servido, superfície, regra de voo).

## Prova de que nada foi perdido
A view `vw_aerodromo_planilha` remonta as 34 colunas originais. Comparando célula a célula com o
CSV, todas batem; a única diferença é que `municipio_servido` sai em MAIÚSCULAS ("RIO BRANCO"
em vez de "Rio Branco"), porque o município é gravado uma vez só, na grafia da coluna `municipio`.

## Carga
`02_carga.sql` é SQL puro (INSERTs), gerado pelo script `apoio/gerar_carga.py` a partir do CSV.
Para regerar: `python3 apoio/gerar_carga.py anac_aerodromos_norte.csv > 02_carga.sql`.
