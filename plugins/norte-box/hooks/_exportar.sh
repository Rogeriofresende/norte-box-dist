#!/usr/bin/env bash
# _exportar.sh — o PACOTE EXPORTAVEL do Norte-box (NRT-_990341, empilhado na estreia).
#
# A ideia (padaria): a estreia ja rodou a tarefa ponta a ponta e GRAVOU um REGISTRO DE ENTREGA SELADO
# (entrega-*.txt, com o carimbo 🟢 ENTREGA PROVADA + resumo + hashes + a ressalva "cobertura literal").
# Este passo NAO reconfere NADA. Ele so APONTA pra UM registro ja selado e monta uma PASTA pronta pra o
# cliente — pacote-cliente-<id>/ — com 4 partes: o ARTEFATO (a saida da conferencia), a PROVA/ (o selo
# verbatim, sanitizado), o LEIA-ME (capa curta) e o RISCOS (derivado das ressalvas do proprio selo).
#
# O GUARDA (o principal, do juiz): so vira pacote VERDE (com o carimbo 🟢) uma entrega REALMENTE PROVADA.
# "Provada de verdade" = o registro carimba 🟢 ENTREGA PROVADA **E** a EVIDENCIA no mesmo arquivo NAO
# contradiz o carimbo (motor_exit:0, resumo com orfaos=0 suspeitas=0 aluc=0, e o corpo sem ORFAO/ALUC).
# Se o carimbo esta 🟡, ou o carimbo foi VIRADO pra 🟢 na mao mas a evidencia reprova (adulterado), o
# exportador RECUSA (exit !=0) e NAO deixa um pacote com cara de provado. Fail-honest: na duvida, recusa.
#
# LIMPEZA (cliente-facing): NADA de caminho interno/local, PII, segredo, log cru, prompt interno, nem o
# DOCUMENTO ORIGINAL (so o hash). O registro cru CARREGA um caminho interno ("prova: /var/folders/...");
# a saida e SANITIZADA antes de entrar no pacote.
#
# LEIS (iguais aos outros passos):
#   - PRIVADO POR PADRAO: le so o disco local; NAO usa rede.
#   - KILL-SWITCH: NORTE_EXPORTAR=0 desliga (recusa, exit 2).
#   - Portabilidade macOS (bash 3.2). Nao usa dado como comando (set -u; sem eval).
#   - NAO reconfere: NAO chama o motor contrato-doc nem a estreia. So LE o selo ja gravado.
#   - PONTA B (NRT-_990380): ANTES de empacotar como PROVADO, VERIFICA a assinatura HMAC do registro
#     (_norte_estreia_verificar). Isto NAO e reconferir a conferencia — e checar que o registro nao foi
#     forjado/editado a mao. 🔴 (adulterado) -> RECUSA fail-closed; 🟡 (sem assinatura/antigo) -> NAO sela
#     como provado (rebaixa/alerta); 🟢 -> segue. E o que mata a forja-a-mao de um registro coerente.
set -u

# a verificacao HMAC mora no _estreia.sh (assinar e verificar sao a mesma familia). O exportador carrega
# essa lib pra poder VERIFICAR (nao pra reconferir): so chama _norte_estreia_verificar. Fail-honest: se a
# lib nao estiver disponivel, a verificacao degrada pra "nao-verificavel" (🟡) no ponto de uso.
if ! command -v _norte_estreia_verificar >/dev/null 2>&1; then
  _norte_exportar_self="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "${_norte_exportar_self:-}" ] && [ -f "${_norte_exportar_self}/_estreia.sh" ]; then
    # shellcheck source=/dev/null
    . "${_norte_exportar_self}/_estreia.sh" 2>/dev/null || true
  fi
  unset _norte_exportar_self 2>/dev/null || true
fi

