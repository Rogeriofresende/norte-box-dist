#!/usr/bin/env bash
# _redact.sh — REDATOR PORTATIL compartilhado do norte-box (FONTE UNICA).
#
# Por que existe: antes havia DUAS copias do redator (telemetry-emit.sh e norte-login.sh)
# que DIVERGIAM nos formatos cobertos (uma tinha ya29., a outra tinha cartao/app-password).
# Auditoria multi-IA (docs/research/2026-07-31) marcou isso como o furo #4. Uma copia unica
# elimina a divergencia pra sempre: qualquer formato novo entra AQUI e vale nos dois lugares.
#
# NAO e um hook (nome com _ inicial, nao esta no hooks.json). E uma BIBLIOTECA sourceada.
# Sourcear um arquivo ENVIADO do plugin (nao dado do usuario) e seguro — diferente de
# sourcear ~/.norte-box/.env (dado do usuario = furo #2, corrigido por leitor sem eval).
#
# HONESTIDADE (furo #4, licao de 20 anos de WAF-bypass): um redator baseado em LISTA de
# padroes SEMPRE deixa passar algum formato novo. Ele reduz o vazamento de secret conhecido,
# NAO garante zero. O termo "ver tudo" nao pode prometer redacao perfeita — so "tiramos os
# secrets/PII que a gente RECONHECE, e se falhar num campo, dropamos o campo".
#
# NOME/CAMINHO DE ARQUIVO (furo do termo #7, fechado aqui): o Read/Write/Edit manda o
# tool_input.file_path — o CAMINHO do arquivo. Uma dentista (1a usuaria) que abre
# /laudos/paciente.pdf estava vazando o NOME do paciente pra Norte (dado de saude, LGPD).
# Agora o redator TAMBEM mascara caminhos ANTES de guardar/enviar, MAS preserva a extensao
# ("[arquivo:.pdf]") pra o "ver tudo" continuar sabendo QUE um arquivo foi aberto e o TIPO —
# sem o nome. Caminho sem extensao vira "[REDACTED-PATH]". Nao ha cegueira: o evento continua
# (a acao/ferramenta e contada), so o NOME identificante sai. Como todo blocklist, e
# best-effort: cobre os formatos comuns (unix absoluto/relativo, ~/, Windows, em prosa, e
# URL terminando em nome-de-arquivo), nao promete pegar todo formato exotico.
#
# Contrato:
#   _redact       : le stdin -> escreve stdout com secret/PII mascarados. return !=0 se explodir.
#   _safe_field   : recebe $1, devolve a versao redigida OU vazio se a redacao falhar (fail-closed).
# Portabilidade macOS bash 3.2 + BSD sed (ERE via -E, classes POSIX, backrefs \1).

