-- =====================================================================
-- Consultas de exemplo (treino para a apresentação). Não fazem parte da
-- entrega obrigatória; servem para praticar os JOINs do modelo.
-- =====================================================================

-- 1) Quantidade de aeródromos por UF e tipo de uso
SELECT m.uf, a.tipo_uso, count(*) AS qtd
FROM aerodromo a
JOIN municipio m ON m.id_municipio = a.id_municipio
GROUP BY m.uf, a.tipo_uso
ORDER BY m.uf, a.tipo_uso;

-- 2) As 10 maiores pistas, com aeródromo, município e superfície
SELECT a.nome, m.nome AS municipio, m.uf, p.designacao, p.comprimento_m, s.nome AS superficie
FROM pista p
JOIN aerodromo a  ON a.id_aerodromo  = p.id_aerodromo
JOIN municipio m  ON m.id_municipio  = a.id_municipio
JOIN superficie s ON s.id_superficie = p.id_superficie
ORDER BY p.comprimento_m DESC
LIMIT 10;

-- 3) Aeródromos que operam IFR à noite
SELECT a.ciad, a.codigo_oaci, a.nome
FROM aerodromo a
JOIN aerodromo_operacao o ON o.id_aerodromo = a.id_aerodromo
WHERE o.periodo = 'NOTURNO' AND o.regra_voo = 'IFR'
ORDER BY a.nome;

-- 4) Comprimento médio de pista por tipo de superfície
SELECT s.nome AS superficie, count(*) AS pistas, round(avg(p.comprimento_m), 1) AS comprimento_medio
FROM pista p
JOIN superficie s ON s.id_superficie = p.id_superficie
GROUP BY s.nome
ORDER BY comprimento_medio DESC;

-- 5) Aeródromos sem pista cadastrada
SELECT a.ciad, a.nome
FROM aerodromo a
LEFT JOIN pista p ON p.id_aerodromo = a.id_aerodromo
WHERE p.id_pista IS NULL;

-- 6) Aeródromos com operação internacional e suas modalidades
SELECT a.nome, string_agg(mi.sigla, ', ' ORDER BY mi.ordem) AS modalidades
FROM aerodromo a
JOIN aerodromo_operacao_internacional oi ON oi.id_aerodromo = a.id_aerodromo
JOIN modalidade_internacional mi         ON mi.sigla = oi.modalidade
GROUP BY a.nome
ORDER BY a.nome;

-- 7) Cadastros vencidos até hoje, por situação
SELECT a.situacao, count(*) AS vencidos
FROM aerodromo a
WHERE a.validade_cadastro < CURRENT_DATE
GROUP BY a.situacao;

-- 8) Municípios com mais aeródromos (top 5)
SELECT m.nome, m.uf, count(*) AS qtd
FROM aerodromo a
JOIN municipio m ON m.id_municipio = a.id_municipio
GROUP BY m.nome, m.uf
ORDER BY qtd DESC
LIMIT 5;

-- 9) Aeródromos com restrição operacional
SELECT a.nome, m.uf, a.restricao
FROM aerodromo a
JOIN municipio m ON m.id_municipio = a.id_municipio
WHERE a.restricao IS NOT NULL;

-- 10) A planilha original remontada (view)
SELECT * FROM vw_aerodromo_planilha ORDER BY id_aerodromo LIMIT 5;