# _norte_exportar_sanitiza — filtro de linha (stdin->stdout) que TIRA o que nao pode ir pro cliente:
#   - a linha "prova: <caminho>" inteira (caminho interno do disco) -> colapsa pra marcador generico;
#   - qualquer caminho absoluto do sistema (/Users, /var/folders, /private, /tmp, /root, /home) -> [caminho local];
#   - a raiz privada .norte-box/... -> [arquivo local do Norte-box].
# Nunca imprime o corpo de um caminho — troca por um rotulo neutro. Idempotente.
# NOTA (limite honesto): esta funcao so limpa CAMINHO. Ela NAO limpa PII/segredo/IP — isso e trabalho do
# GUARDA anti-vazamento (_norte_exportar_gate abaixo, que roda o secret_pii.sh fail-closed sobre a pasta
# final). O par e: sanitiza-caminho aqui + gate anti-PII/segredo/IP na saida = nada sensivel sai.
_norte_exportar_sanitiza() {
  sed \
    -e 's#^prova:.*#prova: (arquivo local na maquina onde a entrega foi conferida — nao incluido no pacote)#' \
    -e 's#/Users/[^[:space:]"]*#[caminho local]#g' \
    -e 's#/var/folders/[^[:space:]"]*#[caminho local]#g' \
    -e 's#/private/[^[:space:]"]*#[caminho local]#g' \
    -e 's#/tmp/[^[:space:]"]*#[caminho local]#g' \
    -e 's#/root/[^[:space:]"]*#[caminho local]#g' \
    -e 's#/home/[^[:space:]"]*#[caminho local]#g' \
    -e 's#[^[:space:]"]*\.norte-box/[^[:space:]"]*#[arquivo local do Norte-box]#g'
}

# _norte_exportar_sensivel <texto> — ecoa "1" se o TEXTO carrega dado que NUNCA pode ir pro cliente:
#   PII formatada (CPF/CNPJ), e-mail, segredo (sk-/ghp_/github_pat_/AKIA/aact_/xox.-/AIza/PRIVATE KEY) e
#   path/host/IP interno da Norte (os dois IPs Hetzner/Oracle, o host Tailscale da Vela e as raizes de agentes).
#   Este e o detector AUTO-CONTIDO do exportador: ele funciona MESMO num cliente onde o gate oficial
#   secret_pii.sh nao foi instalado (o plugin instalado leva so plugins/norte-box/, NAO leva build/gates/).
#   E o unico ponto que ve o ROTULO (que vira nome de pasta/stdout e o gate nunca escaneia) e o e-mail cru.
# Os prefixos de SECRET sao construidos por PEDACOS (variaveis _p*) pra este ARQUIVO-FONTE nao carregar um
# literal de secret (sk-/ghp_/AKIA) que a portaria do repo (secret_pii.sh) marcaria. Ja o IP/host interno
# NAO e mais embutido: virou padrao generico (qualquer IPv4 / *.ts.net / caminho de servidor), sem literal.
# 100% local, sem rede. grep -qE. Retorna "0" se limpo.
_norte_exportar_sensivel() {
  local _t="${1:-}"
  local _d='[0-9]' _p1='sk' _p2='ghp' _p3='AKIA'
  # Infra de servidor NUNCA vai pro cliente. Em vez de EMBUTIR os IPs/hosts internos da Norte (o que faria
  # ESTE arquivo publico carregar o literal — o furo que o Val red-team achou, NRT-_990380), o detector barra
  # a FORMA generica: qualquer IPv4, qualquer host Tailscale (*.ts.net) e qualquer caminho de servidor
  # (/root/... , /home/...). Cobre os IPs internos SEM guardar o valor deles no arquivo-fonte.
  local _anyip='([0-9]{1,3}\.){3}[0-9]{1,3}' _anyts='[A-Za-z0-9_-]+\.ts\.net' _anyroot='/(root|home)/[A-Za-z0-9_./-]+'
  printf '%s' "$_t" | grep -qE \
    "${_p1}-[A-Za-z0-9_-]{6,}|${_p2}_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|${_p3}[A-Z0-9]{16}|aact_[A-Za-z0-9_-]{10,}|xox[bporas]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY|${_d}{3}\.${_d}{3}\.${_d}{3}-${_d}{2}|${_d}{2}\.${_d}{3}\.${_d}{3}/${_d}{4}-${_d}{2}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|${_anyip}|${_anyts}|${_anyroot}" \
    && { printf '1'; return 0; }
  printf '0'
}