# Le stdin, mascara secret/PII conhecido + NOME/CAMINHO de arquivo. Ordem: mais especifico
# primeiro; os caminhos vao POR ULTIMO (secret/PII ja mascarados) e preservam so a extensao.
_redact() {
  local _in
  _in="$(cat 2>/dev/null)" || return 1
  printf '%s' "$_in" | sed -E \
    -e 's/[0-9]{4}[[:space:]][0-9]{4}[[:space:]][0-9]{4}[[:space:]][0-9]{4}/[REDACTED-CARD]/g' \
    -e 's/[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}/[REDACTED-CARD]/g' \
    -e 's/[0-9]{16}/[REDACTED-CARD]/g' \
    -e 's/[A-Za-z0-9]{4}[[:space:]][A-Za-z0-9]{4}[[:space:]][A-Za-z0-9]{4}[[:space:]][A-Za-z0-9]{4}/[REDACTED-APP-PASSWORD]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{4,}\.eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}/[REDACTED-JWT]/g' \
    -e 's/ya29\.[A-Za-z0-9_-]{10,}/[REDACTED-KEY]/g' \
    -e 's/(sk|rk|pk)_(live|test)_[A-Za-z0-9]{10,}/[REDACTED-KEY]/g' \
    -e 's/whsec_[A-Za-z0-9]{10,}/[REDACTED-KEY]/g' \
    -e 's/sk-(ant-|proj-)?[A-Za-z0-9_-]{6,}/[REDACTED-KEY]/g' \
    -e 's/gh[pousr]_[A-Za-z0-9]{10,}/[REDACTED-KEY]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{10,}/[REDACTED-KEY]/g' \
    -e 's/glpat-[A-Za-z0-9_-]{10,}/[REDACTED-KEY]/g' \
    -e 's/hf_[A-Za-z0-9]{10,}/[REDACTED-KEY]/g' \
    -e 's/npm_[A-Za-z0-9]{20,}/[REDACTED-KEY]/g' \
    -e 's/AKIA[A-Z0-9]{16}/[REDACTED-KEY]/g' \
    -e 's/(AC|SK)[0-9a-fA-F]{32}/[REDACTED-KEY]/g' \
    -e 's/aact_[A-Za-z0-9_-]{10,}/[REDACTED-KEY]/g' \
    -e 's/xox[bporas]-[A-Za-z0-9-]{10,}/[REDACTED-KEY]/g' \
    -e 's/AIza[0-9A-Za-z_-]{35}/[REDACTED-KEY]/g' \
    -e 's#[Bb]earer[[:space:]]+[A-Za-z0-9._~+/=-]{12,}#Bearer [REDACTED-TOKEN]#g' \
    -e 's#([a-zA-Z][a-zA-Z0-9+.-]*://)[^:@/[:space:]]+:[^@/[:space:]]+@#\1[REDACTED-CREDENTIAL]@#g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED-PRIVATE-KEY]/g' \
    -e 's/([A-Za-z0-9_]*(KEY|SECRET|TOKEN|PASSWORD|PASSWD|PASS|PWD|AUTH|CREDENTIAL)[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*)[^[:space:]"'"'"']{6,}/\1[REDACTED]/g' \
    -e 's/("?[A-Za-z0-9_]*(key|secret|token|password|passwd|pass|pwd|auth|credential)[A-Za-z0-9_]*"?[[:space:]]*[:=][[:space:]]*"?)[^[:space:],}"'"'"']{6,}/\1[REDACTED]/g' \
    -e 's/[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2}/[REDACTED-CPF]/g' \
    -e 's/[0-9]{2}\.[0-9]{3}\.[0-9]{3}\/[0-9]{4}-[0-9]{2}/[REDACTED-CNPJ]/g' \
    -e 's#([A-Za-z]:\\[^[:space:]"'"'"',:;]*\\[^\\/[:space:]"'"'"',:;]*)\.([A-Za-z0-9]{1,8})#[arquivo:.\2]#g' \
    -e 's#([A-Za-z]:\\[^[:space:]"'"'"',:;]*\\[^\\/[:space:]"'"'"',:;]+)#[REDACTED-PATH]#g' \
    -e 's#([a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]"'"'"']*/)([A-Za-z0-9._+-]*[A-Za-z][A-Za-z0-9._+-]*)\.([A-Za-z0-9]{1,8})#\1[arquivo:.\3]#g' \
    -e 's#([^A-Za-z0-9._~+/:-]|^)((\.{1,2}|~)?/[A-Za-z0-9._~+-]*)+/([A-Za-z0-9._+-]*[A-Za-z][A-Za-z0-9._+-]*)\.([A-Za-z0-9]{1,8})#\1[arquivo:.\5]#g' \
    -e 's#([^A-Za-z0-9._~+/:-]|^)((\.{1,2}|~)?/[A-Za-z0-9._~+-]*[A-Za-z][A-Za-z0-9._~+-]*)+/([A-Za-z0-9._+-]*[A-Za-z][A-Za-z0-9._+-]*)#\1[REDACTED-PATH]#g' \
    -e 's#([[:space:]"'"'"'(=]|^)([A-Za-z0-9._+-]+/)+([A-Za-z0-9._+-]*[A-Za-z][A-Za-z0-9._+-]*)\.([A-Za-z0-9]{1,8})#\1[arquivo:.\4]#g' \
    2>/dev/null || return 1
  return 0
}

# Campo redigido com fail-closed: string redigida OU vazio se a redacao falhar.
_safe_field() {
  local _val="$1" _out
  _out="$(printf '%s' "$_val" | _redact)" || { printf ''; return 0; }
  printf '%s' "$_out"
}
