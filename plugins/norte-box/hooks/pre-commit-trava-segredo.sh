#!/usr/bin/env bash
# pre-commit-trava-segredo.sh - a TRAVA ANTI-SEGREDO do Norte-box (git pre-commit hook).
#
# O QUE FAZ: antes de cada `git commit`, olha SO o que voce esta ADICIONANDO (as linhas novas
# do staged diff) e, se achar um segredo ou dado sensivel, ABORTA o commit (modo BLOQUEIA).
# Motivo: uma vez que uma senha/CPF/extrato entra no historico do Git, sai do controle - fica
# no historico pra sempre e, se aquele repo for pra qualquer lugar (backup, GitHub, colega),
# vazou. E irreversivel. Este freio para isso ANTES de acontecer.
#
# O QUE ELE PEGA (classes de risco):
#   - Senhas / app-passwords / conteudo de .env (X=segredo)
#   - Chaves de API / tokens (sk-, ghp_, github_pat_, AKIA, aact_, xox*-, AIza)
#   - Chave privada (-----BEGIN ... PRIVATE KEY)
#   - CPF (000.000.000-00 e 11 digitos soltos) e CNPJ formatado
#   - Numero de conta/agencia bancaria e mencoes obvias de extrato/saldo/folha
#
# O QUE ELE **NAO** PEGA (honestidade - ver docs/SECURITY.md):
#   - Segredo que voce ja tinha commitado ANTES da trava (ela olha so o que ENTRA agora).
#   - Segredo dentro de arquivo binario (imagem/pdf/zip) - o diff nao mostra o texto.
#   - Um CPF de 11 digitos sem nenhuma pista ao redor pode passar (guard anti-falso-positivo).
#   Regra de ouro que fecha o buraco: **dado sensivel nao vai pro Git, ponto** - fica no
#   sistema/planilha de sempre. A trava e a rede de baixo, nao a unica.
#
# BYPASS CONSCIENTE (documentado): se voce SABE que e falso-positivo (ex: um CPF de exemplo
# num teste, um "sk-" que e outra coisa), rode o commit com a trava desligada de proposito:
#     NORTE_TRAVA_SEGREDO_OFF=1 git commit -m "..."
# So vale pra ESSE commit PORQUE a variavel esta so na frente do comando (nao fica no shell).
# ATENCAO (honestidade): se voce em vez disso rodar `export NORTE_TRAVA_SEGREDO_OFF=1`, a trava
# fica DESLIGADA pra TODOS os commits desse terminal ate voce fechar/`unset` - NAO "some sozinha".
# Por isso, quando o OFF vem do ambiente exportado, a trava AVISA no stderr (veja abaixo).
#
# FAIL-SAFE vs FAIL-OPEN (a decisao de design, cravada pro contexto Supren):
#   Esta trava e a UNICA defesa antes do irreversivel. Se ela nao consegue rodar o diff
#   (git quebrado, sem `git`), ela AVISA e BLOQUEIA (fail-safe) em vez de deixar passar calada -
#   o custo de um commit barrado por engano (rode com OFF=1) e MUITO menor que o de um extrato
#   no historico. (Difere do secret-guard de CHAT, que e fail-open porque nunca pode derrubar a
#   sessao; aqui o risco protegido e irreversivel, entao pesa pro lado seguro.)
#
# ENCADEAMENTO: se voce ja tinha um pre-commit hook proprio, o instalador o preserva como
# `pre-commit.local` e esta trava o chama ao final (nao engole o seu hook).

set -u

# --- bypass consciente -------------------------------------------------------------------------
if [ "${NORTE_TRAVA_SEGREDO_OFF:-}" = "1" ]; then
  printf '\033[1;33m[trava-segredo] DESLIGADA por NORTE_TRAVA_SEGREDO_OFF=1 (bypass consciente).\033[0m\n' >&2
  # Honestidade: se a var foi EXPORTADA no shell (nao so posta na frente do comando), ela vale
  # pra TODO commit deste terminal ate `unset`/fechar - nao "some sozinha". Avisamos.
  case "$(export -p 2>/dev/null)" in
    *"NORTE_TRAVA_SEGREDO_OFF="*)
      printf '\033[1;31m[trava-segredo] ATENCAO: NORTE_TRAVA_SEGREDO_OFF esta EXPORTADA no seu shell - a trava\n   fica desligada pra TODOS os commits deste terminal. Pra religar: `unset NORTE_TRAVA_SEGREDO_OFF`.\033[0m\n' >&2
      ;;
  esac
  # ainda encadeia o hook local do usuario, se houver
  _local="$(git rev-parse --git-path hooks/pre-commit.local 2>/dev/null)"
  [ -n "${_local:-}" ] && [ -x "$_local" ] && exec "$_local" "$@"
  exit 0
fi