# _norte_exportar_pasta_suja <pasta> — ecoa "1" se QUALQUER arquivo da pasta carrega dado sensivel pelo
# detector PROPRIO do exportador (_norte_exportar_sensivel: PII/segredo + E-MAIL). Cobre o buraco que o gate
# oficial NAO cobre: o gate secret_pii.sh nao pega e-mail cru (pra nao dar falso-positivo nos arquivos de
# teste versionados do repo); aqui, cliente-facing, e-mail e PII e NAO pode sair. (Path/host/IP interno ja
# e pego pelo gate oficial na camada 1.) 100% local.
_norte_exportar_pasta_suja() {
  local _dir="${1:-}"
  [ -n "$_dir" ] && [ -d "$_dir" ] || { printf '0'; return 0; }
  local _f
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    if [ "$(_norte_exportar_sensivel "$(cat "$_f" 2>/dev/null)")" = "1" ]; then
      printf '1'; return 0
    fi
  done < <(find "$_dir" -type f 2>/dev/null)
  printf '0'
}

# _norte_exportar_gate <pasta> — o GUARDA anti-vazamento cliente-facing, em DUAS camadas fail-closed:
#   camada 1 (SEMPRE roda, AUTO-CONTIDA): o detector PROPRIO do exportador (_norte_exportar_pasta_suja) —
#     PII/segredo/e-mail/IP-host interno. Funciona MESMO no cliente, onde o gate oficial nao foi instalado
#     (o plugin instalado leva so plugins/norte-box/, NAO leva build/gates/). Esta e a garantia de base.
#   camada 2 (REFORCO, so se PRESENTE): o gate OFICIAL secret_pii.sh sobre a PASTA, forcando FS-scan (a
#     pasta e UNTRACKED — no modo git ls-files o gate daria verde-que-mente). No repo/dev ele existe e
#     reforca; num cliente sem build/gates/ ele simplesmente nao roda (a camada 1 ja garante o minimo).
# Retorna 0 se LIMPO, 1 se ACUSOU em qualquer camada. NUNCA retorna "nao sei" fail-open: a camada 1 sempre
# tem veredito, entao a ausencia do gate oficial NAO afrouxa a barra (era o risco de fail-open de antes).
_norte_exportar_gate() {
  local _dir="${1:-}"
  [ -n "$_dir" ] && [ -d "$_dir" ] || return 1   # sem pasta valida -> trata como sujo (fail-closed)
  # camada 1: detector proprio, AUTO-CONTIDO (sempre roda). Se sujo -> barra na hora.
  [ "$(_norte_exportar_pasta_suja "$_dir")" = "1" ] && return 1
  # camada 2: gate oficial, se instalado (reforco). Acha ao lado da instalacao (repo: hooks -> ../../../build/gates).
  local _self _gate=""
  _self="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  for _c in \
    "${_self}/../../../build/gates/secret_pii.sh" \
    "${_self}/../../build/gates/secret_pii.sh" \
    "${CLAUDE_PLUGIN_ROOT:-}/build/gates/secret_pii.sh" \
    "${CLAUDE_PLUGIN_ROOT:-}/../../build/gates/secret_pii.sh"; do
    [ -n "$_c" ] && [ -f "$_c" ] && { _gate="$_c"; break; }
  done
  if [ -n "$_gate" ]; then
    NORTE_GATE_FS_SCAN=1 bash "$_gate" "$_dir" >/dev/null 2>&1 || return 1
  fi
  return 0
}

# _norte_exportar_campo <registro> <chave> — ecoa o valor da 1a linha "chave: valor" do registro. Cru.
_norte_exportar_campo() {
  grep -m1 "^${2}: " "$1" 2>/dev/null | sed "s/^${2}: //"
}

