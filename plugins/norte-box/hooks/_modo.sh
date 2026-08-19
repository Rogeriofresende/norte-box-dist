#!/usr/bin/env bash
# _modo.sh - FONTE UNICA da leitura do MODO do Norte-box (Fase 2 — DOIS MODOS).
# Sourceado pelos hooks (telemetry-emit/drain/stop, modo-selo) e pelo doctor.
#
# O Norte-box tem UM produto com um interruptor entre 2 modos:
#   - privado        -> a Norte NAO ve este trabalho. Estruturalmente incapaz de enviar
#                       telemetria: no privado o instalador NAO grava URL/token/identity, e
#                       este gate de modo e a 2a trava (fail-closed).
#   - compartilhavel -> a Norte melhora este trabalho (telemetria com aceite, ver TELEMETRIA.md).
#
# LEI (Val, nao-negociavel): FAIL-CLOSED. O modo mora em $HOME/.norte-box/modo (1 palavra).
#   Se o arquivo NAO existe, esta ilegivel, ou tem qualquer valor != "compartilhavel",
#   o modo e tratado como PRIVADO. So o valor EXATO "compartilhavel" abre o envio.
#   Assim um arquivo corrompido/apagado NUNCA vira compartilhavel por acidente.
#
# Portabilidade macOS (bash 3.2). Nao escreve nada (so LE). Nao imprime nada.

# _norte_modo — ecoa "privado" ou "compartilhavel". Fail-closed em privado.
_norte_modo() {
  local _f="${HOME}/.norte-box/modo" _v=""
  if [ -r "$_f" ]; then
    # 1a linha, TRIM so das PONTAS (nao remove espacos INTERNOS). Le como DADO (nunca executa).
    # Antes usava `tr -d ' \t\r\n'` (global) — isso colapsava "compart ilhavel" em
    # "compartilhavel" e ABRIA o envio por corrupcao interna. Trim de pontas faz corrupcao
    # interna cair no `*)` -> privado (fail-closed).
    _v="$(head -n1 "$_f" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  case "$_v" in
    compartilhavel) printf 'compartilhavel' ;;
    *)              printf 'privado' ;;   # ausente / ilegivel / qualquer-outra-coisa -> privado
  esac
}

# _norte_modo_compartilhavel — retorna 0 (sucesso) SO se o modo e compartilhavel. Senao 1.
# Uso nos hooks: `_norte_modo_compartilhavel || exit 0`  (privado = nao emite, fail-open pro trabalho).
_norte_modo_compartilhavel() {
  [ "$(_norte_modo)" = "compartilhavel" ]
}

# Versao vigente do termo (Modelo A: numeros por padrao). consent.md grava consent.json com
# .versao == esta string. Se o termo mudar de versao, mude AQUI (fonte unica): so o aceite da
# versao corrente libera o envio (do MEDIDOR — o conteudo nunca sobe automatico, ver telemetry-emit.sh).
NORTE_CONSENT_VERSION="${NORTE_CONSENT_VERSION:-5}"

# _norte_consent_aceito — retorna 0 SO se o consent foi aceito NA VERSAO VIGENTE do termo.
# Le $HOME/.norte-box/consent.json e exige .versao == "$NORTE_CONSENT_VERSION" (string).
# FAIL-CLOSED: sem jq, sem arquivo, JSON invalido, versao ausente/diferente -> 1 (nao aceitou).
# Motivo (furo MEDIO, Val): o gate de ENVIO nao pode confiar so em modo=compartilhavel no disco.
# Editar arquivos na mao (modo+URL+token+flag) SEM aceitar o termo NAO pode abrir o envio. Este
# 3o freio (junto de modo compartilhavel + flag telemetry.enabled) re-verifica o consent no gate.
_norte_consent_aceito() {
  local _f="${HOME}/.norte-box/consent.json"
  command -v jq >/dev/null 2>&1 || return 1
  [ -f "$_f" ] || return 1
  jq -e --arg v "$NORTE_CONSENT_VERSION" '.versao == $v' "$_f" >/dev/null 2>&1
}

# _norte_pode_enviar — a PRE-CONDICAO UNICA de envio (cinto+suspensorio numa fonte so).
# 0 SO se: modo=compartilhavel E consent aceito na versao vigente. Os hooks ainda checam a flag
# telemetry.enabled + presenca de URL/token por conta propria; esta funcao trava o VAZAMENTO de
# quem editou o disco na mao sem passar pelo aceite.
_norte_pode_enviar() {
  _norte_modo_compartilhavel || return 1
  _norte_consent_aceito || return 1
  return 0
}