# --- precisa do git pra ver o diff. Sem git = fail-SAFE (bloqueia, avisa) ----------------------
if ! command -v git >/dev/null 2>&1; then
  printf '\033[1;31m[trava-segredo] Nao achei o `git` pra conferir o commit. Por seguranca, BLOQUEEI.\033[0m\n' >&2
  printf '   (Se precisar mesmo commitar agora: NORTE_TRAVA_SEGREDO_OFF=1 git commit ...)\n' >&2
  exit 1
fi

# Diff do que esta STAGED (o que vai entrar no commit), so as linhas ADICIONADAS.
# --unified=0 = so as linhas mudadas (sem contexto). Filtramos as que comecam com '+' (add)
# e tiramos o cabecalho '+++ b/arquivo'. Guardamos tambem o arquivo de cada bloco pra apontar.
STAGED="$(git diff --cached --unified=0 --no-color --diff-filter=ACM 2>/dev/null)"
if [ -z "$STAGED" ]; then
  # nada staged de texto (ou so delecoes/renames) - nada a barrar aqui. Encadeia local e sai.
  _local="$(git rev-parse --git-path hooks/pre-commit.local 2>/dev/null)"
  [ -n "${_local:-}" ] && [ -x "$_local" ] && exec "$_local" "$@"
  exit 0
fi

# --- PADROES (espelham o secret-guard de chat + o gate secret_pii.sh, + adicoes Supren) --------
# Cada regra: NOME|regex|explicacao-humana. A explicacao aparece na mensagem de bloqueio.
# ATENCAO: NUNCA imprimimos o VALOR casado (o segredo) - so o arquivo, a linha e o TIPO.
# Regras "fortes" (alta confianca, baixo falso-positivo):
REGRAS_FORTES=(
  'chave-privada|-----BEGIN [A-Z ]*PRIVATE KEY|uma chave privada (-----BEGIN ... PRIVATE KEY)'
  'token-anthropic|sk-(ant-)?[A-Za-z0-9_-]{20,}|uma chave de API (formato sk-...)'
  'token-github|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|um token do GitHub (ghp_/github_pat_)'
  'token-aws|AKIA[A-Z0-9]{16}|uma chave da AWS (AKIA...)'
  'token-asaas|aact_[A-Za-z0-9_-]{20,}|um token do Asaas (aact_...)'
  'token-slack|xox[bporas]-[A-Za-z0-9-]{10,}|um token do Slack (xox...-)'
  'token-google|AIza[0-9A-Za-z_-]{35}|uma chave do Google (AIza...)'
  'app-password|[A-Za-z_]*APP_PASSWORD[[:space:]]*[:=][[:space:]]*[^[:space:]]+|uma app-password (SENHA=...)'
  'segredo-env|[A-Za-z_]*(PASSWORD|PASSWD|SENHA|SECRET|SEGREDO|API_KEY|APIKEY|TOKEN|PRIVATE_KEY)[A-Za-z_]*[[:space:]]*[:=][[:space:]]*[^[:space:]#"'\''][^[:space:]]{4,}|conteudo de .env / uma senha ou segredo (X=...)'
  'cpf-formatado|[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2}|um CPF (000.000.000-00)'
  'cnpj-formatado|[0-9]{2}\.[0-9]{3}\.[0-9]{3}/[0-9]{4}-[0-9]{2}|um CNPJ (00.000.000/0000-00)'
)
# Regras "por contexto" (so disparam se houver uma PISTA **E** um NUMERO/VALOR na MESMA linha).
# Duas condicoes juntas = so barra o dado BRUTO sensivel; prosa que so *menciona* financa
# (sem numero) passa. Ex.: "banco de ideias", "agencia de marketing", "faturamento subiu 20%"
# NAO tem numero-de-conta/valor-monetario ao lado da pista -> passam.
#
# FORMATO (importante - foi o bug do #12): campos separados por '@@@' (nao por '|'),
# pra a PISTA e o NUMREGEX poderem conter '|' de alternativa livremente.
#   nome @@@ regex-do-numero/valor @@@ regex-da-pista @@@ explicacao
# A pista casa QUALQUER uma das alternativas (extrato|saldo|conta|agencia|folha|salario|holerite).
REGRAS_CONTEXTO=(
  'cpf-11-digitos@@@(^|[^0-9])[0-9]{11}([^0-9]|$)@@@[Cc][Pp][Ff]@@@um CPF de 11 digitos (a linha fala em CPF)'
  'conta-agencia@@@(^|[^0-9])[0-9]{4,8}-?[0-9xX]([^0-9]|$)@@@[Aa]g[êe]ncia|[Cc]onta( corrente)?|[Cc]/[Cc]@@@um numero de conta/agencia bancaria'
  'saldo-valor@@@(R\$[[:space:]]*)?[0-9]{1,3}([.,][0-9]{3})*[.,][0-9]{2}([^0-9]|$)|R\$[[:space:]]*[0-9]@@@[Ee]xtrato|[Ss]aldo|[Ff]olha de pagamento|[Ss]al[aá]rio|[Hh]olerite|[Rr]emunera[cç][aã]o@@@um trecho de extrato / saldo / folha de pagamento (pista + valor R$)'
)