# _norte_exportar_resumo_campo <resumo> <chave> — ecoa o VALOR NUMERICO do campo "chave=<n>" do resumo,
# por PARSE ESTRUTURADO (token a token), nunca substring. Assim "orfaos=0 ... (na verdade orfaos=3)" le o
# PRIMEIRO campo real (0), sem tropecar no ruido; e "orfaos=3" nao e mascarado por um "orfaos=0" adjacente.
# Ecoa vazio se o campo nao existe. bash 3.2 (for sobre tokens separados por espaco).
_norte_exportar_resumo_campo() {
  local _resumo="${1:-}" _chave="${2:-}" _tok
  for _tok in $_resumo; do
    case "$_tok" in
      "${_chave}="*) printf '%s' "${_tok#${_chave}=}"; return 0 ;;
    esac
  done
  return 0
}

# _norte_exportar_provado <registro> — 0 (PROVADO de verdade) SO se TODAS valem; 1 caso contrario.
#   (a) o carimbo (campo lido por LINHA UNICA, grep -m1) comeca por "🟢 ENTREGA PROVADA" — um 🟢 plantado
#       em OUTRA linha do arquivo NAO abre o verde;
#   (b) motor_exit: 0 (o motor fechou);
#   (c) resumo com orfaos=0 E suspeitas=0 E aluc=0 por PARSE ESTRUTURADO (campo=valor, nao substring):
#       "orfaos=0 ...(orfaos=3)" nao mascara nada; cada campo tem que valer EXATAMENTE 0;
#   (d) o CORPO (bloco da conferencia) NAO contem linha ORFAO/SUSPEIT/ALUC — CASE-INSENSITIVE (um "orfao"
#       minusculo plantado no corpo tambem derruba o carimbo forjado).
# Assim um carimbo 🟢 VIRADO na mao sobre um registro amarelo (motor_exit:1 / resumo com orfao / corpo
# com ORFAO) NAO passa: a evidencia derruba o carimbo forjado. Fail-honest: na duvida (campo faltando) -> 1.
_norte_exportar_provado() {
  local _reg="${1:-}"
  [ -n "$_reg" ] && [ -f "$_reg" ] || return 1
  # (a) carimbo verde — o campo e lido por LINHA UNICA (grep -m1 "^carimbo: "); 🟢 em outra linha nao conta.
  local _carimbo; _carimbo="$(_norte_exportar_campo "$_reg" carimbo)"
  case "$_carimbo" in
    '🟢 ENTREGA PROVADA'*) : ;;
    *) return 1 ;;
  esac
  # (b) motor_exit == 0
  local _mexit; _mexit="$(_norte_exportar_campo "$_reg" motor_exit)"
  [ "$_mexit" = "0" ] || return 1
  # (c) resumo: cada campo (orfaos/suspeitas/aluc) tem que ser EXATAMENTE 0 (parse estruturado, nao substring)
  local _resumo; _resumo="$(_norte_exportar_campo "$_reg" resumo)"
  [ -n "$_resumo" ] || return 1
  [ "$(_norte_exportar_resumo_campo "$_resumo" orfaos)"    = "0" ] || return 1
  [ "$(_norte_exportar_resumo_campo "$_resumo" suspeitas)" = "0" ] || return 1
  [ "$(_norte_exportar_resumo_campo "$_resumo" aluc)"      = "0" ] || return 1
  # (d) o corpo (bloco da conferencia) nao pode ter linha de reprova — CASE-INSENSITIVE (-i).
  if grep -qiE '^[[:space:]]*(ORFAO|SUSPEIT|ALUC)' "$_reg" 2>/dev/null; then
    return 1
  fi
  return 0
}

