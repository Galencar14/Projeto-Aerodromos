-- =====================================================================
-- Aeródromos da Região Norte (ANAC) - Script de criação (DDL)
-- PostgreSQL 13+   |   Executar em um banco vazio, antes de 02_carga.sql
-- Equipe: Lucas Jatene, Anderson Silva e Gustavo Alencar
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Localização
-- ---------------------------------------------------------------------

-- Unidade federativa. Evita repetir o nome do estado e garante siglas válidas.
CREATE TABLE uf (
    sigla  CHAR(2)     PRIMARY KEY CHECK (sigla ~ '^[A-Z]{2}$'),
    nome   VARCHAR(30) NOT NULL UNIQUE
);

-- Município. Os dois pares da planilha (municipio/uf e
-- municipio_servido/uf_servido) apontam para esta mesma tabela,
-- então cada município é gravado uma única vez.
CREATE TABLE municipio (
    id_municipio  SERIAL      PRIMARY KEY,
    nome          VARCHAR(60) NOT NULL,
    uf            CHAR(2)     NOT NULL REFERENCES uf (sigla),
    CONSTRAINT uq_municipio_nome_uf UNIQUE (nome, uf)
);
CREATE INDEX ix_municipio_uf ON municipio (uf);

-- ---------------------------------------------------------------------
-- Tabelas de domínio (valores que se repetem em muitas linhas)
-- ---------------------------------------------------------------------

-- Tipo de superfície da pista (Asfalto, Terra, Cascalho...).
CREATE TABLE superficie (
    id_superficie  SERIAL      PRIMARY KEY,
    nome           VARCHAR(30) NOT NULL UNIQUE
);

-- Regras de voo usadas em operacao_diurna / operacao_noturna.
-- 'SEM' representa o valor "Sem Operação" da planilha.
CREATE TABLE regra_voo (
    codigo     VARCHAR(3)  PRIMARY KEY,
    descricao  VARCHAR(40) NOT NULL UNIQUE,
    ordem      SMALLINT    NOT NULL UNIQUE   -- ordem de exibição (VFR antes de IFR)
);