ACHOU=0
DETALHES=""      # linhas "arquivo:linha :: tipo" (nunca o valor)
arquivo_atual="?"
linha_no=0

# Percorre o diff. `@@ -a,b +c,d @@` marca o inicio de um bloco; `+++ b/<arquivo>` marca o arquivo.
# A partir do @@, cada linha '+...' e a linha (c + offset) do NOVO arquivo.
while IFS= read -r linha; do
  case "$linha" in
    '+++ '*)
      arquivo_atual="${linha#+++ b/}"
      arquivo_atual="${arquivo_atual#+++ }"
      continue
      ;;
    '@@'*)
      # extrai o "+c" de "@@ -a,b +c,d @@"
      novo="${linha#*+}"; novo="${novo%% *}"; novo="${novo%%,*}"
      linha_no="$novo"
      continue
      ;;
    '+'*)
      conteudo="${linha#+}"
      # testa cada regra FORTE
      for r in "${REGRAS_FORTES[@]}"; do
        nome="${r%%|*}"; resto="${r#*|}"
        expl="${resto##*|}"; regex="${resto%|*}"
        if printf '%s' "$conteudo" | grep -qE -- "$regex"; then
          ACHOU=1
          DETALHES="${DETALHES}  - ${arquivo_atual}:${linha_no}  ->  ${expl}"$'\n'
          break
        fi
      done
      # testa cada regra POR CONTEXTO (NUMERO/VALOR **E** palavra-pista na MESMA linha).
      # Campos separados por '@@@' (NAO por '|'): assim pista e numregex podem ter '|' de
      # alternativa sem quebrar o split (era o bug do #12 - so a ultima alternativa sobrava).
      for r in "${REGRAS_CONTEXTO[@]}"; do
        nome="${r%%@@@*}"; resto="${r#*@@@}"
        numregex="${resto%%@@@*}"; resto="${resto#*@@@}"
        pista="${resto%%@@@*}"; expl="${resto#*@@@}"
        if printf '%s' "$conteudo" | grep -qE -- "$numregex" && printf '%s' "$conteudo" | grep -qE -- "$pista"; then
          ACHOU=1
          DETALHES="${DETALHES}  - ${arquivo_atual}:${linha_no}  ->  ${expl}"$'\n'
          break
        fi
      done
      linha_no=$((linha_no + 1))
      ;;
  esac
done <<EOF
$STAGED
EOF

if [ "$ACHOU" = "1" ]; then
  cat >&2 <<'CABECA'

  ╔══════════════════════════════════════════════════════════════════════╗
  ║  🛑 TRAVA DA NORTE: esse commit tem dado sensivel — foi BLOQUEADO.     ║
  ╚══════════════════════════════════════════════════════════════════════╝
CABECA
  printf '\n  O que eu vi entrar no commit (NAO mostro o valor, so onde esta):\n\n' >&2
  printf '%s\n' "$DETALHES" >&2
  cat >&2 <<'RODAPE'
  A REGRA DE OURO:
    dado sensivel — extrato, senha, CPF, folha de pagamento, token — NAO entra no Git.
    Ele fica no sistema/planilha de sempre. No Git so vai codigo e documento comum.

  Por que a Norte trava isso: uma vez no historico do Git, o dado sai do controle
  (backup, GitHub, colega) e nao tem "desfazer" — e pra sempre. Melhor barrar agora.

  O QUE FAZER:
    1. Tire o dado sensivel do arquivo (deixe-o na planilha/sistema de origem);
    2. `git add` de novo e commit — vai passar.

  Se voce TEM CERTEZA que e falso-positivo (ex: um CPF de exemplo num teste):
    NORTE_TRAVA_SEGREDO_OFF=1 git commit -m "sua mensagem"
    (vale so pra ESTE commit; volta a proteger no proximo.)

RODAPE
  # log so o evento (nunca o valor) - best-effort, nunca quebra por causa do log
  echo "[trava-segredo] BLOCKED $(date -u +%FT%TZ)" >> "${HOME}/.norte-box/trava-segredo.log" 2>/dev/null || true
  exit 1
fi

# Passou a trava. Encadeia o hook local do usuario (se ele tinha um), preservando o comportamento dele.
_local="$(git rev-parse --git-path hooks/pre-commit.local 2>/dev/null)"
if [ -n "${_local:-}" ] && [ -x "$_local" ]; then
  exec "$_local" "$@"
fi
exit 0
