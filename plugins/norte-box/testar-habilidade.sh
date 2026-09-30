#!/usr/bin/env bash
# testar-habilidade.sh — prova do campo "habilidade" do medidor (0.3.42). Roda numa copia isolada
# (HOME temporario, sem envio). Sai 0 so se os 11 casos passarem e nenhum texto vazar.
set -u
RAIZ="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; cp -R "$RAIZ" "$T/plugin"
printf '_norte_pode_enviar(){ return 0; }\n' > "$T/plugin/hooks/_modo.sh"
mkdir -p "$T/home/.norte-box"; touch "$T/home/.norte-box/telemetry.enabled"
Q="$T/home/.norte-box/telemetry-queue.jsonl"; FALHAS=0
caso() { : > "$Q"; printf '%s' "$2" | env -u NORTE_BOX_TELEMETRY_URL HOME="$T/home" CLAUDE_PLUGIN_ROOT="$T/plugin" ${4:-} bash "$T/plugin/hooks/telemetry-emit.sh"
  got="$(jq -r '.habilidade // "-"' "$Q" 2>/dev/null | tail -1)"; vaz="$(grep -c 'SEGREDO' "$Q")"
  if [ "$got" = "$3" ] && [ "$vaz" = "0" ]; then echo "ok   $1"; else echo "FALHA $1 (veio=$got vazou=$vaz)"; FALHAS=$((FALHAS+1)); fi; }
caso "Skill continuar"      '{"session_id":"s","tool_name":"Skill","tool_input":{"skill":"continuar","args":"SEGREDO"},"tool_response":"ok"}' continuar
caso "Skill norte:conselho" '{"session_id":"s","tool_name":"Skill","tool_input":{"skill":"norte:conselho"},"tool_response":"ok"}' conselho
caso "/continuar + texto"   '{"session_id":"s","prompt":"/continuar SEGREDO"}' continuar
caso "/▲-continuar"         '{"session_id":"s","prompt":"/▲-continuar"}' continuar
caso "/norte:provar"        '{"session_id":"s","prompt":"/norte:provar SEGREDO"}' provar
caso "/comando-do-cliente"  '{"session_id":"s","prompt":"/acme-cliente SEGREDO"}' -
caso "texto comum"          '{"session_id":"s","prompt":"use /continuar SEGREDO"}' -
caso "outro plugin"         '{"session_id":"s","tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"},"tool_response":"ok"}' -
caso "caminho malicioso"    '{"session_id":"s","tool_name":"Skill","tool_input":{"skill":"../../skills/continuar"},"tool_response":"ok"}' -
caso "desligado"            '{"session_id":"s","prompt":"/continuar"}' - NORTE_BOX_TELEMETRY_HAB=0
caso "ferramenta comum"     '{"session_id":"s","tool_name":"Read","tool_input":{"file_path":"/x"},"tool_response":"SEGREDO"}' -
[ "$FALHAS" = 0 ] && echo "TODOS OS 11 PASSARAM" || echo "$FALHAS FALHARAM"
exit "$FALHAS"
