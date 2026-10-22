extends RefCounted
## The reference's own writing in Portuguese. Same blocks, chapter gates and
## links as prose/en.gd; see there for the format. The game has no Portuguese
## text, so names and the game's own menu labels stay as the game shows them.

const PAGES := {
	"home": {"title": "Referência"},
	"world/setting": {"title": "Uma galáxia em guerra"},
	"world/fleet": {"title": "A frota espacial terrana"},
	"world/outlaws": {"title": "Foras da lei e piratas"},
	"chapter/1": {"title": "Uma nave nova"},
	"chapter/2": {"title": "Sucata espacial"},
	"chapter/3": {"title": "Passagem para Phoebos"},
	"chapter/4": {"title": "A carga do Doc"},
	"chapter/5": {"title": "O comboio de armas"},
	"chapter/6": {"title": "O espião fugitivo"},
	"chapter/7": {"title": "Mercadoria delicada"},
	"chapter/8": {"title": "Abordagem ao gigante"},
	"chapter/9": {"title": "Quatro naves para Opos"},
	"chapter/10": {"title": "A frente nivelian"},
	"chapter/11": {"title": "Emboscada na nebulosa"},
	"chapter/12": {"title": "A estação dos foras da lei"},
	"chapter/13": {"title": "Vingança"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Piloto mercenário"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Tenente da frota espacial"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Comandante da frota espacial"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Passageiro apressado"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Chefe de clã vossk", "early_title": "Piloto vossk"},
	"character/5": {"title": "John \"Doc\" Washington", "subtitle": "Comerciante"},
	"character/6": {"title": "Piloto do esquadrão", "subtitle": "Frota espacial"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Oficial de segurança"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Espião em fuga"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Comerciante octopod"},
	"character/10": {"title": "Feknor", "subtitle": "Dos Grey"},
	"character/11": {"title": "Almirante Smith", "subtitle": "Frota espacial terrana"},
	"character/12": {"title": "Botom Krant", "subtitle": "Comandante de estação nivelian"},
	"progress/ranks": {"title": "Reputação e nível"},
	"progress/milestones": {"title": "Marcos"},
	"progress/loyalty": {"title": "Lealdade e subornos"},
	"mode/survival": {"title": "Sobrevivência", "subtitle": "Modo de jogo"},
	"mode/swarm": {"title": "Enxame", "subtitle": "Modo de jogo do remake"},
	"guide/start": {"title": "Primeiros passos"},
	"guide/flight": {"title": "Voar e combater"},
	"guide/weapons": {"title": "Armas e escudos"},
	"guide/hangar": {"title": "O hangar"},
	"guide/trade": {"title": "Comércio e saque"},
	"guide/travel": {"title": "Viagens e mapa"},
	"guide/jobs": {"title": "O quadro de trabalhos"},
	"guide/campaign": {"title": "Campanha e exploração livre"},
	"guide/saves": {"title": "Salvar e carregar"},
	"guide/tips": {"title": "Dicas"},
}

const BLOCKS := {
	"home": [
		[1, "", "Esta referência descreve a sua própria cópia de Galaxy on Fire: cada planeta e estação da galáxia, as naves, armas e mercadorias das lojas, os trabalhos dos quadros, as pessoas da história e as regras de comércio, viagens e reputação. Nomes, descrições e diálogos vêm do arquivo do jogo que você importou; os números seguem as regras com que este remake joga.", false],
		[1, "", "As páginas da história crescem com a sua campanha. Capítulos que você ainda não alcançou e pessoas que ainda não conheceu ficam fora da referência, e o desfecho de um capítulo aparece depois que você o joga.", false],
	],
	"intro/world": [
		[1, "", "O cenário do jogo: a guerra entre terranos e vossk, a frota espacial que Keith Maxwell acabou de deixar e os foras da lei que atacam os dois lados.", false],
	],
	"intro/story": [
		[1, "", "A campanha é uma única sequência de treze capítulos. Cada um começa com um briefing numa estação e continua num voo cheio de chamadas de rádio. Os capítulos abaixo vão até onde o seu piloto chegou.", false],
	],
	"intro/characters": [
		[1, "", "As pessoas que falam com Keith Maxwell nos briefings e pelo rádio. Cada retrato vem da arte do próprio jogo.", false],
	],
	"intro/races": [
		[1, "", "Dez povos vivem nos planetas e estações da galáxia. Os habitantes de um lugar decidem que naves a loja pode vender e, no caso de terranos e vossk, se a sua lealdade lhe custa um suborno ao viajar para lá.", false],
	],
	"intro/galaxy": [
		[1, "", "A galáxia é dividida em quatro quadrantes de vinte e cinco sistemas cada, e cada sistema tem cinco planetas ou estações. O mapa abaixo mostra todos; as viagens entre eles se abrem quando a campanha termina, ou logo de cara se você pulá-la.", false],
	],
	"intro/stations": [
		[1, "", "Todos os quinhentos planetas e estações. O nível tecnológico de um lugar define seus preços de carga e descontos em naves; só lugares com comércio têm um hangar aberto a todos.", false],
	],
	"intro/ships": [
		[1, "", "As naves que você pode comprar. Casco, porão de carga e suportes de armas as distinguem; as lojas da maioria dos povos vendem todas, exceto o caça vossk, que só os vossk vendem.", false],
	],
	"intro/equipment": [
		[1, "", "Armas e geradores de escudo. Uma nave só pode levar uma arma se tiver um suporte para aquele tipo de arma, e só uma arma de cada tipo por vez.", false],
	],
	"intro/goods": [
		[1, "", "Carga encontrada nos destroços de naves destruídas. Cada mercadoria segue sua própria regra sobre como o nível tecnológico de uma estação muda o preço.", false],
	],
	"intro/jobs": [
		[1, "", "Os tipos de trabalho oferecidos no quadro quando a galáxia está aberta. A recompensa depende do trabalho e do quadrante em que você está.", false],
	],
	"intro/progress": [
		[1, "", "Como o jogo mede o seu piloto: reputação pelos abates, nível pelos ganhos, lealdade entre terranos e vossk e as mensagens que celebram sua riqueza e sua exploração.", false],
	],
	"intro/modes": [
		[1, "", "Outras formas de jogar além da campanha e da exploração livre.", false],
	],
	"intro/guide": [
		[1, "", "Como jogar: voar, combater, equipar-se, negociar, viajar e subir na vida.", false],
	],
	"world/setting": [
		[1, "", "No quarto milênio, os terranos travam uma guerra interplanetária contra os [[race/1]]. Outros povos dividem a galáxia com eles: alguns aliados a um lado, outros negociando com ambos, outros mal conhecidos.", false],
		[1, "", "O jogo começa no ano 3587 em [[station/0]], uma estação terrana, onde o cruzador de batalha SS Ulysses deixa [[character/0]]. Após uma dispensa honrosa da frota espacial, ele recebeu uma nave própria do [[character/11|almirante Smith]] e pretende ganhar a vida como mercenário.", false],
		[1, "Onde acontece", "Toda a campanha se passa no primeiro quadrante, [[quadrant/0]], perto de [[station/0]]. O resto da galáxia se abre quando a história termina.", false],
		[14, "Depois da guerra", "Com o líder dos foras da lei morto e um motor de hiperespaço a bordo, Maxwell recusa um lugar na frota. A galáxia é dele para explorar, negociar e lutar por quem pagar.", false],
	],
	"world/fleet": [
		[1, "", "A frota espacial terrana é o exército dos mundos terranos. Maxwell serviu nela antes do início do jogo, e a maior parte dos trabalhos da campanha vem de seus oficiais ou de pessoas próximas a eles.", false],
		[1, "", "Seu caça padrão é a [[ship/6]]. Entre seus oficiais na história estão [[character/1]], que mostra a Maxwell sua nova nave, e o [[character/11|almirante Smith]], que a deu a ele.", false],
		[5, "", "A frota também tem agentes. A tenente Hammond trabalha disfarçada em [[station/2]] por ordem do almirante.", false],
		[6, "", "O oficial de segurança [[character/7]] caça traidores dentro da frota.", false],
		[12, "", "Nem todos os seus comandantes são leais: um deles negociou com os vossk e os foras da lei pelas costas da frota.", false],
	],
	"world/outlaws": [
		[9, "", "Os foras da lei pilotam naves terranas modificadas e atacam comboios. Quando emboscam um comboio grey em pleno território vossk, fica claro que trabalham com os vossk.", false],
		[12, "", "Os foras da lei têm um líder dentro da própria frota espacial, que vendeu segredos militares roubados aos vossk e acobertou os ataques aos transportes. Eles resistem numa estação própria atrás de um campo minado.", false],
		[1, "", "Os foras da lei também têm um povo próprio no mapa da galáxia: os lugares habitados por [[race/9]] são suas estações e planetas. Só as lojas deles vendem a [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell chega a [[station/0]] e é recebido pela tenente [[character/1]], que tem ordens do almirante Smith para lhe mostrar a nova nave, uma velha batedora [[ship/0]]. Ela explica o hangar: naves, armas e equipamentos são comprados na loja, e a carga coletada no espaço é vendida a partir do porão.", false],
		[1, "", "Depois vem um voo de teste. Christine o guia pelos pontos de rota, explica escudos, troca de arma, disparo e propulsão, e por fim solta alguns drones de treino para derrubar.", false],
		[2, "Desfecho", "Maxwell destrói os drones e volta à estação. Christine lhe deseja sorte e espera revê-lo inteiro.", false],
	],
	"chapter/2": [
		[2, "", "Um rosto indesejado da frota: o comandante [[character/2]], que Maxwell nunca suportou, tem um trabalho para ele. Um corredor espacial perto da estação precisa ser limpo de destroços antes que chegue o próximo comboio, e há só dois minutos para isso.", false],
		[3, "Desfecho", "O corredor é limpo a tempo e Vlad paga, comentando que Maxwell nasceu para esse trabalho.", false],
	],
	"chapter/3": [
		[3, "", "Um cliente pequeno e nervoso, [[character/3]], quer ser levado a [[station/1]] imediatamente, antes que um negócio dele vá por água abaixo. O lugar está infestado de vossk, mas ele paga bem e Maxwell aceita.", false],
		[4, "Desfecho", "No caminho, uma patrulha vossk exige a rendição deles. Maxwell leva Bolar até lá, e o passageiro promete recomendá-lo assim que parar de tremer.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] precisa de escolta para a nave dele até [[station/2]], o esconderijo dos piratas. Maxwell aumenta o preço pelo risco e suspeita que a carga é mais uma entrega de armas para os foras da lei.", false],
		[5, "Desfecho", "Caças vossk atacam o cargueiro duas vezes. Ele chega a Tortuga, e Doc deixa claro que o que ele levava não é da conta de Maxwell.", false],
	],
	"chapter/5": [
		[5, "", "Em Tortuga, Maxwell encontra [[character/1]], que está lá disfarçada. A frota recebeu ordens de interceptar um comboio de armas vossk perto de [[station/3]]; se a entrega passar, haverá um massacre. O esquadrão dela precisa de mais um piloto experiente.", false],
		[6, "Desfecho", "Primeiro cai a escolta, depois os cargueiros. O comboio é detido, e Christine espera que o almirante Smith fique satisfeito.", false],
	],
	"chapter/6": [
		[6, "", "O oficial de segurança [[character/7]] tem um trabalho que não pode dar errado: [[character/8]], um espião, fugiu com uma das naves secretas da frota. Ela não pode cair em mãos inimigas e, se preciso, deve ser destruída.", false],
		[7, "Desfecho", "Maxwell encontra Lockwood num campo de asteroides e danifica a nave dele até que ele se renda. Antes que alguém possa prendê-lo, [[character/2|Vlad Borsikov]] o derruba e lembra Maxwell de que a ordem era destruir a nave. Maxwell começa a suspeitar de que nunca se tratou só de uma nave.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] pede escolta para as naves dele até [[station/4]]. Maxwell reconhece o bando octopod, famoso por andar abarrotado de mercadoria roubada, mas aceita desde que as autoridades fiquem de fora.", false],
		[8, "Desfecho", "O que começa como dinheiro fácil vira luta contra caças vossk e um cruzador. Pelo menos uma nave passa, e Maxwell nota que os vossk estão ficando mais agressivos.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] localizou um cruzador de batalha vossk avariado. A frota quer capturá-lo e pegar o comandante vivo, mas antes é preciso destruir cada canhão fixo do casco.", false],
		[9, "Desfecho", "Enquanto o esquadrão de Christine atrai o fogo, Maxwell elimina os canhões, e a nave é abordada.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]], dos Grey, contrata Maxwell para levar um comboio de quatro naves até [[station/5]], atravessando o território vossk, e paga por cada nave que chegar.", false],
		[10, "Desfecho", "Os atacantes não são vossk, e sim naves terranas modificadas. Maxwell os repele e conclui que os foras da lei trabalham com os vossk.", false],
	],
	"chapter/10": [
		[10, "", "O [[character/11]] precisa de todos os pilotos disponíveis: uma estação dos aliados dos terranos, os nivelian, está sob ataque de fortes forças vossk. Depois de uma troca ríspida sobre os preços e lealdades de Maxwell, o almirante o manda para lá.", false],
		[11, "Desfecho", "O comandante da estação, [[character/12]], pede a Maxwell que se concentre nos cruzadores enquanto [[character/1|Christine]] cuida dos caças. O ataque é repelido, e os dois concordam que os foras da lei são o perigo que resta.", false],
	],
	"chapter/11": [
		[11, "", "Um chefe de clã vossk, [[character/4]], contata Maxwell em segredo. Um dos comandantes vossk conspira com um oficial terrano e os foras da lei, e o clã o quer morto. O melhor lugar para uma emboscada é a nebulosa Yarapu.", false],
		[12, "Desfecho", "Maxwell destrói o cruzador do comandante e a escolta. Nartok conta que o traidor do lado terrano é um velho conhecido de Maxwell e que a tenente Hammond já está na pista dele.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] traz a notícia: [[character/2]] é o líder dos foras da lei. Como comandante, ele acobertou os ataques aos transportes e fez Lockwood roubar segredos militares para vendê-los aos vossk. O bando dele se entrincheirou numa estação de foras da lei protegida por um campo minado, que Maxwell precisa limpar antes do ataque.", false],
		[13, "Desfecho", "O campo minado é limpo e os defensores da estação caem. Christine avança contra Vlad, que a derruba antes que Maxwell possa cobri-la, e foge.", false],
	],
	"chapter/13": [
		[13, "", "O [[character/11]] oferece condolências; Maxwell só quer saber para onde Vlad foi. A frota encontrou Vlad e o que resta dos foras da lei dele, e seus esquadrões precisam da ajuda de Maxwell para derrotá-los.", false],
		[14, "Desfecho", "Derrotados os foras da lei, Maxwell deixa a frota com seu trabalho, persegue Vlad sozinho e o mata. O almirante lhe oferece um lugar na frota; Maxwell recusa. Ele recebe um motor de hiperespaço, que abre todos os quadrantes da galáxia.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell é o piloto do jogador: um ex-piloto da frota espacial terrana que, após uma dispensa honrosa, recebe uma nave do [[character/11|almirante Smith]] e começa a vida de mercenário em [[station/0]].", false],
		[1, "", "Ele é sarcástico e rápido para barganhar seus honorários, mas termina os trabalhos que aceita.", false],
		[7, "", "Ele protesta quando [[character/2|Vlad Borsikov]] derruba um homem que já tinha se rendido.", false],
		[13, "", "A morte de [[character/1|Christine Hammond]] torna o último capítulo uma questão pessoal.", false],
		[14, "", "Depois de matar Vlad, ele recusa voltar à frota e prefere escolher o próprio caminho pela galáxia.", false],
	],
	"character/1": [
		[1, "", "A tenente Christine Hammond, da frota espacial terrana, recebe Maxwell em [[station/0]], mostra a nave dele e faz com ele o primeiro voo de teste. Ela pede que ele a chame de Christine.", false],
		[5, "", "Ela também atua como agente: em [[station/2]] está disfarçada por ordem do almirante Smith, e leva Maxwell para o ataque ao comboio de armas vossk.", false],
		[8, "", "Ela lidera o esquadrão que captura um cruzador de batalha vossk avariado.", false],
		[12, "", "Ela descobre que [[character/2|Vlad Borsikov]] está por trás dos foras da lei e planeja o ataque à estação deles.", false],
		[13, "", "Ela avança contra Vlad depois da batalha e é derrubada por ele. A morte dela lança Maxwell atrás de Vlad no último capítulo.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov é comandante da frota espacial terrana e, nas palavras de Maxwell, o sujeito mais desprezível dela. Ele dá a Maxwell seu primeiro trabalho pago: limpar um corredor espacial de destroços contra o relógio.", false],
		[7, "", "Ele derruba o espião Corsair Lockwood depois que ele se rende e insiste que a ordem era destruir a nave.", false],
		[12, "", "Ele é o traidor: o líder dos foras da lei, que usou o posto para acobertar os ataques aos transportes e fez Lockwood roubar segredos militares que vendeu aos vossk.", false],
		[13, "", "Quando Christine Hammond vai atrás dele depois do ataque à estação, ele a derruba e foge.", false],
		[14, "", "A frota o encontra com o que resta dos foras da lei, e Maxwell o mata num duelo.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon é um cliente agitado que precisa chegar a [[station/1]] imediatamente para salvar um negócio, e paga bem a um piloto disposto a levá-lo pelo espaço vossk.", false],
		[4, "", "Ele sobrevive à emboscada vossk e promete recomendar Maxwell.", false],
	],
	"character/4": [
		[4, "", "Um vossk com este rosto chama Maxwell a caminho de Phoebos e exige a rendição em nome do Império Vossk.", false],
		[11, "", "Nartok Brek é um chefe de clã dos [[race/1]]. Ele contata Maxwell em segredo porque um de seus próprios comandantes conspira com um oficial terrano e os foras da lei, e pede que o traidor seja emboscado na nebulosa Yarapu. Ele exige a palavra de honra de Maxwell antes de dizer qualquer coisa.", false],
		[12, "", "Depois da emboscada, ele conta a Maxwell que o próprio Maxwell já conhece o traidor terrano.", false],
	],
	"character/5": [
		[4, "", "John Washington, chamado de Doc pelos amigos, precisa de escolta para a nave dele até [[station/2]]. Ele oferece 3.000 créditos e aceita 4.500, desde que não haja testemunhas. Maxwell suspeita de uma entrega de armas para os foras da lei.", false],
		[5, "", "A carga dele chega. O que era, ele guarda para si.", false],
	],
	"character/6": [
		[6, "", "Um piloto do esquadrão de Christine Hammond, que pergunta pelo rádio se esse Maxwell tem alguma experiência de combate, sem perceber que ele está ouvindo.", false],
		[13, "", "O mesmo esquadrão fica para trás para proteger a estação dos foras da lei enquanto Christine e Maxwell perseguem Vlad.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom é o oficial de segurança da frota espacial. Ele manda Maxwell atrás do espião [[character/8]], com ordens de que a nave roubada não pode cair em mãos inimigas.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood é um espião que fugiu com uma das naves secretas da frota espacial.", false],
		[7, "", "Encurralado num campo de asteroides, ele se rende, e mesmo assim Vlad Borsikov o derruba.", false],
		[12, "", "Mais tarde se descobre que foi o próprio Vlad quem o encarregou de roubar segredos militares.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt transporta carga para o bando octopod, famoso por levar mercadoria roubada. Ele garante que tudo a bordo é perfeitamente legal e paga Maxwell para levar suas naves até [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor, dos Grey, ouviu falar de Maxwell e oferece um trabalho difícil: quatro naves até [[station/5]] atravessando o território vossk, a 4.000 créditos por nave que chegar.", false],
	],
	"character/11": [
		[1, "", "O almirante Smith, da frota espacial terrana, deu a Maxwell a nave após a dispensa e encarrega a tenente Hammond de mostrar como usá-la.", false],
		[10, "", "Ele convoca Maxwell quando a estação nivelian é atacada. A conversa fica tensa quando Maxwell fala de seus preços e do que os vossk poderiam pagar.", false],
		[13, "", "Depois da morte de Christine, ele oferece condolências a Maxwell e revela onde estão os foras da lei de Vlad.", false],
		[14, "", "Ele deixa Maxwell perseguir Vlad sozinho, oferece-lhe um lugar na frota e lhe dá um motor de hiperespaço quando ele recusa.", false],
	],
	"character/12": [
		[11, "", "Botom Krant comanda a estação nivelian atacada pelos vossk. Ele pede a Maxwell que se concentre nos cruzadores e agradece quando o ataque é repelido.", false],
	],
	"race/0": [
		[1, "", "Humanos, em guerra com os [[race/1]] no quarto milênio. Maxwell é terrano, e a maioria dos clientes da campanha serve à frota espacial terrana. Os terranos têm mais planetas e estações do que qualquer outro povo.", false],
		[1, "", "Muitas das naves à venda são projetos terranos: a [[ship/0]], a [[ship/6]] e sua versão modificada, a [[ship/7]], e a canhoneira [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "O inimigo dos terranos. As lojas vossk vendem só o próprio caça, a [[ship/8]], e são as únicas que vendem as armas vossk. Um piloto que trabalha para os terranos paga subornos nas estações vossk, e vice-versa.", false],
	],
	"race/2": [
		[1, "", "Um dos povos da galáxia, com planetas e estações próprios.", false],
	],
	"race/3": [
		[1, "", "Um dos povos da galáxia, com planetas e estações próprios.", false],
	],
	"race/4": [
		[1, "", "Seus componentes especiais entram em armas como o [[equipment/23]], e o pesado bombardeiro [[ship/3]] é deles.", false],
	],
	"race/5": [
		[1, "", "As naves grey são conhecidas pela blindagem extremamente pesada. A batedora [[ship/9]] vem da frota deles e só recentemente foi adaptada para pilotos humanoides, e o míssil [[equipment/4]] é feito com componentes grey. Feknor, dos Grey, contrata Maxwell para um comboio perigoso.", false],
	],
	"race/6": [
		[1, "", "Aliados dos terranos. O caça [[ship/1]] é um desenvolvimento nivelian, e o laser [[equipment/2]] se baseia em tecnologia bélica nivelian. O ataque vossk a uma das estações deles põe Maxwell de vez na guerra.", false],
	],
	"race/7": [
		[1, "", "Um dos povos da galáxia, com planetas e estações próprios.", false],
	],
	"race/8": [
		[1, "", "Um dos povos da galáxia, com planetas e estações próprios.", false],
	],
	"race/9": [
		[1, "", "Os foras da lei não são um povo, e sim um modo de vida: piratas e contrabandistas com planetas e estações próprios. Só as lojas deles vendem a [[ship/7]], e [[station/2]] é o esconderijo mais conhecido deles.", false],
	],
	"galaxy": [
		[1, "", "Quatro quadrantes, cem sistemas e quinhentos planetas e estações. Cada quadrante é mais difícil que o anterior: seus trabalhos pagam mais, seus inimigos são mais duros e suas lojas vendem equipamentos melhores.", false],
		[1, "", "Voar dentro de um quadrante custa créditos conforme a distância; passar ao quadrante vizinho ou ao oposto custa um extra. Depois de visitar todos os lugares da galáxia, viajar é de graça.", false],
	],
	"progress/ranks": [
		[1, "Reputação", "A reputação conta os inimigos que você destruiu. Cada limite da tabela abaixo eleva a sua patente, mostrada na tela \"Status\".", false],
		[1, "Nível", "O seu nível cresce com o dinheiro ganho em missões e trabalhos. Quando seus ganhos totais passam de 1,6 vez o que eram no último nível, você chega ao próximo. Níveis mais altos tornam mais duros os inimigos das suas missões.", false],
	],
	"progress/milestones": [
		[1, "", "Ao atracar, a estação recebe você com uma mensagem na primeira vez que seus créditos passam de um marco ou sua exploração da galáxia atinge uma nova marca. As mensagens abaixo são as do próprio jogo.", false],
		[1, "Riqueza", "Riqueza é mais que um número. Com mais de 999.999 créditos, você pode negociar em todos os planetas e estações: o hangar se abre até onde não há comércio, e lá você pode comprar, vender carga e saque e reequipar a nave.", false],
		[1, "Exploração", "Cada lugar visitado conta. Visitar todos os quinhentos torna toda viagem gratuita.", false],
	],
	"progress/loyalty": [
		[1, "", "A sua lealdade fica em algum ponto entre terranos e vossk, indicado pelo ponteiro da tela \"Status\". Cada missão para um cliente terrano a move um passo em direção aos terranos; cada missão para um cliente vossk, um passo em direção aos vossk. Ela não passa de dez passos para nenhum lado.", false],
		[1, "", "Ao viajar para um lugar terrano com a lealdade pendendo para os vossk, ou para um lugar vossk com ela pendendo para os terranos, cobram um suborno além do custo do voo: 150 créditos por passo. Pagar um suborno move a sua lealdade um passo de volta ao centro.", false],
	],
	"mode/survival": [
		[1, "", "Sobrevivência é um modo à parte, com piloto e tabela de recordes próprios. Escolha-o em \"Start Game\". Naves inimigas não param de chegar, cada abate rende pontos e repara o casco, e a cor da marcação de um inimigo mostra a força dele. A sua pontuação rende uma patente da tabela abaixo.", false],
	],
	"mode/swarm": [
		[1, "", "Enxame é um modo criado para este remake, disponível em \"Start Game\". Começa com um punhado de caças e cresce até virar uma multidão que se fecha de todos os lados, com ondas após o quinto minuto.", false],
		[1, "", "Cada abate enche a barra de nível. Cada nível oferece três cartas de melhoria: uma arma nova, uma versão melhor de uma que você tem, um cano extra, mais alcance ou velocidade de projétil, um escudo mais forte, reparo a cada abate ou um casco diferente. Recusar uma carta repara um quarto do casco no lugar.", false],
		[1, "", "As armas, escudos e cascos são os do seu arquivo do jogo. Alcançar uma patente no ranking de Sobrevivência desbloqueia o próximo casco para o Enxame.", false],
	],
	"guide/start": [
		[1, "", "Depois de importar o arquivo do jogo, \"Start Game\" oferece a campanha, a exploração livre, Sobrevivência e Enxame. A campanha começa em [[station/0]] com uma [[ship/0]] e 5.000 créditos.", false],
		[1, "O menu da estação", "Numa estação, \"Info\" descreve o lugar, \"Hangar\" abre a loja e a sua nave, \"Missions\" mostra o quadro de trabalhos e \"Map\" permite viajar. Durante a campanha, o quadro e o mapa ficam bloqueados, e \"Go on\" inicia o próximo briefing. \"Status\" mostra nível, reputação, tempo de jogo, abates e lealdade, e \"Menu\" guarda as opções e o salvamento.", false],
		[1, "", "Nem todo lugar tem um hangar aberto a todos: sem comércio, o hangar só abre durante a campanha ou quando você tem mais de 999.999 créditos.", false],
	],
	"guide/flight": [
		[1, "", "Pontos de rota são marcados em amarelo, aliados em verde e inimigos em vermelho. Objetos fora da sua visão aparecem na borda da tela. A força restante de um inimigo aparece abaixo da marcação dele.", false],
		[1, "", "O escudo absorve colisões e impactos e se recarrega com o tempo; quando acaba, o dano vai para o casco. A propulsão dá uma breve arrancada e precisa de tempo para recarregar.", false],
		[1, "Controles", "No teclado, pilote com o mouse ou as setas, ajuste o empuxo com W e S e desloque-se para os lados com A e D. Atire com um clique ou Espaço, troque de arma com Q, dispare mísseis com F e use a propulsão com Shift. R liga o piloto automático, T acelera o tempo em trechos seguros, E atraca perto de uma estação e Esc pausa. Um controle mira com o direcional direito e atira com o gatilho direito. Os controles de toque têm um direcional, um acelerador e botões de tiro, mísseis, propulsão e navegação; um toque duplo em Tiro ativa o tiro automático.", false],
		[1, "Piloto automático e tempo", "O piloto automático voa até o próximo ponto de rota ou a estação. Enquanto nada ameaça você, o tempo pode correr mais rápido; inimigos, dano ou a chegada ao destino o devolvem ao normal.", false],
	],
	"guide/weapons": [
		[1, "", "As naves têm suportes para cinco tipos de arma: lasers, canhões de plasma, canhões de fótons, mísseis e canhões térmicos. Cada suporte leva uma arma, e cada nave tem o próprio conjunto de suportes. Um gerador de escudo serve em qualquer nave.", false],
		[1, "", "Lasers e canhões de plasma disparam rápido a média distância. Canhões de fótons alcançam mais longe e acertam mais forte por tiro, mas recarregam devagar. Canhões térmicos espalham partículas a curta distância com cadência altíssima. Mísseis são lançados com um botão próprio, sem trocar de arma, e causam dano pesado com recarga longa.", false],
		[1, "", "Os escudos diferem em capacidade e em velocidade de recarga. As armas mais fortes só são vendidas a partir do segundo quadrante, e as armas vossk só em lojas vossk.", false],
	],
	"guide/hangar": [
		[1, "", "O hangar tem três partes: \"Ship\" mostra a sua nave com as armas montadas e o escudo, \"Cargo\" guarda suas mercadorias e equipamento reserva, e \"Shop\" oferece o estoque da estação.", false],
		[1, "", "O equipamento comprado vai para o porão; instale-o de lá se a sua nave tiver um suporte livre para ele. Equipamentos e naves são revendidos pela metade do preço.", false],
		[1, "", "Comprar uma nave dá a atual como parte do pagamento. O equipamento que serve na nova nave continua montado e o resto vai para o porão, desde que haja espaço.", false],
		[1, "", "As lojas vendem de uma a quatro armas ou escudos e até três naves, escolhidos entre o que o quadrante e o povo do lugar permitem. O estoque se renova quando você volta depois de voar para outro lugar. Durante a campanha, cada capítulo tem seu próprio estoque fixo.", false],
	],
	"guide/trade": [
		[1, "", "As mercadorias vêm dos destroços de naves destruídas e vão para o porão depois da missão. Venda-as na seção de carga do hangar. Algumas valem mais onde a tecnologia é baixa, outras onde é alta e outras o mesmo em todo lugar; a página de cada mercadoria mostra o preço em cada nível tecnológico.", false],
		[1, "", "As lojas não têm mercadorias próprias. O que você vende numa loja fica no estoque dela, e você pode recomprar lá pelo mesmo preço.", false],
		[1, "", "O comércio precisa de um hangar: planetas e estações sem comércio só abrem o deles para pilotos com mais de 999.999 créditos.", false],
	],
	"guide/travel": [
		[1, "", "O mapa mostra a galáxia, seus quadrantes e sistemas. Escolha um lugar e viaje até lá pelo custo de voo mostrado, mais um suborno se a sua lealdade for contra o povo dele. Você chega já atracado.", false],
		[1, "", "O custo do voo cresce com a distância. Mudar de quadrante soma 15.000 créditos à tarifa, e 30.000 para o quadrante oposto. O mapa mostra quanto da galáxia você explorou; com todos os lugares visitados, viajar não custa nada.", false],
		[1, "", "A galáxia se abre quando a campanha está completa ou quando você a pula.", false],
	],
	"guide/jobs": [
		[1, "", "Fora da campanha, o quadro de trabalhos de cada estação oferece alguns trabalhos de clientes de povos diferentes. Cada um mostra dificuldade e recompensa; trabalhos difíceis pagam mais, assim como os quadrantes mais distantes.", false],
		[1, "", "De vez em quando, um vigarista suspeito oferece um trabalho que paga quarenta por cento a mais que o normal. Um trabalho concluído paga a recompensa e move a sua lealdade em direção ao povo do cliente.", false],
	],
	"guide/campaign": [
		[1, "", "A campanha é uma sequência de treze missões. Uma missão cumprida paga a recompensa; uma que falhou pode ser repetida. Quando ela termina, o motor de hiperespaço abre a galáxia, e o quadro de trabalhos e o mapa ficam disponíveis.", false],
		[1, "", "\"Pular campanha · Explorar\", no menu inicial ou no menu da estação, leva direto à exploração livre. Pular não dá recompensas de conclusão e mantém o seu piloto da campanha no próprio espaço.", false],
	],
	"guide/saves": [
		[1, "", "O jogo salva automaticamente após cada missão e nos pontos de controle. Campanha, exploração, Sobrevivência e Enxame têm salvamentos separados. \"Carregar / recuperar\" no menu de pausa, ou \"Load\" após uma derrota, volta ao último salvamento automático, ao início do voo ou à última estação.", false],
		[1, "", "\"Arquivos do jogo\" → \"Transferir jogos salvos\" leva seus salvamentos para outro dispositivo que importou o mesmo arquivo do jogo.", false],
	],
	"guide/tips": [
		[1, "", "Venda a carga recolhida dos destroços antes de comprar equipamento; em naves pequenas o porão enche rápido.", true],
		[1, "", "Confira os suportes de uma nave antes de comprar armas para ela: uma arma sem suporte compatível fica no porão.", true],
		[1, "", "Guarde as mercadorias até atracar onde o nível tecnológico as favorece.", true],
		[1, "", "Voar só para um lado deixa caras as visitas às estações do outro.", true],
		[1, "", "Visite lugares novos quando for viajar de qualquer forma: explorar a galáxia inteira torna toda viagem gratuita.", true],
	],
}
