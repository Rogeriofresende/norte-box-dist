#!/usr/bin/env python3
# planilha_confere.py — CHECKER-MODELO do portão "planilha→confere" do Norte-box.
#
# A ideia (padaria): quando a entrega é uma PLANILHA (uma tabela de dados), não basta o arquivo
# existir — a gente CONFERE o conteúdo. Este é o modelo do "conferidor": ele LÊ o arquivo de dados
# e ASSERTA sobre os VALORES. Se tudo bate, imprime os números conferidos e sai com sucesso (exit 0);
# se algo está errado, imprime O QUE está errado e sai com erro (exit != 0).
#
# A REGRA DE OURO (fail-honest — o que os 2 grupos grifaram): "rodou" != "conferiu". Um conferidor que
# só lê o arquivo e sempre sai 0 NÃO prova nada. Por isso este modelo SEMPRE tem pelo menos uma
# asserção de VALOR, e sai != 0 em QUALQUER falha. Se você adaptar, mantenha esta regra: pelo menos
# uma asserção de conteúdo, e sys.exit(1) em toda falha.
#
# COMO O MOTOR RODA: o motor copia o SEU checker + o SEU arquivo de dados pro mesmo sandbox e roda
# este script com o arquivo de dados acessível como "./dados.csv" (ou "./dados.json") no diretório
# atual. Você só precisa abrir "dados.csv" — o motor cuida do resto.
#
# COMO ADAPTAR (3 lugares marcados com # >>> ):
#   1) EXIGIDAS: as colunas que a planilha PRECISA ter.
#   2) a asserção de linhas > 0 (planilha vazia = erro).
#   3) a asserção de VALOR: aqui, "a coluna numérica não pode ter célula vazia e o total tem que ser
#      um número". Troque pela regra que faz sentido pra você (ex.: "preço > 0", "cpf preenchido").

import csv
import sys
from typing import NoReturn

# >>> 1) as colunas que a planilha PRECISA ter (troque pelas suas):
EXIGIDAS = ["coluna1", "coluna2"]

# nome fixo com que o motor entrega os dados no sandbox (não mude):
ARQUIVO = "dados.csv"


def erro(msg) -> NoReturn:
    """Imprime o que falhou e sai com erro (fail-honest: exit != 0).

    NoReturn deixa explícito (pra você e pro checador de código) que esta função
    NUNCA volta — sempre encerra em erro. Se você adaptar, mantenha o sys.exit."""
    print("ERRO:", msg)
    sys.exit(1)


def main():
    try:
        with open(ARQUIVO, newline="") as f:
            leitor = csv.DictReader(f)
            # colunas vêm do CABEÇALHO (fieldnames), não do corpo — assim "planilha vazia" (só
            # cabeçalho, 0 linhas) é diferente de "coluna faltando", e cada erro é reportado certo.
            cabecalho = leitor.fieldnames or []
            linhas = list(leitor)
    except FileNotFoundError:
        erro("não achei o arquivo de dados (%s)" % ARQUIVO)
    except Exception as e:
        # NÃO engolir: reportar o tipo do erro e reprovar (fail-honest).
        erro("não consegui ler o arquivo de dados: %s" % type(e).__name__)

    # colunas exigidas presentes?
    faltando = [c for c in EXIGIDAS if c not in cabecalho]
    if faltando:
        erro("colunas faltando: %s" % faltando)

    # >>> 2) planilha não pode estar vazia:
    if len(linhas) == 0:
        erro("planilha vazia (0 linhas de dados)")

    # >>> 3) asserção de VALOR (o coração do "conferir"): nenhuma célula das colunas exigidas pode
    # estar vazia. Troque/some regras conforme o seu caso (ex.: número > 0, data válida, etc).
    for i, linha in enumerate(linhas, start=1):
        for col in EXIGIDAS:
            valor = (linha.get(col) or "").strip()
            if valor == "":
                erro("célula vazia em '%s' na linha %d" % (col, i))

    # tudo conferido: imprime os números (isto aparece no "Ver rodar" da caixa) e sai com sucesso.
    print("CONFERIDO: %d linhas, colunas exigidas presentes e sem células vazias." % len(linhas))
    sys.exit(0)


if __name__ == "__main__":
    main()
