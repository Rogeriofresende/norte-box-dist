# O que mudou pra você

Este é o changelog em português de padaria da norte-box — o que MUDOU PRA VOCÊ em
cada versão, em uma ou duas frases, sem jargão. Não é changelog técnico nem git log:
aqui a gente fala do que você sente, não do que a gente mexeu por baixo.

Formato (não mude, o motor lê por ele): cada versão é um cabeçalho `## X.Y.Z` seguido de
bullets `-`. O motor mostra SÓ as versões novas pra você (as que saíram desde a última
vez que você abriu a caixa), uma vez. Depois disso, fica quieto.

## 0.3.23
- A caixa começou a montar o "filme" do seu uso: a sequência dos seus passos numa sessão + onde deu erro, travou ou demorou. É pra o dono da caixa enxergar a SAÚDE do uso e te ajudar melhor — sem NUNCA ler o seu trabalho. Continua igual à promessa: sobe só um código embaralhado da sessão, um contador e o "deu certo/erro"; o que você digita, a resposta da IA, nomes de arquivo e a mensagem de erro NÃO saem da sua máquina.

## 0.3.22
- A Vitrine (as páginas que você folheia) agora tem uma CAPA: uma lista de tudo que você já gerou, a mais recente primeiro. E cada página ganhou um "← voltar ao índice" no topo, pra você navegar sem se perder num beco sem saída.
- A caixa te avisa quando um arquivo que você citou num bilhete MUDOU desde então — pra você não agir confiando num retrato velho.
- Um "já tentei isso?": a caixa lembra o que você já tentou antes, pra não te deixar repetir um caminho que não deu certo.
- Um "vale-manter": de vez em quando ela te mostra, em silêncio, o que anda sem uso — pra você decidir o que guardar e o que largar. Não apaga nada; só mostra.
- No Windows, a Vitrine agora abre sozinha no navegador (antes às vezes não abria).

## 0.3.19
- Agora o seu time é DE VERDADE: a Ada (construir/subir), a Val (revisar e tentar quebrar) e o Max (juntar tudo) vieram embarcados na caixa — antes eram só nomes, agora respondem.
- Comando novo `/norte-box:time-ordem "sua ordem"`: você dá UMA ordem e o time debate em paralelo, a Val tenta quebrar, e o Max te devolve UMA decisão recomendada (com o risco dela e o que precisa de você). A discordância é obrigatória — se todos concordam, ele te avisa que não valeu chamar o time.
- Detalhe honesto: chamar o time roda 3 agentes de uma vez, então gasta ~3x. Use quando a escolha tem dois lados; pra tarefa simples de uma pessoa só, chame um agente e pronto.

## 0.3.18
- Parei de te interromper quando você só FAZ UMA PERGUNTA: "quanto custou o deploy?", "vale a pena mandar a newsletter?", "será que publico hoje?", "o serviço está no ar?" — se a frase termina com "?", eu fico quieto. Perguntar não é mandar fazer, então não te atrapalho à toa.
- E fechei uns furos: pedido perigoso com uma palavra no meio ("põe ISSO online", "deixa ISSO online", "move O arquivo pra lá") agora eu paro pra confirmar também — antes esse jeitinho de escrever passava batido.
- Detalhe honesto: se você escrever um risco COMO pergunta ("apaga o banco?"), eu vou ficar quieto (trato como pergunta). É raro — ordem de verdade vem sem "?" — e é o preço de eu não te encher quando você só quer perguntar.

## 0.3.17
- Ficou mais difícil eu deixar passar um pedido perigoso escrito "de outro jeito": além de "publica"/"apaga", agora eu também paro pra confirmar em "sobe pro ar", "faz o deploy", "dispara a newsletter", "limpa a pasta", "zera o banco", "revoga os convites", "formata", "derruba o serviço" e afins.
- E continuei quieto no que é só pergunta: "quantos leads", "manda ver os números", "consulta o saldo" e afins seguem sem interromper você — nada de falar à toa.

## 0.3.16
- Agora isso funciona sozinho, e do jeito certo: quando você me pede algo que MEXE no mundo (publicar, apagar, alterar arquivo), eu paro e te peço pra confirmar antes — mas quando é só uma pergunta, um "oi" ou um "depois a gente vê", eu fico QUIETO e não te interrompo à toa. Só falo quando é risco de verdade.

## 0.3.15
- Quando você me pede uma coisa, eu NUNCA cravo por conta própria: eu te devolvo um palpite ("me parece que você quer X"), duas ou três opções, e paro pra você confirmar — nada anda sozinho no meu chute.

## 0.3.12
- Quando eu me atualizo, agora eu me CONFIRO sozinho antes de você usar — e só te aviso se a versão nova parecer com problema ("não confie nesta versão, avise a Norte"). Se estiver tudo certo, fico quieto.
- Você também pode conferir na hora que quiser com o comando `nb-atualizar` — ele te diz "pode confiar" ou "tem problema: X".

## 0.3.11
- Agora, quando a caixa muda de versão, ela te AVISA em português o que ficou diferente pra você — em vez de mudar por baixo, calada.
- É só um recado curto na abertura, uma vez. Sem novidade, sem recado.

## 0.3.10
- Quando eu travo de vez no meio de um trabalho, eu monto sozinho um bilhete de socorro aqui na sua máquina com o que a Norte precisa pra te ajudar rápido — e nada sai daqui sozinho: você decide se manda.

## 0.3.9
- Quando eu travo por falta de uma informação, agora eu te PERGUNTO em vez de chutar — paro e espero você me dizer, no seu tempo.

## 0.3.8
- Se o bilhete de onde a gente parou já ficou velho, eu te aviso na hora de retomar — pra você não seguir em cima de coisa desatualizada.

## 0.3.7
- Cada bilhete de "onde paramos" agora vem com um selo honesto de provado ou não — pra você saber na hora se aquilo já foi conferido de verdade.
