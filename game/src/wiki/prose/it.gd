extends RefCounted
## The reference's own writing in Italian. Same blocks, chapter gates and links
## as prose/en.gd; see there for the format.

const PAGES := {
	"home": {"title": "Riferimento"},
	"world/setting": {"title": "Una galassia in guerra"},
	"world/fleet": {"title": "La flotta spaziale terrana"},
	"world/outlaws": {"title": "Fuorilegge e pirati"},
	"chapter/1": {"title": "Una nave nuova"},
	"chapter/2": {"title": "Rottami spaziali"},
	"chapter/3": {"title": "Passaggio per Phoebos"},
	"chapter/4": {"title": "Il carico di Doc"},
	"chapter/5": {"title": "Il convoglio di armi"},
	"chapter/6": {"title": "La spia in fuga"},
	"chapter/7": {"title": "Merce delicata"},
	"chapter/8": {"title": "L'abbordaggio del gigante"},
	"chapter/9": {"title": "Quattro navi per Opos"},
	"chapter/10": {"title": "Il fronte niveliano"},
	"chapter/11": {"title": "Imboscata nella nebulosa"},
	"chapter/12": {"title": "La stazione dei fuorilegge"},
	"chapter/13": {"title": "Vendetta"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Pilota mercenario"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Tenente della flotta spaziale"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Comandante della flotta spaziale"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Passeggero di fretta"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Capoclan vossk", "early_title": "Pilota vossk"},
	"character/5": {"title": "John \"Doc\" Washington", "subtitle": "Mercante"},
	"character/6": {"title": "Pilota di squadriglia", "subtitle": "Flotta spaziale"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Ufficiale della sicurezza"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Spia in fuga"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Mercante ottopode"},
	"character/10": {"title": "Feknor", "subtitle": "Dei Grey"},
	"character/11": {"title": "Ammiraglio Smith", "subtitle": "Flotta spaziale terrana"},
	"character/12": {"title": "Botom Krant", "subtitle": "Comandante di stazione niveliano"},
	"progress/ranks": {"title": "Reputazione e livello"},
	"progress/milestones": {"title": "Traguardi"},
	"progress/loyalty": {"title": "Lealtà e tangenti"},
	"mode/survival": {"title": "Sopravvivenza", "subtitle": "Modalità di gioco"},
	"mode/swarm": {"title": "Sciame", "subtitle": "Modalità del remake"},
	"guide/start": {"title": "Primi passi"},
	"guide/flight": {"title": "Volare e combattere"},
	"guide/weapons": {"title": "Armi e scudi"},
	"guide/hangar": {"title": "L'hangar"},
	"guide/trade": {"title": "Commercio e bottino"},
	"guide/travel": {"title": "Viaggi e mappa"},
	"guide/jobs": {"title": "La bacheca dei lavori"},
	"guide/campaign": {"title": "Campagna ed esplorazione libera"},
	"guide/saves": {"title": "Salvare e caricare"},
	"guide/tips": {"title": "Consigli"},
}

const BLOCKS := {
	"home": [
		[1, "", "Questo riferimento descrive la tua copia di Galaxy on Fire: ogni pianeta e stazione della galassia, le navi, le armi e le merci dei suoi negozi, i lavori delle sue bacheche, i personaggi della sua storia e le regole di commercio, viaggi e reputazione. Nomi, descrizioni e dialoghi provengono dal file di gioco che hai importato; le cifre seguono le regole con cui gioca questo remake.", false],
		[1, "", "Le pagine della storia crescono con la tua campagna. I capitoli che non hai ancora raggiunto e le persone che non hai incontrato restano fuori dal riferimento, e l'esito di un capitolo compare quando lo hai giocato.", false],
	],
	"intro/world": [
		[1, "", "L'ambientazione del gioco: la guerra tra Terrani e Vossk, la flotta spaziale che Keith Maxwell ha appena lasciato e i fuorilegge che depredano entrambe le parti.", false],
	],
	"intro/story": [
		[1, "", "La campagna è un'unica sequenza di tredici capitoli. Ognuno inizia con un briefing in una stazione e prosegue con un volo pieno di chiamate radio. I capitoli qui sotto arrivano fin dove è arrivato il tuo pilota.", false],
	],
	"intro/characters": [
		[1, "", "Le persone che parlano con Keith Maxwell nei briefing e via radio. Ogni ritratto proviene dalla grafica del gioco.", false],
	],
	"intro/races": [
		[1, "", "Dieci popoli vivono sui pianeti e sulle stazioni della galassia. Gli abitanti di un luogo decidono quali navi può vendere il suo negozio e, per Terrani e Vossk, se la tua lealtà ti costa una tangente quando ci vai.", false],
	],
	"intro/galaxy": [
		[1, "", "La galassia è divisa in quattro quadranti di venticinque sistemi ciascuno, e ogni sistema contiene cinque pianeti o stazioni. La mappa qui sotto li mostra tutti; i viaggi tra di essi si aprono a campagna conclusa, o subito se la salti.", false],
	],
	"intro/stations": [
		[1, "", "Tutti i cinquecento pianeti e stazioni. Il livello tecnologico di un luogo fissa i prezzi delle merci e gli sconti sulle navi; solo i luoghi con commercio hanno un hangar aperto a tutti.", false],
	],
	"intro/ships": [
		[1, "", "Le navi che puoi comprare. Scafo, stiva e supporti per armi le distinguono; i negozi della maggior parte dei popoli le vendono tutte tranne il caccia vossk, che vendono solo i Vossk.", false],
	],
	"intro/equipment": [
		[1, "", "Armi e generatori di scudo. Una nave può portare un'arma solo se ha un supporto per quel tipo di arma, e una sola arma di ogni tipo alla volta.", false],
	],
	"intro/goods": [
		[1, "", "Merci trovate tra i rottami delle navi distrutte. Ogni tipo di merce segue la propria regola su come il livello tecnologico di una stazione ne cambia il prezzo.", false],
	],
	"intro/jobs": [
		[1, "", "I tipi di lavoro offerti in bacheca una volta aperta la galassia. La ricompensa dipende dal lavoro e dal quadrante in cui ti trovi.", false],
	],
	"intro/progress": [
		[1, "", "Come il gioco misura il tuo pilota: reputazione dalle uccisioni, livello dai guadagni, lealtà tra Terrani e Vossk e i messaggi che celebrano la tua ricchezza e la tua esplorazione.", false],
	],
	"intro/modes": [
		[1, "", "Modi di giocare oltre alla campagna e all'esplorazione libera.", false],
	],
	"intro/guide": [
		[1, "", "Come si gioca: volare, combattere, equipaggiarsi, commerciare, viaggiare e farsi strada.", false],
	],
	"world/setting": [
		[1, "", "Nel quarto millennio i Terrani combattono una guerra interplanetaria contro i [[race/1]]. Altri popoli condividono con loro la galassia: alcuni alleati con una parte, altri in affari con entrambe, altri appena conosciuti.", false],
		[1, "", "Il gioco inizia nell'anno 3587 su [[station/0]], una stazione terrana, dove l'incrociatore da battaglia SS Ulysses lascia [[character/0]]. Dopo un congedo con onore dalla flotta spaziale, ha ricevuto una nave tutta sua dall'[[character/11|ammiraglio Smith]] e intende guadagnarsi da vivere come mercenario.", false],
		[1, "Dove si svolge", "L'intera campagna si svolge nel primo quadrante, [[quadrant/0]], vicino a [[station/0]]. Il resto della galassia si apre quando la storia è finita.", false],
		[14, "Dopo la guerra", "Con il capo dei fuorilegge morto e un motore iperspaziale a bordo, Maxwell rifiuta un posto nella flotta. La galassia è sua: da esplorare, in cui commerciare e per cui combattere al servizio di chi paga.", false],
	],
	"world/fleet": [
		[1, "", "La flotta spaziale terrana è l'esercito dei mondi terrani. Maxwell vi ha prestato servizio prima dell'inizio del gioco, e la maggior parte dei suoi incarichi di campagna arriva dai suoi ufficiali o dalle persone a loro vicine.", false],
		[1, "", "Il suo caccia standard è la [[ship/6]]. Tra i suoi ufficiali nella storia ci sono [[character/1]], che mostra a Maxwell la sua nuova nave, e l'[[character/11|ammiraglio Smith]], che gliel'ha data.", false],
		[5, "", "La flotta impiega anche agenti. La tenente Hammond lavora sotto copertura su [[station/2]] per ordine dell'ammiraglio.", false],
		[6, "", "L'ufficiale della sicurezza [[character/7]] dà la caccia ai traditori all'interno della flotta.", false],
		[12, "", "Non tutti i suoi comandanti sono leali: uno di loro ha trattato con i Vossk e i fuorilegge alle spalle della flotta.", false],
	],
	"world/outlaws": [
		[9, "", "I fuorilegge pilotano navi terrane modificate e attaccano i convogli. Quando tendono un'imboscata a un convoglio grey nel cuore del territorio vossk, diventa chiaro che lavorano con i Vossk.", false],
		[12, "", "I fuorilegge hanno un capo all'interno della stessa flotta spaziale, che ha venduto segreti militari rubati ai Vossk e coperto gli attacchi ai trasporti. Resistono in una stazione tutta loro dietro un campo minato.", false],
		[1, "", "I fuorilegge hanno anche un popolo proprio sulla mappa della galassia: i luoghi abitati dai [[race/9]] sono le loro stazioni e i loro pianeti. I loro negozi sono gli unici a vendere la [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell arriva su [[station/0]] e viene accolto dalla tenente [[character/1]], che ha l'ordine dell'ammiraglio Smith di mostrargli la sua nuova nave, una vecchia ricognitrice [[ship/0]]. Lei gli spiega l'hangar: navi, armi ed equipaggiamento si comprano nello shop, e le merci raccolte nello spazio si vendono dalla stiva.", false],
		[1, "", "Segue un volo di prova. Christine lo guida tra i waypoint, gli spiega scudi, cambio d'arma, fuoco e boost, e alla fine fa partire alcuni droni d'addestramento da abbattere.", false],
		[2, "Esito", "Maxwell distrugge i droni e torna alla stazione. Christine gli augura buona fortuna e spera di rivederlo tutto intero.", false],
	],
	"chapter/2": [
		[2, "", "Un volto sgradito della flotta: il comandante [[character/2]], che Maxwell non ha mai sopportato, ha un lavoro per lui. Un corridoio spaziale vicino alla stazione va ripulito dai rottami prima dell'arrivo del prossimo convoglio, e ci sono solo due minuti per farlo.", false],
		[3, "Esito", "Il corridoio è libero in tempo e Vlad paga, osservando che Maxwell è fatto per questo lavoro.", false],
	],
	"chapter/3": [
		[3, "", "Un piccolo cliente nervoso, [[character/3]], vuole essere portato subito su [[station/1]], prima che salti un suo affare. Il posto pullula di Vossk, ma paga bene e Maxwell accetta.", false],
		[4, "Esito", "Lungo la strada una pattuglia vossk ne pretende la resa. Maxwell porta Bolar a destinazione, e il passeggero promette di raccomandarlo appena avrà smesso di tremare.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] ha bisogno di una scorta per la sua nave fino a [[station/2]], il covo dei pirati. Maxwell alza il compenso per il rischio e sospetta che il carico sia un'altra consegna di armi per i fuorilegge.", false],
		[5, "Esito", "I caccia vossk attaccano il mercantile due volte. Raggiunge Tortuga, e Doc mette in chiaro che quello che trasportava non è affare di Maxwell.", false],
	],
	"chapter/5": [
		[5, "", "Su Tortuga Maxwell incontra [[character/1]], che è lì sotto copertura. La flotta ha l'ordine di intercettare un convoglio di armi vossk vicino a [[station/3]]; se la consegna passa, sarà un massacro. La sua squadriglia ha bisogno di un altro pilota esperto.", false],
		[6, "Esito", "Cade prima la scorta, poi i mercantili. Il convoglio è fermato, e Christine si aspetta che l'ammiraglio Smith ne sarà contento.", false],
	],
	"chapter/6": [
		[6, "", "L'ufficiale della sicurezza [[character/7]] ha un lavoro che non può andare storto: [[character/8]], una spia, è fuggito con una delle navi segrete della flotta. Non deve cadere in mano nemica e, se necessario, va distrutta.", false],
		[7, "Esito", "Maxwell trova Lockwood in un campo di asteroidi e gli danneggia la nave finché non si arrende. Prima che qualcuno possa arrestarlo, [[character/2|Vlad Borsikov]] lo abbatte e ricorda a Maxwell che l'ordine era di distruggere la nave. Maxwell comincia a sospettare che non si sia mai trattato solo di una nave.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] chiede una scorta per le sue navi fino a [[station/4]]. Maxwell riconosce la banda degli ottopodi, nota per essere piena zeppa di merce rubata, ma accetta finché le autorità restano fuori.", false],
		[8, "Esito", "Quelli che sembravano soldi facili diventano uno scontro con caccia vossk e un incrociatore. Almeno una nave passa, e Maxwell nota che i Vossk stanno diventando più aggressivi.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] ha individuato un incrociatore da battaglia vossk in avaria. La flotta vuole catturarlo e prendere vivo il suo comandante, ma prima bisogna distruggere ogni cannone fisso sul suo scafo.", false],
		[9, "Esito", "Mentre la squadriglia di Christine attira il fuoco, Maxwell elimina i cannoni e la nave viene abbordata.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]] dei Grey ingaggia Maxwell per portare un convoglio di quattro navi fino a [[station/5]], attraverso il territorio vossk, e paga per ogni nave che arriva.", false],
		[10, "Esito", "Gli aggressori non sono Vossk ma navi terrane modificate. Maxwell li respinge e ne conclude che i fuorilegge lavorano con i Vossk.", false],
	],
	"chapter/10": [
		[10, "", "L'[[character/11]] ha bisogno di tutti i piloti disponibili: una stazione degli alleati dei Terrani, i Niveliani, è sotto l'attacco di forti forze vossk. Dopo un aspro scambio sui prezzi e sulle lealtà di Maxwell, l'ammiraglio lo manda in azione.", false],
		[11, "Esito", "Il comandante della stazione [[character/12]] chiede a Maxwell di concentrarsi sugli incrociatori mentre [[character/1|Christine]] si occupa dei caccia. L'attacco è respinto, e i due concordano che i fuorilegge sono il pericolo che resta.", false],
	],
	"chapter/11": [
		[11, "", "Un capoclan vossk, [[character/4]], contatta Maxwell in segreto. Uno dei comandanti vossk cospira con un ufficiale terrano e i fuorilegge, e il clan lo vuole morto. Il posto migliore per un'imboscata è la Nebulosa di Yarapu.", false],
		[12, "Esito", "Maxwell distrugge l'incrociatore del comandante e la sua scorta. Nartok gli rivela che il traditore dalla parte terrana è una vecchia conoscenza di Maxwell, e che la tenente Hammond è già sulle sue tracce.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] porta la notizia: [[character/2]] è il capo dei fuorilegge. Da comandante ha coperto gli attacchi ai trasporti e ha fatto rubare a Lockwood segreti militari da vendere ai Vossk. La sua banda si è barricata in una stazione di fuorilegge protetta da un campo minato, che Maxwell deve sgomberare prima dell'attacco.", false],
		[13, "Esito", "Il campo minato è sgomberato e i difensori della stazione cadono. Christine si lancia contro Vlad, che la abbatte prima che Maxwell possa coprirla, e fugge.", false],
	],
	"chapter/13": [
		[13, "", "L'[[character/11]] porge le sue condoglianze; Maxwell vuole solo sapere dove sia andato Vlad. La flotta ha trovato Vlad e gli ultimi dei suoi fuorilegge, e le sue squadriglie hanno bisogno dell'aiuto di Maxwell per spezzarli.", false],
		[14, "Esito", "Una volta spezzati i fuorilegge, Maxwell lascia la flotta al suo lavoro, insegue Vlad da solo e lo uccide. L'ammiraglio gli offre un posto nella flotta; Maxwell rifiuta. Riceve un motore iperspaziale, che gli apre ogni quadrante della galassia.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell è il pilota del giocatore: un ex pilota della flotta spaziale terrana che, dopo un congedo con onore, riceve una nave dall'[[character/11|ammiraglio Smith]] e inizia una vita da mercenario su [[station/0]].", false],
		[1, "", "È sarcastico e pronto a contrattare i suoi compensi, ma porta a termine i lavori che accetta.", false],
		[7, "", "Protesta quando [[character/2|Vlad Borsikov]] abbatte un uomo che si era arreso.", false],
		[13, "", "La morte di [[character/1|Christine Hammond]] trasforma l'ultimo capitolo in una questione personale.", false],
		[14, "", "Dopo aver ucciso Vlad rifiuta di tornare nella flotta e preferisce scegliere la propria strada nella galassia.", false],
	],
	"character/1": [
		[1, "", "La tenente Christine Hammond della flotta spaziale terrana accoglie Maxwell su [[station/0]], gli mostra la nave e vola con lui il suo primo volo di prova. Gli chiede di chiamarla Christine.", false],
		[5, "", "Lavora anche come agente: su [[station/2]] è sotto copertura per ordine dell'ammiraglio Smith, e coinvolge Maxwell nell'attacco al convoglio di armi vossk.", false],
		[8, "", "Guida la squadriglia che cattura un incrociatore da battaglia vossk in avaria.", false],
		[12, "", "Scopre che dietro i fuorilegge c'è [[character/2|Vlad Borsikov]] e pianifica l'attacco alla loro stazione.", false],
		[13, "", "Dopo la battaglia si lancia contro Vlad e viene abbattuta da lui. La sua morte spinge Maxwell all'inseguimento di Vlad nell'ultimo capitolo.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov è un comandante della flotta spaziale terrana e, per dirla con Maxwell, il tipo peggiore che ci sia. Dà a Maxwell il suo primo lavoro pagato: ripulire un corridoio spaziale dai rottami contro il tempo.", false],
		[7, "", "Abbatte la spia Corsair Lockwood dopo la sua resa e insiste che l'ordine era di distruggere la nave.", false],
		[12, "", "È lui il traditore: il capo dei fuorilegge, che ha usato il suo grado per coprire gli attacchi ai trasporti e ha fatto rubare a Lockwood segreti militari che ha venduto ai Vossk.", false],
		[13, "", "Quando Christine Hammond lo insegue dopo l'attacco alla sua stazione, la abbatte e fugge.", false],
		[14, "", "La flotta lo trova con gli ultimi dei suoi fuorilegge, e Maxwell lo uccide in duello.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon è un cliente agitato che deve raggiungere subito [[station/1]] per salvare un affare, e paga bene un pilota disposto a portarlo attraverso lo spazio vossk.", false],
		[4, "", "Sopravvive all'imboscata vossk e promette di raccomandare Maxwell.", false],
	],
	"character/4": [
		[4, "", "Un Vossk con questo volto chiama Maxwell sulla via per Phoebos e ne pretende la resa in nome dell'Impero vossk.", false],
		[11, "", "Nartok Brek è un capoclan dei [[race/1]]. Contatta Maxwell in segreto perché uno dei suoi stessi comandanti cospira con un ufficiale terrano e i fuorilegge, e chiede di tendere un'imboscata al traditore nella Nebulosa di Yarapu. Prima di dire qualsiasi cosa chiede a Maxwell la sua parola d'onore.", false],
		[12, "", "Dopo l'imboscata rivela a Maxwell che Maxwell conosce già il traditore terrano.", false],
	],
	"character/5": [
		[4, "", "John Washington, che gli amici chiamano Doc, ha bisogno di una scorta per la sua nave fino a [[station/2]]. Offre 3.000 crediti e si accorda per 4.500, a patto che non ci siano testimoni. Maxwell sospetta una consegna di armi per i fuorilegge.", false],
		[5, "", "Il suo carico arriva. Cosa fosse, lo tiene per sé.", false],
	],
	"character/6": [
		[6, "", "Un pilota della squadriglia di Christine Hammond, che chiede via radio se questo Maxwell abbia almeno esperienza di combattimento, senza accorgersi che lui sente.", false],
		[13, "", "La stessa squadriglia resta indietro a mettere in sicurezza la stazione dei fuorilegge mentre Christine e Maxwell inseguono Vlad.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom è l'ufficiale della sicurezza della flotta spaziale. Manda Maxwell sulle tracce della spia [[character/8]], con l'ordine che la nave rubata non cada in mano nemica.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood è una spia fuggita con una delle navi segrete della flotta spaziale.", false],
		[7, "", "Messo alle strette in un campo di asteroidi, si arrende, e Vlad Borsikov lo abbatte comunque.", false],
		[12, "", "In seguito si scopre che era stato proprio Vlad a incaricarlo di rubare segreti militari.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt trasporta merci per la banda degli ottopodi, nota per portare merce rubata. Giura che tutto ciò che è a bordo è perfettamente legale e paga Maxwell per portare le sue navi fino a [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor dei Grey ha sentito parlare di Maxwell e gli offre un lavoro difficile: quattro navi fino a [[station/5]] attraverso il territorio vossk, a 4.000 crediti per ogni nave che arriva.", false],
	],
	"character/11": [
		[1, "", "L'ammiraglio Smith della flotta spaziale terrana ha dato a Maxwell la sua nave dopo il congedo, e incarica la tenente Hammond di mostrargli come usarla.", false],
		[10, "", "Chiama Maxwell quando la stazione niveliana viene attaccata. La conversazione si fa tesa quando Maxwell parla dei suoi prezzi e di quanto potrebbero pagare i Vossk.", false],
		[13, "", "Dopo la morte di Christine porge le sue condoglianze a Maxwell e gli indica dove si trovano i fuorilegge di Vlad.", false],
		[14, "", "Lascia che Maxwell insegua Vlad da solo, gli offre un posto nella flotta e gli dà un motore iperspaziale quando rifiuta.", false],
	],
	"character/12": [
		[11, "", "Botom Krant comanda la stazione niveliana attaccata dai Vossk. Chiede a Maxwell di concentrarsi sugli incrociatori e lo ringrazia quando l'attacco è respinto.", false],
	],
	"race/0": [
		[1, "", "Umani, in guerra con i [[race/1]] nel quarto millennio. Maxwell è un Terrano, e la maggior parte dei clienti della campagna serve nella flotta spaziale terrana. I Terrani possiedono più pianeti e stazioni di qualsiasi altro popolo.", false],
		[1, "", "Molte delle navi in vendita sono progetti terrani: la [[ship/0]], la [[ship/6]] e la sua versione modificata [[ship/7]], e la cannoniera [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "Il nemico dei Terrani. I negozi vossk vendono solo il loro caccia, la [[ship/8]], e sono gli unici a vendere le armi vossk. A un pilota che lavora per i Terrani vengono chieste tangenti nelle stazioni vossk, e viceversa.", false],
	],
	"race/2": [
		[1, "", "Uno dei popoli della galassia, con pianeti e stazioni propri.", false],
	],
	"race/3": [
		[1, "", "Uno dei popoli della galassia, con pianeti e stazioni propri.", false],
	],
	"race/4": [
		[1, "", "I loro componenti speciali finiscono in armi come il [[equipment/23]], e il pesante bombardiere [[ship/3]] è loro.", false],
	],
	"race/5": [
		[1, "", "Le navi grey sono note per la loro corazza pesantissima. La ricognitrice [[ship/9]] viene dalla loro flotta ed è stata adattata da poco a piloti umanoidi, e il missile [[equipment/4]] è costruito con componenti grey. Feknor dei Grey ingaggia Maxwell per un convoglio pericoloso.", false],
	],
	"race/6": [
		[1, "", "Alleati dei Terrani. Il caccia [[ship/1]] è uno sviluppo niveliano, e il laser [[equipment/2]] si basa sulla tecnologia bellica niveliana. L'attacco vossk a una delle loro stazioni trascina Maxwell nella guerra sul serio.", false],
	],
	"race/7": [
		[1, "", "Uno dei popoli della galassia, con pianeti e stazioni propri.", false],
	],
	"race/8": [
		[1, "", "Uno dei popoli della galassia, con pianeti e stazioni propri.", false],
	],
	"race/9": [
		[1, "", "I fuorilegge non sono un popolo ma uno stile di vita: pirati e contrabbandieri con pianeti e stazioni propri. I loro negozi sono gli unici a vendere la [[ship/7]], e [[station/2]] è il loro covo più noto.", false],
	],
	"galaxy": [
		[1, "", "Quattro quadranti, cento sistemi e cinquecento pianeti e stazioni. Ogni quadrante è più difficile del precedente: i suoi lavori pagano di più, i suoi nemici sono più duri e i suoi negozi vendono equipaggiamento migliore.", false],
		[1, "", "Volare all'interno di un quadrante costa crediti in base alla distanza; passare al quadrante vicino o a quello opposto costa un supplemento. Dopo aver visitato ogni luogo della galassia, viaggiare è gratis.", false],
	],
	"progress/ranks": [
		[1, "Reputazione", "La reputazione conta i nemici che hai distrutto. Ogni soglia della tabella qui sotto alza il tuo grado, mostrato nella schermata Stato.", false],
		[1, "Livello", "Il tuo livello cresce con il denaro guadagnato da missioni e lavori. Quando i tuoi guadagni totali superano 1,6 volte quelli del tuo ultimo livello, raggiungi il successivo. Livelli più alti rendono più duri i nemici delle tue missioni.", false],
	],
	"progress/milestones": [
		[1, "", "Quando attracchi, la stazione ti accoglie con un messaggio la prima volta che i tuoi crediti superano un traguardo o la tua esplorazione della galassia raggiunge un nuovo livello. I messaggi qui sotto sono quelli del gioco.", false],
		[1, "Ricchezza", "La ricchezza è più di un numero. Con più di 999.999 crediti puoi commerciare su ogni pianeta e stazione: l'hangar si apre anche dove non c'è commercio, e lì puoi comprare, vendere merci e bottino e riequipaggiare la nave.", false],
		[1, "Esplorazione", "Ogni luogo visitato conta. Visitarli tutti e cinquecento rende gratuito ogni viaggio.", false],
	],
	"progress/loyalty": [
		[1, "", "La tua lealtà si trova da qualche parte tra Terrani e Vossk, indicata dal cursore nella schermata Stato. Ogni missione per un cliente terrano la sposta di un passo verso i Terrani; ogni missione per un cliente vossk, di un passo verso i Vossk. Non può andare oltre dieci passi in nessuna direzione.", false],
		[1, "", "Se viaggi verso un luogo terrano mentre la tua lealtà pende verso i Vossk, o verso un luogo vossk mentre pende verso i Terrani, ti viene chiesta una tangente oltre al costo del volo: 150 crediti per ogni passo. Pagare una tangente riporta la tua lealtà di un passo verso il centro.", false],
	],
	"mode/survival": [
		[1, "", "Sopravvivenza è una modalità separata, con il suo pilota e la sua classifica dei punteggi. Sceglila in Avvia gioco. Le navi nemiche continuano ad arrivare, ogni abbattimento dà punti e ripara lo scafo, e il colore dei riquadri di un nemico ne indica la forza. Il tuo punteggio ti fa guadagnare un grado dalla tabella qui sotto.", false],
	],
	"mode/swarm": [
		[1, "", "Sciame è una modalità scritta per questo remake, che trovi in Avvia gioco. Inizia con una manciata di caccia e cresce fino a una folla che si stringe da ogni lato, con ondate dopo il quinto minuto.", false],
		[1, "", "Ogni abbattimento riempie la barra del livello. Ogni livello offre tre carte di potenziamento: una nuova arma, una versione migliore di una che hai, una bocca da fuoco in più, più gittata o velocità dei proiettili, uno scudo più forte, riparazioni a ogni abbattimento o uno scafo diverso. Rifiutare una carta ripara invece un quarto del tuo scafo.", false],
		[1, "", "Armi, scudi e scafi sono quelli del tuo file di gioco. Raggiungere un grado nella classifica di Sopravvivenza sblocca lo scafo successivo per Sciame.", false],
	],
	"guide/start": [
		[1, "", "Dopo l'importazione del file di gioco, Avvia gioco offre la campagna, l'esplorazione libera, Sopravvivenza e Sciame. La campagna inizia su [[station/0]] con una [[ship/0]] e 5.000 crediti.", false],
		[1, "Il menu della stazione", "In una stazione, Info descrive il luogo, Hangar apre il negozio e la tua nave, Missioni mostra la bacheca dei lavori e Mappa ti permette di viaggiare. Durante la campagna bacheca e mappa restano bloccate, e Avanti avvia il briefing successivo. Stato mostra livello, reputazione, tempo di gioco, abbattimenti e lealtà, e Menu contiene le opzioni e il salvataggio.", false],
		[1, "", "Non tutti i luoghi hanno un hangar aperto a tutti: senza commercio, l'hangar si apre solo durante la campagna o quando hai più di 999.999 crediti.", false],
	],
	"guide/flight": [
		[1, "", "I waypoint sono segnati in giallo, gli alleati in verde e i nemici in rosso. Gli oggetti fuori dalla tua visuale compaiono sul bordo dello schermo. La forza rimanente di un nemico è indicata sotto il suo segnalino.", false],
		[1, "", "Lo scudo assorbe collisioni e colpi e si ricarica col tempo; quando è esaurito, i danni vanno allo scafo. Il boost dà un breve scatto di velocità e ha bisogno di tempo per ricaricarsi.", false],
		[1, "Comandi", "Con la tastiera, guida con il mouse o le frecce, regola la spinta con W e S e spostati di lato con A e D. Spara con un clic o Spazio, cambia arma con Q, lancia missili con F e usa il boost con Maiusc. R attiva il pilota automatico, T accelera il tempo nei tratti sicuri, E attracca vicino a una stazione ed Esc mette in pausa. Un controller mira con lo stick destro e spara con il grilletto destro. I comandi touch hanno uno stick, una manetta e pulsanti per fuoco, missili, boost e navigazione; un doppio tocco su Fuoco attiva il fuoco automatico.", false],
		[1, "Pilota automatico e tempo", "Il pilota automatico vola fino al prossimo waypoint o alla stazione. Finché nulla ti minaccia, il tempo può scorrere più veloce; nemici, danni o l'arrivo a destinazione lo riportano alla normalità.", false],
	],
	"guide/weapons": [
		[1, "", "Le navi hanno supporti per cinque tipi di arma: laser, cannoni al plasma, cannoni fotonici, missili e cannoni termici. Ogni supporto regge un'arma, e ogni nave ha il proprio insieme di supporti. Un generatore di scudo va bene per ogni nave.", false],
		[1, "", "Laser e cannoni al plasma sparano rapidamente a media distanza. I cannoni fotonici arrivano più lontano e colpiscono più forte per colpo, ma si ricaricano lentamente. I cannoni termici spruzzano particelle a distanza ravvicinata con una cadenza altissima. I missili si lanciano con un pulsante dedicato, senza cambiare arma, e infliggono danni pesanti con una ricarica lunga.", false],
		[1, "", "Gli scudi differiscono per capacità e velocità di ricarica. Le armi più potenti si vendono solo dal secondo quadrante in poi, e le armi vossk solo nei negozi vossk.", false],
	],
	"guide/hangar": [
		[1, "", "L'hangar ha tre parti: Nave mostra la tua nave con le armi montate e lo scudo, Carico contiene le tue merci e l'equipaggiamento di riserva, e Shop offre la merce della stazione.", false],
		[1, "", "L'equipaggiamento acquistato finisce nella stiva; installalo da lì se la tua nave ha un supporto libero. Equipaggiamento e navi si rivendono a metà prezzo.", false],
		[1, "", "Comprare una nave dà in permuta quella attuale. L'equipaggiamento compatibile con la nuova nave resta montato e il resto passa nella stiva, finché c'è spazio.", false],
		[1, "", "I negozi vendono da una a quattro armi o scudi e fino a tre navi, scelti tra ciò che il quadrante e il popolo del luogo consentono. La merce di un negozio si rinnova quando torni dopo aver volato altrove. Durante la campagna ogni capitolo ha la sua merce fissa.", false],
	],
	"guide/trade": [
		[1, "", "Le merci provengono dai rottami delle navi distrutte e finiscono nella stiva dopo la missione. Vendile nella sezione carico dell'hangar. Alcune rendono di più dove la tecnologia è bassa, altre dove è alta, altre allo stesso prezzo ovunque; ogni pagina di merce elenca il prezzo a ogni livello tecnologico.", false],
		[1, "", "I negozi non hanno merci proprie. Ciò che vendi in un negozio resta nella sua merce, e puoi ricomprarlo lì allo stesso prezzo.", false],
		[1, "", "Il commercio richiede un hangar: pianeti e stazioni senza commercio aprono il loro solo ai piloti con più di 999.999 crediti.", false],
	],
	"guide/travel": [
		[1, "", "La mappa mostra la galassia, i suoi quadranti e sistemi. Scegli un luogo e viaggia lì per il costo di volo indicato, più una tangente se la tua lealtà è contraria al suo popolo. Arrivi già attraccato.", false],
		[1, "", "Il costo del volo cresce con la distanza. Cambiare quadrante aggiunge 15.000 crediti alla tariffa, e 30.000 per il quadrante opposto. La mappa mostra quanta parte della galassia hai esplorato; con ogni luogo visitato, viaggiare non costa nulla.", false],
		[1, "", "La galassia si apre quando la campagna è completata o quando la salti.", false],
	],
	"guide/jobs": [
		[1, "", "Fuori dalla campagna, la bacheca di ogni stazione offre alcuni lavori di clienti di popoli diversi. Ognuno mostra difficoltà e ricompensa; i lavori difficili pagano di più, e così i quadranti più lontani.", false],
		[1, "", "Ogni tanto un truffatore losco offre un lavoro che paga il quaranta per cento in più del solito. Un lavoro completato paga la sua ricompensa e sposta la tua lealtà verso il popolo del cliente.", false],
	],
	"guide/campaign": [
		[1, "", "La campagna è una sequenza di tredici missioni. Una missione riuscita paga la sua ricompensa; una fallita si può ritentare. Una volta completata, il motore iperspaziale apre la galassia, e bacheca dei lavori e mappa diventano disponibili.", false],
		[1, "", "Salta campagna · Esplora, nel menu iniziale o in quello della stazione, porta subito all'esplorazione libera. Saltarla non dà ricompense di completamento e mantiene il tuo pilota della campagna nel suo slot.", false],
	],
	"guide/saves": [
		[1, "", "Il gioco salva automaticamente dopo ogni missione e ai checkpoint. Campagna, esplorazione, Sopravvivenza e Sciame hanno salvataggi separati. Carica / ripristina nel menu di pausa, o Carica dopo una sconfitta, riporta all'ultimo salvataggio automatico, all'inizio del volo o all'ultima stazione.", false],
		[1, "", "File del gioco → Trasferisci salvataggi sposta i tuoi salvataggi su un altro dispositivo che ha importato lo stesso file di gioco.", false],
	],
	"guide/tips": [
		[1, "", "Vendi le merci raccolte dai relitti prima di comprare equipaggiamento; sulle navi piccole la stiva si riempie in fretta.", true],
		[1, "", "Controlla i supporti di una nave prima di comprarle armi: un'arma senza supporto adatto resta nella stiva.", true],
		[1, "", "Tieni le merci finché non attracchi dove il livello tecnologico le favorisce.", true],
		[1, "", "Volare per una sola parte rende costose le visite alle stazioni dell'altra.", true],
		[1, "", "Visita luoghi nuovi quando viaggi comunque: esplorare tutta la galassia rende gratuito ogni viaggio.", true],
	],
}