-- Modalidades de operação internacional (RNS, RS, AS).
CREATE TABLE modalidade_internacional (
    sigla      VARCHAR(3)   PRIMARY KEY,
    descricao  VARCHAR(100) NOT NULL UNIQUE,
    ordem      SMALLINT     NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- Aeródromo (entidade principal)
-- ---------------------------------------------------------------------
CREATE TABLE aerodromo (
    id_aerodromo               INTEGER      PRIMARY KEY,
    ciad                       CHAR(6)      NOT NULL UNIQUE CHECK (ciad ~ '^[A-Z]{2}[0-9]{4}$'),
    codigo_oaci                CHAR(4)      UNIQUE CHECK (codigo_oaci ~ '^[A-Z][A-Z0-9]{3}$'),
    tipo_uso                   VARCHAR(7)   CHECK (tipo_uso IN ('Público', 'Privado')),
    nome                       VARCHAR(100) NOT NULL,
    id_municipio               INTEGER      NOT NULL REFERENCES municipio (id_municipio),
    id_municipio_servido       INTEGER      REFERENCES municipio (id_municipio),
    latitude                   NUMERIC(9,6) NOT NULL CHECK (latitude  BETWEEN -90  AND 90),
    longitude                  NUMERIC(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    altitude_m                 NUMERIC(6,1) CHECK (altitude_m >= 0),
    situacao                   VARCHAR(12)  NOT NULL CHECK (situacao IN ('Cadastrado', 'Autorizado', 'Interditado')),
    classe_rbac153             SMALLINT     CHECK (classe_rbac153 BETWEEN 1 AND 4),
    perfil_operacional_rbac153 VARCHAR(20)  CHECK (perfil_operacional_rbac153 IN ('RBAC 121', 'RBAC 135 Regular', 'Outras Operações')),
    classe_rbac107             VARCHAR(4)   CHECK (classe_rbac107 IN ('AP-0', 'AP-1', 'AP-2', 'AP-3')),
    certificacao_operacional   BOOLEAN      NOT NULL,
    validade_cadastro          DATE,
    link_portaria_cadastro     VARCHAR(200) CHECK (link_portaria_cadastro ~ '^https?://'),
    restricao                  TEXT,
    amazonia_legal             BOOLEAN      NOT NULL
);
CREATE INDEX ix_aerodromo_municipio         ON aerodromo (id_municipio);
CREATE INDEX ix_aerodromo_municipio_servido ON aerodromo (id_municipio_servido);
CREATE INDEX ix_aerodromo_nome              ON aerodromo (nome);

-- ---------------------------------------------------------------------
-- Pista (colunas pista1_* da planilha). Relação 1:N com aeródromo:
-- neste recorte cada aeródromo tem no máximo uma pista, mas o modelo
-- aceita várias.
-- ---------------------------------------------------------------------
CREATE TABLE pista (
    id_pista          INTEGER      PRIMARY KEY,
    id_aerodromo      INTEGER      NOT NULL REFERENCES aerodromo (id_aerodromo) ON DELETE CASCADE,
    designacao        VARCHAR(7)   NOT NULL CHECK (designacao ~ '^[0-9]{2}[LCR]?/[0-9]{2}[LCR]?$'),
    comprimento_m     NUMERIC(6,1) NOT NULL CHECK (comprimento_m > 0),
    largura_m         NUMERIC(5,1) NOT NULL CHECK (largura_m > 0),
    id_superficie     INTEGER      NOT NULL REFERENCES superficie (id_superficie),
    -- Resistência informada como peso máximo / pressão (pistas pequenas) ...
    resistencia_kg    NUMERIC(8,1) CHECK (resistencia_kg > 0),
    resistencia_mpa   NUMERIC(6,2) CHECK (resistencia_mpa > 0),
    -- ... ou como PCN (ex.: 78/F/D/X/T), decomposto em partes atômicas (1FN)
    pcn_valor         SMALLINT     CHECK (pcn_valor > 0),
    pcn_pavimento     CHAR(1)      CHECK (pcn_pavimento    IN ('F', 'R')),            -- Flexível / Rígido
    pcn_subleito      CHAR(1)      CHECK (pcn_subleito     IN ('A', 'B', 'C', 'D')),  -- resistência do subleito
    pcn_pressao_pneu  CHAR(1)      CHECK (pcn_pressao_pneu IN ('W', 'X', 'Y', 'Z')),  -- pressão máx. dos pneus
    pcn_avaliacao     CHAR(1)      CHECK (pcn_avaliacao    IN ('T', 'U')),            -- Técnica / Uso (experiência)
    luzes_eixo        BOOLEAN,
    luzes_borda       BOOLEAN,
    CONSTRAINT uq_pista_aerodromo_designacao UNIQUE (id_aerodromo, designacao),
    -- As 5 partes do PCN existem juntas ou nenhuma existe
    CONSTRAINT ck_pista_pcn_completo CHECK (
        (pcn_valor IS NULL) = (pcn_pavimento IS NULL) AND
        (pcn_valor IS NULL) = (pcn_subleito IS NULL) AND
        (pcn_valor IS NULL) = (pcn_pressao_pneu IS NULL) AND
        (pcn_valor IS NULL) = (pcn_avaliacao IS NULL)
    ),
    -- Uma pista usa PCN ou peso/pressão, nunca os dois
    CONSTRAINT ck_pista_resistencia_exclusiva CHECK (pcn_valor IS NULL OR resistencia_kg IS NULL)
);
-- (id_aerodromo já é indexado pela UNIQUE acima, que começa por ele)
CREATE INDEX ix_pista_superficie ON pista (id_superficie);

-- ---------------------------------------------------------------------
-- Colunas multivaloradas ("A / B" na mesma célula) viram tabelas
-- associativas, uma linha por valor.
-- ---------------------------------------------------------------------

-- operacao_diurna e operacao_noturna
CREATE TABLE aerodromo_operacao (
    id_aerodromo  INTEGER    NOT NULL REFERENCES aerodromo (id_aerodromo) ON DELETE CASCADE,
    periodo       VARCHAR(7) NOT NULL CHECK (periodo IN ('DIURNO', 'NOTURNO')),
    regra_voo     VARCHAR(3) NOT NULL REFERENCES regra_voo (codigo),
    PRIMARY KEY (id_aerodromo, periodo, regra_voo)
);
CREATE INDEX ix_aerodromo_operacao_regra ON aerodromo_operacao (regra_voo, periodo);

-- operacao_internacional
CREATE TABLE aerodromo_operacao_internacional (
    id_aerodromo  INTEGER    NOT NULL REFERENCES aerodromo (id_aerodromo) ON DELETE CASCADE,
    modalidade    VARCHAR(3) NOT NULL REFERENCES modalidade_internacional (sigla),
    PRIMARY KEY (id_aerodromo, modalidade)
);

-- ---------------------------------------------------------------------
-- View que remonta a planilha original (34 colunas) a partir das
-- tabelas normalizadas: prova de que nenhuma informação foi perdida.
-- ---------------------------------------------------------------------
CREATE VIEW vw_aerodromo_planilha AS
SELECT
    a.id_aerodromo,
    a.ciad,
    a.codigo_oaci,
    a.tipo_uso,
    a.nome,
    m.nome  AS municipio,
    m.uf,
    ms.nome AS municipio_servido,
    ms.uf   AS uf_servido,
    a.latitude,
    a.longitude,
    a.altitude_m,
    (SELECT string_agg(rv.codigo, ' / ' ORDER BY rv.ordem)
       FROM aerodromo_operacao o JOIN regra_voo rv ON rv.codigo = o.regra_voo
      WHERE o.id_aerodromo = a.id_aerodromo AND o.periodo = 'DIURNO')  AS operacao_diurna,
    (SELECT string_agg(CASE rv.codigo WHEN 'SEM' THEN rv.descricao ELSE rv.codigo END, ' / ' ORDER BY rv.ordem)
       FROM aerodromo_operacao o JOIN regra_voo rv ON rv.codigo = o.regra_voo
      WHERE o.id_aerodromo = a.id_aerodromo AND o.periodo = 'NOTURNO') AS operacao_noturna,
    p.id_pista          AS pista1_id,
    p.designacao        AS pista1_designacao,
    p.comprimento_m     AS pista1_comprimento_m,
    p.largura_m         AS pista1_largura_m,
    p.resistencia_kg    AS pista1_resistencia_kg,
    p.resistencia_mpa   AS pista1_resistencia_mpa,
    CASE WHEN p.pcn_valor IS NOT NULL THEN
        concat_ws('/', p.pcn_valor, p.pcn_pavimento, p.pcn_subleito, p.pcn_pressao_pneu, p.pcn_avaliacao)
    END                 AS pista1_resistencia_pcn,
    s.nome              AS pista1_superficie,
    p.luzes_eixo        AS pista1_luzes_eixo,
    p.luzes_borda       AS pista1_luzes_borda,
    a.situacao,
    a.classe_rbac153,
    a.perfil_operacional_rbac153,
    a.classe_rbac107,
    (SELECT string_agg(mi.descricao || ' (' || mi.sigla || ')', ' / ' ORDER BY mi.ordem)
       FROM aerodromo_operacao_internacional oi
       JOIN modalidade_internacional mi ON mi.sigla = oi.modalidade
      WHERE oi.id_aerodromo = a.id_aerodromo) AS operacao_internacional,
    a.certificacao_operacional,
    a.validade_cadastro,
    a.link_portaria_cadastro,
    a.restricao,
    a.amazonia_legal
FROM aerodromo a
JOIN municipio m        ON m.id_municipio  = a.id_municipio
LEFT JOIN municipio ms  ON ms.id_municipio = a.id_municipio_servido
LEFT JOIN pista p       ON p.id_aerodromo  = a.id_aerodromo
LEFT JOIN superficie s  ON s.id_superficie = p.id_superficie;

COMMIT;
