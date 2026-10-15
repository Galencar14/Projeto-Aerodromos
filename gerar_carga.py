"""Gera 02_carga.sql a partir de anac_aerodromos_norte.csv.
Uso: python3 gerar_carga.py anac_aerodromos_norte.csv > 02_carga.sql"""
import csv, re, sys

UF_NOMES = {'AC': 'Acre', 'AM': 'Amazonas', 'AP': 'Amapá', 'PA': 'Pará',
            'RO': 'Rondônia', 'RR': 'Roraima', 'TO': 'Tocantins'}
REGRAS = [('VFR', 'Regras de voo visual', 1), ('IFR', 'Regras de voo por instrumentos', 2),
          ('SEM', 'Sem Operação', 3)]
MODALIDADES = [('RNS', 'Público Táxi Aéreo e Aviação Geral', 1),
               ('RS', 'Público Regular ou Charter', 2),
               ('AS', 'Público Regular ou Charter exclusivamente de voos alternados', 3)]

def q(v):
    """Literal SQL: vazio vira NULL, texto entre aspas simples."""
    return 'NULL' if v in ('', None) else "'" + str(v).replace("'", "''") + "'"
def n(v):
    return 'NULL' if v in ('', None) else v
def b(v):
    return {'true': 'TRUE', 'false': 'FALSE', '': 'NULL'}[v]

rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8')))
out = []
w = out.append
w('-- =====================================================================')
w('-- Aeródromos da Região Norte (ANAC) - Script de carga')
w('-- Executar depois de 01_ddl.sql, em um banco vazio.')
w('-- Gerado por apoio/gerar_carga.py a partir de anac_aerodromos_norte.csv')
w('-- =====================================================================\n')
w('BEGIN;\n')

w('-- UF')
w('INSERT INTO uf (sigla, nome) VALUES')
w(',\n'.join(f'    ({q(s)}, {q(nm)})' for s, nm in sorted(UF_NOMES.items())) + ';\n')

# Municípios: os dois pares (municipio/uf e municipio_servido/uf_servido)
# vão para a mesma tabela. O CSV grava o município em MAIÚSCULAS e o
# município servido em grafia normal; unificamos pela forma em maiúsculas.
muns = {}
for r in rows:
    muns.setdefault((r['municipio'], r['uf']), None)
    if r['municipio_servido']:
        key = (r['municipio_servido'].upper(), r['uf_servido'])
        muns.setdefault(key, None)
for i, key in enumerate(sorted(muns, key=lambda k: (k[1], k[0])), 1):
    muns[key] = i
w('-- Municípios')
w('INSERT INTO municipio (id_municipio, nome, uf) VALUES')
w(',\n'.join(f'    ({i}, {q(nm)}, {q(uf)})' for (nm, uf), i in muns.items()) + ';')
w("SELECT setval(pg_get_serial_sequence('municipio', 'id_municipio'), (SELECT max(id_municipio) FROM municipio));\n")

sups = {s: i for i, s in enumerate(sorted({r['pista1_superficie'] for r in rows if r['pista1_superficie']}), 1)}
w('-- Superfícies de pista')
w('INSERT INTO superficie (id_superficie, nome) VALUES')
w(',\n'.join(f'    ({i}, {q(s)})' for s, i in sups.items()) + ';')
w("SELECT setval(pg_get_serial_sequence('superficie', 'id_superficie'), (SELECT max(id_superficie) FROM superficie));\n")

w('-- Regras de voo')
w('INSERT INTO regra_voo (codigo, descricao, ordem) VALUES')
w(',\n'.join(f'    ({q(c)}, {q(d)}, {o})' for c, d, o in REGRAS) + ';\n')
w('-- Modalidades de operação internacional')
w('INSERT INTO modalidade_internacional (sigla, descricao, ordem) VALUES')
w(',\n'.join(f'    ({q(c)}, {q(d)}, {o})' for c, d, o in MODALIDADES) + ';\n')

aer, pis, ope, oin = [], [], [], []
regra_de = {'VFR': 'VFR', 'IFR': 'IFR', 'Sem Operação': 'SEM'}
modal_de = {f'{d} ({c})': c for c, d, _ in MODALIDADES}
for r in rows:
    ida = r['id_aerodromo']
    mid = muns[(r['municipio'], r['uf'])]
    msid = muns[(r['municipio_servido'].upper(), r['uf_servido'])] if r['municipio_servido'] else None
    aer.append('    (' + ', '.join([
        ida, q(r['ciad']), q(r['codigo_oaci']), q(r['tipo_uso']), q(r['nome']), str(mid), n(msid and str(msid)),
        r['latitude'], r['longitude'], n(r['altitude_m']), q(r['situacao']), n(r['classe_rbac153']),
        q(r['perfil_operacional_rbac153']), q(r['classe_rbac107']), b(r['certificacao_operacional']),
        q(r['validade_cadastro']), q(r['link_portaria_cadastro']), q(r['restricao']), b(r['amazonia_legal'])]) + ')')
    if r['pista1_id']:
        pcn = r['pista1_resistencia_pcn'].split('/') if r['pista1_resistencia_pcn'] else [''] * 5
        assert len(pcn) == 5
        pis.append('    (' + ', '.join([
            r['pista1_id'], ida, q(r['pista1_designacao']), r['pista1_comprimento_m'], r['pista1_largura_m'],
            str(sups[r['pista1_superficie']]), n(r['pista1_resistencia_kg']), n(r['pista1_resistencia_mpa']),
            n(pcn[0]), q(pcn[1]), q(pcn[2]), q(pcn[3]), q(pcn[4]),
            b(r['pista1_luzes_eixo']), b(r['pista1_luzes_borda'])]) + ')')
    for periodo, col in (('DIURNO', 'operacao_diurna'), ('NOTURNO', 'operacao_noturna')):
        if r[col]:
            for v in r[col].split(' / '):
                ope.append(f"    ({ida}, '{periodo}', '{regra_de[v]}')")
    if r['operacao_internacional']:
        for v in r['operacao_internacional'].split(' / '):
            oin.append(f"    ({ida}, '{modal_de[v]}')")

w(f'-- Aeródromos ({len(aer)} linhas)')
w('INSERT INTO aerodromo (id_aerodromo, ciad, codigo_oaci, tipo_uso, nome, id_municipio, id_municipio_servido,')
w('    latitude, longitude, altitude_m, situacao, classe_rbac153, perfil_operacional_rbac153, classe_rbac107,')
w('    certificacao_operacional, validade_cadastro, link_portaria_cadastro, restricao, amazonia_legal) VALUES')
w(',\n'.join(aer) + ';\n')
w(f'-- Pistas ({len(pis)} linhas)')
w('INSERT INTO pista (id_pista, id_aerodromo, designacao, comprimento_m, largura_m, id_superficie,')
w('    resistencia_kg, resistencia_mpa, pcn_valor, pcn_pavimento, pcn_subleito, pcn_pressao_pneu, pcn_avaliacao,')
w('    luzes_eixo, luzes_borda) VALUES')
w(',\n'.join(pis) + ';\n')
w(f'-- Operação diurna/noturna ({len(ope)} linhas)')
w('INSERT INTO aerodromo_operacao (id_aerodromo, periodo, regra_voo) VALUES')
w(',\n'.join(ope) + ';\n')
w(f'-- Operação internacional ({len(oin)} linhas)')
w('INSERT INTO aerodromo_operacao_internacional (id_aerodromo, modalidade) VALUES')
w(',\n'.join(oin) + ';\n')
w('COMMIT;')
print('\n'.join(out))