# _norte_exportar_pacote <registro> [destino]
#   Monta o pacote a partir de UM registro de entrega selado. RETORNO:
#     0 -> pacote VERDE gerado (entrega provada de verdade)
#     2 -> NAO gerou (kill-switch / registro ausente/vazio / entrega NAO-PROVADA ou adulterada)
#   O modo desta fatia e RECUSA (fail-honest): entrega nao-provada NAO vira pacote. (O modo "marcar
#   ⚠️ NAO-PROVADO na capa" e uma alternativa aceita pelo guarda; aqui escolhemos RECUSAR — mais seguro.)
_norte_exportar_pacote() {
  local _reg="${1:-}" _dest="${2:-.}"

  # kill-switch
  case "${NORTE_EXPORTAR:-1}" in
    0|no|nao|off|false)
      printf '🟡 o pacote exportavel nao esta ligado nesta maquina (NORTE_EXPORTAR=0).\n'
      return 2 ;;
  esac

  # pre-condicoes (fail-honest)
  if [ -z "$_reg" ] || [ ! -f "$_reg" ]; then
    printf '🟡 nao consegui exportar: o registro de entrega indicado nao existe.\n'
    return 2
  fi
  if [ ! -s "$_reg" ]; then
    printf '🟡 nao consegui exportar: o registro de entrega esta vazio.\n'
    return 2
  fi
  # tem que ser um registro de entrega (o cabecalho da estreia) — nao qualquer arquivo.
  if ! grep -q '^REGISTRO DE ENTREGA' "$_reg" 2>/dev/null; then
    printf '🟡 nao consegui exportar: esse arquivo nao parece um registro de entrega do norte-box.\n'
    return 2
  fi

  # O GUARDA (o principal): so segue se a entrega for PROVADA DE VERDADE (carimbo 🟢 E evidencia coerente).
  if ! _norte_exportar_provado "$_reg"; then
    printf '🛑 NAO EXPORTEI: essa entrega NAO esta provada (ou o carimbo nao bate com a evidencia do proprio registro).\n'
    printf '   um pacote pra cliente so sai de uma entrega 🟢 ENTREGA PROVADA de verdade — nunca com cara de provado sem ser.\n'
    printf '   rode a estreia ate ela fechar 🟢 e aponte o registro selado que ela gravar.\n'
    return 2
  fi

  # ---- O GUARDA DA PONTA B: a ASSINATURA HMAC (NRT-_990380) ----
  # O guarda de coerencia acima le o CONTEUDO do registro; mas um registro 100% reescrito a mao (carimbo 🟢,
  # motor_exit:0, resumo zerado, corpo limpo) e coerente e PASSARIA. A assinatura HMAC fecha isso: so quem tem
  # a chave LOCAL produz um assinatura_hmac valido. Verificamos ANTES de empacotar como provado:
  #   🔴 (adulterado/forjado com assinatura que nao bate) -> RECUSA fail-closed. E ISTO que mata a forja.
  #   🟡 (sem assinatura / registro antigo / sem chave-openssl) -> NAO sela como provado: REBAIXA pra
  #      "nao-verificavel" e estampa alerta (juiz: nao matar registro antigo de fome, mas nao carimbar verde
  #      no que nao da pra verificar). Fail-honest.
  #   🟢 (confere) -> segue normal.
  local _hmac_veredito _hmac_rc _selo_verificavel=1
  _hmac_veredito="$(_norte_estreia_verificar "$_reg" 2>/dev/null)"; _hmac_rc=$?
  if [ "$_hmac_rc" -eq 1 ]; then
    printf '🛑 NAO EXPORTEI: a assinatura do registro NAO confere (registro editado ou forjado).\n'
    printf '   o corpo do registro nao bate com a assinatura HMAC gravada — alguem editou/forjou o registro a mao.\n'
    printf '   rode a estreia de novo e aponte o registro selado ORIGINAL que ela gravar.\n'
    return 2
  fi
  if [ "$_hmac_rc" -ne 0 ]; then
    # 🟡 nao-verificavel (sem assinatura / antigo / sem chave). Nao recusa (nao mata de fome), mas NAO sela
    # como provado: o pacote sai REBAIXADO pra "nao-verificavel", sem o carimbo 🟢 e com alerta claro.
    _selo_verificavel=0
  fi

  # id do pacote a partir do rotulo + timestamp. O rotulo vira NOME DE PASTA (e ecoa no stdout) — o gate
  # secret_pii NAO ve o nome da pasta, entao a limpeza do rotulo e por conta PROPRIA aqui, em DOIS passos:
  #   1) sanitiza pra caractere seguro de nome ([A-Za-z0-9._-], resto vira '_'), cortado em 40;
  #   2) passa o rotulo CRU pelo detector de sensivel — se o rotulo E/CONTEM um segredo/PII/e-mail (ex:
  #      um rotulo que E uma chave de API, ou um e-mail de contato), a sanitizacao por si so NAO basta (uma
  #      chave "sk-..." so tem caractere valido e passaria intacta). Nesse caso, DESCARTA o rotulo e usa um
  #      id generico ("entrega") — o dado sensivel NUNCA vira nome de pasta nem stdout.
  local _rot _rotcru _ts _id _dir
  _rotcru="$(_norte_exportar_campo "$_reg" rotulo)"; [ -n "$_rotcru" ] || _rotcru="entrega"
  if [ "$(_norte_exportar_sensivel "$_rotcru")" = "1" ]; then
    _rot="entrega"   # rotulo carrega dado sensivel -> nao usa como nome de pasta
  else
    _rot="$(printf '%s' "$_rotcru" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-40)"
    [ -n "$_rot" ] || _rot="entrega"
  fi
  _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo t)"
  _id="${_rot}-${_ts}"
  _dir="${_dest%/}/pacote-cliente-${_id}"
  mkdir -p "$_dir/prova" 2>/dev/null || {
    printf '🟡 nao consegui exportar: nao deu pra criar a pasta do pacote (disco nao gravavel).\n'
    return 2
  }

  # valores do selo (ja provado). Sanitizados quando usados no texto do cliente.
  local _resumo _dochash _chkhash _carimbo _quando
  _resumo="$(_norte_exportar_campo "$_reg" resumo)"
  _dochash="$(_norte_exportar_campo "$_reg" doc_hash)"
  _chkhash="$(_norte_exportar_campo "$_reg" checklist_hash)"
  _carimbo="$(_norte_exportar_campo "$_reg" carimbo)"
  _quando="$(_norte_exportar_campo "$_reg" quando)"

  # PONTA B (rebaixa): se a assinatura NAO pode ser verificada (🟡: sem assinatura / registro antigo / sem
  # chave), o pacote NAO pode carimbar 🟢 ENTREGA PROVADA. Rebaixa o carimbo pra "nao-verificavel" e prepara
  # o alerta. (No caso 🔴 ja retornamos acima; aqui so cai 🟢 ou 🟡.)
  if [ "$_selo_verificavel" -eq 0 ]; then
    _carimbo='⚠️ NAO-VERIFICAVEL — a assinatura do registro esta ausente; nao da pra confirmar que o registro nao foi editado'
  fi

  # --- parte 1/4: ARTEFATO (a saida final da conferencia — copia, NAO regenera). E o que a entrega produziu.
  #     O corpo do registro (depois do cabecalho) carrega a conferencia ITEM A ITEM que o motor imprimiu
  #     ("✅ conferi assim...", "OK <item>", "ORFAO/SUSPEIT/ALUC <item>", "RESUMO: ..."). Extrai esse bloco
  #     por CONTEUDO (nao depende de um marcador fragil): tudo a partir da 1a linha "✅ conferi" OU
  #     "---- conferencia" (se o marcador existir) ate o fim; sanitiza. Sem esse fix o artefato saia OCO
  #     (so o resumo, sem os itens) — item 6 do Val.
  {
    printf 'ARTEFATO DA ENTREGA — conferencia item a item (norte-box)\n'
    printf 'resumo: %s\n' "$_resumo"
    printf '%s\n' '----'
    awk '
      f { print; next }
      /^---- conferencia/ { f=1; next }        # marcador (quando presente): comeca DEPOIS dele
      /^✅ conferi/       { f=1; print; next }   # fallback robusto: o bloco do motor comeca aqui
    ' "$_reg" 2>/dev/null
  } | _norte_exportar_sanitiza > "$_dir/artefato-conferencia.txt" 2>/dev/null

  # --- parte 2/4: PROVA/ (o registro selado VERBATIM — o 🟢 + resumo + hashes + a ressalva) SANITIZADO.
  #     "verbatim" no que importa (carimbo/exit/hashes/resumo/conferencia); a UNICA edicao e a limpeza de
  #     caminho interno (a linha "prova: <caminho>"), que NUNCA pode ir pro cliente. O selo honesto inteiro.
  #     PONTA B (rebaixa): no caso 🟡 (nao-verificavel) a linha "carimbo: 🟢 ENTREGA PROVADA" e reescrita pra
  #     o marcador de nao-verificavel — o pacote inteiro NAO pode carregar cara de provado sem assinatura.
  if [ "$_selo_verificavel" -eq 0 ]; then
    _norte_exportar_sanitiza < "$_reg" \
      | sed 's/^carimbo:.*/carimbo: ⚠️ NAO-VERIFICAVEL (assinatura ausente — nao da pra confirmar que o registro nao foi editado)/' \
      > "$_dir/prova/registro-selado.txt" 2>/dev/null
  else
    _norte_exportar_sanitiza < "$_reg" > "$_dir/prova/registro-selado.txt" 2>/dev/null
  fi

  # --- parte 3/4: LEIA-ME (capa curta, estatica). Mostra o selo 🟢 e onde esta a prova.
  {
    printf '# Pacote de entrega — norte-box\n'
    printf '\n'
    printf '%s\n' "$_carimbo"
    printf '\n'
    if [ "$_selo_verificavel" -eq 0 ]; then
      printf '> ⚠️ **ATENCAO — ENTREGA NAO-VERIFICAVEL.** Este registro NAO tem assinatura HMAC (registro antigo\n'
      printf '> ou gerado com a assinatura desligada). NAO da pra confirmar que ele nao foi editado a mao.\n'
      printf '> Para uma entrega com selo verificavel, rode a estreia de novo (com a assinatura ligada).\n'
      printf '\n'
    fi
    printf 'Este pacote contem o resultado de uma tarefa que foi conferida pela norte-box e SELADA.\n'
    printf '\n'
    printf '## O que tem aqui\n'
    printf '%s\n' '- **artefato-conferencia.txt** — a conferencia item a item (o resultado da entrega).'
    printf '%s\n' '- **prova/registro-selado.txt** — o registro selado (o carimbo, o resumo e os hashes).'
    printf '%s\n' '- **RISCOS.md** — o que este selo garante e o que NAO garante (leia antes de usar).'
    printf '\n'
    printf '## Como abrir\n'
    printf 'Sao arquivos de texto simples. Abra em qualquer editor de texto.\n'
    printf '\n'
    printf '## A prova\n'
    printf 'A prova esta em **prova/registro-selado.txt**. Resumo da conferencia: %s.\n' "$_resumo"
    printf 'Assinaturas do conteudo conferido: documento %s, checklist %s.\n' "$_dochash" "$_chkhash"
  } > "$_dir/LEIA-ME.md" 2>/dev/null

  # --- parte 4/4: RISCOS (derivado das ressalvas do PROPRIO selo). Cobertura literal + nao atesta merito
  #     juridico + os itens orfaos como pendencias (aqui sao 0, entao diz "nenhuma pendencia").
  local _orfaos
  _orfaos="$(_norte_exportar_resumo_campo "$_resumo" orfaos)"; [ -n "$_orfaos" ] || _orfaos="0"
  {
    printf '# RISCOS e limites deste selo\n'
    printf '\n'
    if [ "$_selo_verificavel" -eq 0 ]; then
      printf '## ⚠️ Assinatura NAO-VERIFICAVEL\n'
      printf 'Este registro NAO carrega assinatura HMAC verificavel (registro antigo ou assinatura desligada).\n'
      printf 'Isso significa que NAO da pra confirmar que o registro nao foi editado depois de gerado.\n'
      printf 'Trate o resultado abaixo como nao-verificavel ate refazer a estreia com a assinatura ligada.\n'
      printf '\n'
    fi
    printf 'A norte-box confere COBERTURA LITERAL: ela verifica que as exigencias do checklist estao\n'
    printf 'ESCRITAS no texto do documento. **O selo NAO atesta merito juridico** — nao diz que o\n'
    printf 'documento esta juridicamente correto, so que os itens pedidos aparecem no texto.\n'
    printf '\n'
    printf '## O que este selo garante\n'
    printf '%s\n' '- Cada item do checklist tem uma ancora correspondente no texto (cobertura).'
    printf '%s\n' '- O checklist nao afirma a ausencia de algo que existe no texto (anti-contradicao).'
    printf '\n'
    printf '## O que este selo NAO garante\n'
    printf '%s\n' '- Correcao juridica / adequacao ao caso concreto (isso e trabalho de um advogado).'
    printf '%s\n' '- Que a ancora casada esteja no CONTEXTO certo (a conferencia e por palavra, nao por sentido).'
    printf '\n'
    printf '## Pendencias\n'
    if [ "$_orfaos" = "0" ]; then
      printf 'Nenhuma pendencia: a conferencia fechou com 0 item orfao.\n'
    else
      printf 'Ha %s item(ns) sem cobertura no texto — veja a prova/registro-selado.txt.\n' "$_orfaos"
    fi
  } > "$_dir/RISCOS.md" 2>/dev/null

  # ---- O GUARDA ANTI-VAZAMENTO (fail-closed, cliente-facing) ----
  # O selo pode estar 🟢 e a entrega provada, e MESMO ASSIM o pacote conter dado sensivel: a pessoa pode ter
  # escrito um CPF/e-mail/segredo/IP DENTRO da descricao de um item do checklist (uso NORMAL), e esse texto
  # flui verbatim pro registro selado -> pro pacote. Antes de declarar 🟢, rodamos o guarda anti-vazamento
  # (_norte_exportar_gate: detector auto-contido SEMPRE + gate oficial secret_pii se instalado) sobre a
  # PASTA MONTADA. Se ACUSA -> RECUSA fail-closed: APAGA a pasta (nao deixa cara de provada) e devolve
  # exit !=0 com mensagem clara. Redigir seria opcional; recusar e o minimo — e o mais seguro.
  if ! _norte_exportar_gate "$_dir"; then
    rm -rf "$_dir" 2>/dev/null
    printf '🛑 NAO EXPORTEI: o pacote conteria dado sensivel (PII, segredo, e-mail ou path/IP interno).\n'
    printf '   isso costuma vir de um dado escrito DENTRO do checklist/rotulo (ex: um CPF ou e-mail na descricao de um item).\n'
    printf '   nao deixei nenhum pacote no disco. limpe a fonte (tire o dado sensivel do checklist/rotulo) e refaca a estreia.\n'
    return 2
  fi

  if [ "$_selo_verificavel" -eq 0 ]; then
    printf '⚠️ pacote gerado, mas REBAIXADO pra NAO-VERIFICAVEL — o registro nao tem assinatura HMAC (antigo/desligado).\n'
    printf '   empacotei so o que pode sair, mas SEM carimbar 🟢 provado. Refaca a estreia (assinatura ligada) pra um selo verificavel.\n'
    printf '   %s\n' "$_resumo"
    printf 'NB_PACOTE=%s\n' "$_dir"
    return 0
  fi
  printf '🟢 pacote pronto pra cliente — a entrega estava PROVADA (assinatura confere) e empacotei so o que pode sair.\n'
  printf '   %s\n' "$_resumo"
  printf 'NB_PACOTE=%s\n' "$_dir"
  return 0
}
