# As 6 regras anti-perda-em-construcao-grande

> Projeto grande e onde o trabalho se perde: a sessao acaba, o contexto some, o que
> foi "quase feito" volta do zero, e ninguem sabe mais qual era o objetivo. Estas 6
> regras existem pra que **nada do que voce construiu evapore entre um passo e o
> proximo**. Sao texto estatico, deliberadamente curtas: leia antes de comecar uma
> construcao grande e mantenha a vista enquanto trabalha.

---

## 1. Um objetivo imutavel, sempre visivel

Escreva o objetivo em UMA frase no comeco e **nao o reescreva**. Todo passo serve a
esse objetivo ou nao acontece. Quando um exemplo concreto (uma tela, um bug, uma
ideia bonita) tentar virar "o objetivo", volte pra frase original — o exemplo e
instancia, nao a meta. Se o objetivo mudar de verdade, isso e uma decisao explicita,
nunca uma deriva silenciosa.

## 2. O caminho e o estado sempre a vista

Mantenha um mapa vivo do projeto: a lista de passos com `[x]` feito / `[ ]` pendente,
e qual e o passo atual. Esse mapa e a fonte unica de "onde estamos" — nao a sua
memoria, nao o scroll do chat. Quem chega no projeto (voce amanha, ou outra sessao)
 le o mapa e sabe exatamente o proximo movimento, sem re-explicacao.

## 3. Spec antes de codar

Antes de escrever a primeira linha de codigo, escreva o contrato: o que cada peca
deve fazer, como se prova que esta pronta, o que fica de fora. Um projeto grande sem
spec vira retrabalho — a suposicao nao-examinada e onde mais tempo se perde. A spec
pode ser curta (algumas frases num projeto simples), mas tem que existir e ser
aprovada antes da construcao.

## 4. Provar cada passo por fato

Um passo so esta pronto quando ha **evidencia externa reproduzivel**: a saida de um
teste que rodou, o resultado de um comando, a tela abrindo. "Passou no meu teste
mental" e "acho que funciona" nao contam. Cole a saida literal. Idealmente quem
verifica nao e quem construiu — o construtor tem vies de que funcionou.

## 5. Nao construir conteudo antes do esqueleto viver

Faca o esqueleto do projeto FUNCIONAR primeiro (o minimo instalavel/executavel que
prova vida), e so depois preencha o conteudo. Construir muito conteudo sobre uma base
que ainda nao roda e o jeito mais rapido de acumular trabalho que vai ser jogado fora
quando o esqueleto mudar. Vida do esqueleto primeiro, riqueza depois.

## 6. Checkpoint / handoff a cada troca de sessao

Toda vez que a sessao vai acabar (ou o contexto esta enchendo), salve um **bilhete de
handoff** curto e completo: objetivo, mapa `[x]`/`[ ]`, fatos ja verificados, proximo
passo concreto, e o que ja foi disparado pra nao repetir. A proxima sessao le esse
bilhete e continua no mesmo lugar — sem tomar o controle da maquina, sem voce ter que
re-explicar nada. Um passo `[x]` so entra no bilhete se tiver prova no disco (regra 4).

---

> **O fio comum:** nenhuma etapa fecha por criterio interno de quem construiu — so por
> evidencia externa. E todo aprendizado persiste em um lugar (o mapa + o handoff) que a
> proxima sessao ENCONTRA sozinha. Perde-se trabalho quando uma dessas duas coisas falha.
