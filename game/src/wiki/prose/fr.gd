extends RefCounted
## The reference's own writing in French. Same blocks, chapter gates and links
## as prose/en.gd; see there for the format.

const PAGES := {
	"home": {"title": "Référence"},
	"world/setting": {"title": "Une galaxie en guerre"},
	"world/fleet": {"title": "La flotte spatiale terranienne"},
	"world/outlaws": {"title": "Hors-la-loi et pirates"},
	"chapter/1": {"title": "Un nouveau vaisseau"},
	"chapter/2": {"title": "Débris spatiaux"},
	"chapter/3": {"title": "Passage vers Phoebos"},
	"chapter/4": {"title": "La cargaison de Doc"},
	"chapter/5": {"title": "Le convoi d'armes"},
	"chapter/6": {"title": "L'espion en fuite"},
	"chapter/7": {"title": "Marchandises sensibles"},
	"chapter/8": {"title": "À l'abordage du géant"},
	"chapter/9": {"title": "Quatre vaisseaux pour Opos"},
	"chapter/10": {"title": "Le front nivelien"},
	"chapter/11": {"title": "Embuscade dans la nébuleuse"},
	"chapter/12": {"title": "La station des hors-la-loi"},
	"chapter/13": {"title": "Vengeance"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Pilote mercenaire"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Lieutenant de la flotte spatiale"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Commandant de la flotte spatiale"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Passager pressé"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Chef de clan vossk", "early_title": "Pilote vossk"},
	"character/5": {"title": "John « Doc » Washington", "subtitle": "Marchand"},
	"character/6": {"title": "Pilote d'escadrille", "subtitle": "Flotte spatiale"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Officier de sécurité"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Espion en fuite"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Marchand octopode"},
	"character/10": {"title": "Feknor", "subtitle": "Des Grey"},
	"character/11": {"title": "Amiral Smith", "subtitle": "Flotte spatiale terranienne"},
	"character/12": {"title": "Botom Krant", "subtitle": "Commandant de station nivelien"},
	"progress/ranks": {"title": "Réputation et niveau"},
	"progress/milestones": {"title": "Étapes"},
	"progress/loyalty": {"title": "Loyauté et pots-de-vin"},
	"mode/survival": {"title": "Survie", "subtitle": "Mode de jeu"},
	"mode/swarm": {"title": "Essaim", "subtitle": "Mode de jeu du remake"},
	"guide/start": {"title": "Premiers pas"},
	"guide/flight": {"title": "Voler et combattre"},
	"guide/weapons": {"title": "Armes et boucliers"},
	"guide/hangar": {"title": "Le hangar"},
	"guide/trade": {"title": "Commerce et butin"},
	"guide/travel": {"title": "Voyages et carte"},
	"guide/jobs": {"title": "Le tableau des contrats"},
	"guide/campaign": {"title": "Campagne et exploration libre"},
	"guide/saves": {"title": "Sauvegarder et charger"},
	"guide/tips": {"title": "Conseils"},
}

const BLOCKS := {
	"home": [
		[1, "", "Cette référence décrit votre propre exemplaire de Galaxy on Fire : chaque planète et station de la galaxie, les vaisseaux, armes et marchandises de ses boutiques, les contrats de ses tableaux, les personnages de son histoire et les règles du commerce, des voyages et de la réputation. Les noms, descriptions et dialogues viennent du fichier de jeu que vous avez importé ; les chiffres suivent les règles de ce remake.", false],
		[1, "", "Les pages de l'histoire s'étoffent avec votre campagne. Les chapitres que vous n'avez pas atteints et les personnes que vous n'avez pas rencontrées restent hors de la référence, et le dénouement d'un chapitre n'apparaît qu'une fois celui-ci joué.", false],
	],
	"intro/world": [
		[1, "", "L'univers du jeu : la guerre entre Terraniens et Vossk, la flotte spatiale que Keith Maxwell vient de quitter et les hors-la-loi qui s'en prennent aux deux camps.", false],
	],
	"intro/story": [
		[1, "", "La campagne est une suite linéaire de treize chapitres. Chacun commence par un briefing dans une station et se poursuit par un vol ponctué d'appels radio. Les chapitres ci-dessous vont aussi loin que votre pilote.", false],
	],
	"intro/characters": [
		[1, "", "Les personnes qui parlent à Keith Maxwell lors des briefings et par radio. Chaque portrait provient des graphismes du jeu.", false],
	],
	"intro/races": [
		[1, "", "Dix peuples vivent sur les planètes et stations de la galaxie. Les habitants d'un lieu décident des vaisseaux que sa boutique peut vendre et, pour les Terraniens et les Vossk, si votre loyauté vous coûte un pot-de-vin quand vous vous y rendez.", false],
	],
	"intro/galaxy": [
		[1, "", "La galaxie est divisée en quatre quadrants de vingt-cinq systèmes, et chaque système compte cinq planètes ou stations. La carte ci-dessous les montre toutes ; les voyages entre elles s'ouvrent à la fin de la campagne, ou tout de suite si vous la passez.", false],
	],
	"intro/stations": [
		[1, "", "Les cinq cents planètes et stations. Le niveau technologique d'un lieu fixe ses prix de cargaison et ses remises sur les vaisseaux ; seuls les lieux commerçants ont un hangar ouvert à tous.", false],
	],
	"intro/ships": [
		[1, "", "Les vaisseaux que vous pouvez acheter. Coque, soute et supports d'armes les distinguent ; les boutiques de la plupart des peuples les vendent tous sauf le chasseur vossk, que seuls les Vossk vendent.", false],
	],
	"intro/equipment": [
		[1, "", "Armes et générateurs de bouclier. Un vaisseau ne peut porter une arme que s'il a un support pour ce type d'arme, et une seule arme de chaque type à la fois.", false],
	],
	"intro/goods": [
		[1, "", "Cargaison trouvée dans les débris des vaisseaux détruits. Chaque marchandise suit sa propre règle selon laquelle le niveau technologique d'une station change son prix.", false],
	],
	"intro/jobs": [
		[1, "", "Les types de travail proposés au tableau des contrats une fois la galaxie ouverte. La récompense dépend du contrat et du quadrant où vous êtes.", false],
	],
	"intro/progress": [
		[1, "", "Comment le jeu mesure votre pilote : réputation par les destructions, niveau par les gains, loyauté entre Terraniens et Vossk, et les messages qui saluent votre richesse et votre exploration.", false],
	],
	"intro/modes": [
		[1, "", "D'autres façons de jouer en plus de la campagne et de l'exploration libre.", false],
	],
	"intro/guide": [
		[1, "", "Comment jouer : voler, combattre, s'équiper, commercer, voyager et gravir les échelons.", false],
	],
	"world/setting": [
		[1, "", "Au quatrième millénaire, les Terraniens mènent une guerre interplanétaire contre les [[race/1]]. D'autres peuples partagent la galaxie avec eux : certains alliés à un camp, d'autres commerçant avec les deux, d'autres à peine connus.", false],
		[1, "", "Le jeu commence en 3587 à [[station/0]], une station terranienne, où le croiseur de combat SS Ulysses dépose [[character/0]]. Après une libération honorable de la flotte spatiale, il a reçu son propre vaisseau de l'[[character/11|amiral Smith]] et compte gagner sa vie comme mercenaire.", false],
		[1, "Où cela se passe", "Toute la campagne se déroule dans le premier quadrant, [[quadrant/0]], près de [[station/0]]. Le reste de la galaxie s'ouvre une fois l'histoire terminée.", false],
		[14, "Après la guerre", "Le meneur des hors-la-loi est mort, un moteur hyperspatial est à bord, et Maxwell refuse une place dans la flotte. La galaxie est à lui : à explorer, à commercer et à combattre pour qui paie.", false],
	],
	"world/fleet": [
		[1, "", "La flotte spatiale terranienne est l'armée des mondes terraniens. Maxwell y a servi avant le début du jeu, et la plupart de ses missions de campagne viennent de ses officiers ou de leur entourage.", false],
		[1, "", "Son chasseur standard est le [[ship/6]]. Parmi ses officiers dans l'histoire figurent [[character/1]], qui montre à Maxwell son nouveau vaisseau, et l'[[character/11|amiral Smith]], qui le lui a donné.", false],
		[5, "", "La flotte emploie aussi des agents. Le lieutenant Hammond travaille sous couverture sur [[station/2]] sur ordre de l'amiral.", false],
		[6, "", "L'officier de sécurité [[character/7]] traque les traîtres au sein de la flotte.", false],
		[12, "", "Tous ses commandants ne sont pas loyaux : l'un d'eux traite avec les Vossk et les hors-la-loi dans le dos de la flotte.", false],
	],
	"world/outlaws": [
		[9, "", "Les hors-la-loi pilotent des vaisseaux terraniens modifiés et attaquent les convois. Quand ils tendent une embuscade à un convoi grey en plein territoire vossk, il devient clair qu'ils travaillent avec les Vossk.", false],
		[12, "", "Les hors-la-loi ont un chef au sein même de la flotte spatiale, qui a vendu des secrets militaires volés aux Vossk et couvert les attaques contre les transports. Ils se retranchent dans leur propre station derrière un champ de mines.", false],
		[1, "", "Les hors-la-loi ont aussi leur propre peuple sur la carte de la galaxie : les lieux habités par les [[race/9]] sont leurs stations et planètes. Leurs boutiques sont les seules à vendre le [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell arrive à [[station/0]] et est accueilli par le lieutenant [[character/1]], qui a ordre de l'amiral Smith de lui montrer son nouveau vaisseau, un vieil éclaireur [[ship/0]]. Elle lui explique le hangar : vaisseaux, armes et équipement s'achètent au Shop, et la cargaison ramassée dans l'espace se vend depuis la soute.", false],
		[1, "", "Vient ensuite un vol d'essai. Christine le guide entre les points de passage, explique les boucliers, le changement d'arme, le tir et le boost, puis lance quelques drones d'entraînement à abattre.", false],
		[2, "Dénouement", "Maxwell détruit les drones et revient à la station. Christine lui souhaite bonne chance et espère le revoir en un seul morceau.", false],
	],
	"chapter/2": [
		[2, "", "Un visage importun de la flotte : le commandant [[character/2]], que Maxwell n'a jamais pu supporter, a un travail pour lui. Un couloir spatial près de la station doit être dégagé de ses débris avant l'arrivée du prochain convoi, et il n'y a que deux minutes pour le faire.", false],
		[3, "Dénouement", "Le couloir est dégagé à temps et Vlad paie, en remarquant que Maxwell était fait pour ce travail.", false],
	],
	"chapter/3": [
		[3, "", "Un petit client nerveux, [[character/3]], veut être emmené à [[station/1]] sur-le-champ, avant qu'une de ses affaires ne tombe à l'eau. L'endroit grouille de Vossk, mais il paie bien et Maxwell accepte.", false],
		[4, "Dénouement", "En route, une patrouille vossk exige leur reddition. Maxwell fait passer Bolar, et le passager promet de le recommander dès qu'il aura cessé de trembler.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] a besoin d'une escorte pour son vaisseau jusqu'à [[station/2]], le repaire des pirates. Maxwell fait monter le prix à cause du risque et soupçonne une nouvelle livraison d'armes pour les hors-la-loi.", false],
		[5, "Dénouement", "Des chasseurs vossk s'en prennent deux fois au cargo. Il atteint Tortuga, et Doc fait comprendre que ce qu'il transportait ne regarde pas Maxwell.", false],
	],
	"chapter/5": [
		[5, "", "Sur Tortuga, Maxwell tombe sur [[character/1]], qui s'y trouve sous couverture. La flotte a l'ordre d'intercepter un convoi d'armes vossk près de [[station/3]] ; si la livraison passe, ce sera un massacre. Son escadrille a besoin d'un pilote expérimenté de plus.", false],
		[6, "Dénouement", "L'escorte tombe d'abord, puis les cargos. Le convoi est arrêté, et Christine s'attend à ce que l'amiral Smith soit satisfait.", false],
	],
	"chapter/6": [
		[6, "", "L'officier de sécurité [[character/7]] a une mission qui ne doit pas échouer : [[character/8]], un espion, s'est enfui avec l'un des vaisseaux secrets de la flotte. Il ne doit pas tomber aux mains de l'ennemi et, s'il le faut, doit être détruit.", false],
		[7, "Dénouement", "Maxwell trouve Lockwood dans un champ d'astéroïdes et endommage son vaisseau jusqu'à ce qu'il se rende. Avant que quiconque puisse l'arrêter, [[character/2|Vlad Borsikov]] l'abat et rappelle à Maxwell que l'ordre était de détruire le vaisseau. Maxwell commence à soupçonner qu'il ne s'agissait jamais seulement d'un vaisseau.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] demande une escorte pour ses vaisseaux jusqu'à [[station/4]]. Maxwell reconnaît la bande des Octopodes, connue pour être bourrée de marchandises volées, mais accepte tant que les autorités restent en dehors.", false],
		[8, "Dénouement", "Ce qui commence comme de l'argent facile tourne au combat contre des chasseurs vossk et un croiseur. Au moins un vaisseau passe, et Maxwell note que les Vossk deviennent plus agressifs.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] a repéré un croiseur de combat vossk hors d'état de manœuvrer. La flotte veut le capturer et prendre son commandant vivant, mais il faut d'abord détruire chaque canon fixe de sa coque.", false],
		[9, "Dénouement", "Pendant que l'escadrille de Christine attire le feu, Maxwell neutralise les canons, et le vaisseau est pris à l'abordage.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]] des Grey engage Maxwell pour mener un convoi de quatre vaisseaux jusqu'à [[station/5]], droit à travers le territoire vossk, et paie pour chaque vaisseau qui arrive.", false],
		[10, "Dénouement", "Les assaillants ne sont pas des Vossk mais des vaisseaux terraniens modifiés. Maxwell les repousse et en conclut que les hors-la-loi travaillent avec les Vossk.", false],
	],
	"chapter/10": [
		[10, "", "L'[[character/11]] a besoin de tous les pilotes disponibles : une station des alliés des Terraniens, les Niveliens, est attaquée par d'importantes forces vossk. Après un échange tendu sur les tarifs et les loyautés de Maxwell, l'amiral l'envoie au combat.", false],
		[11, "Dénouement", "Le commandant de station [[character/12]] demande à Maxwell de se concentrer sur les croiseurs pendant que [[character/1|Christine]] s'occupe des chasseurs. L'attaque est repoussée, et tous deux conviennent que les hors-la-loi sont le danger qui reste.", false],
	],
	"chapter/11": [
		[11, "", "Un chef de clan vossk, [[character/4]], contacte Maxwell en secret. L'un des commandants vossk conspire avec un officier terranien et les hors-la-loi, et le clan veut sa mort. Le meilleur endroit pour une embuscade est la nébuleuse de Yarapu.", false],
		[12, "Dénouement", "Maxwell détruit le croiseur du commandant et son escorte. Nartok lui apprend que le traître côté terranien est une vieille connaissance de Maxwell, et que le lieutenant Hammond est déjà sur sa piste.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] apporte la nouvelle : [[character/2]] est le meneur des hors-la-loi. En tant que commandant, il a couvert les attaques contre les transports et fait voler des secrets militaires par Lockwood pour les vendre aux Vossk. Sa bande s'est barricadée dans une station de hors-la-loi protégée par un champ de mines, que Maxwell doit dégager avant l'assaut.", false],
		[13, "Dénouement", "Le champ de mines est dégagé et les défenseurs de la station tombent. Christine fonce sur Vlad, qui l'abat avant que Maxwell puisse la couvrir, et s'échappe.", false],
	],
	"chapter/13": [
		[13, "", "L'[[character/11]] présente ses condoléances ; Maxwell veut seulement savoir où Vlad est parti. La flotte a retrouvé Vlad et les derniers de ses hors-la-loi, et ses escadrilles ont besoin de Maxwell pour les briser.", false],
		[14, "Dénouement", "Une fois les hors-la-loi brisés, Maxwell laisse la flotte à sa tâche, poursuit Vlad seul et le tue. L'amiral lui offre une place dans la flotte ; Maxwell refuse. Il reçoit un moteur hyperspatial, qui lui ouvre tous les quadrants de la galaxie.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell est le pilote du joueur : un ancien pilote de la flotte spatiale terranienne qui, après une libération honorable, reçoit un vaisseau de l'[[character/11|amiral Smith]] et commence une vie de mercenaire à [[station/0]].", false],
		[1, "", "Il est sarcastique et prompt à marchander ses honoraires, mais il termine les missions qu'il accepte.", false],
		[7, "", "Il proteste quand [[character/2|Vlad Borsikov]] abat un homme qui s'était rendu.", false],
		[13, "", "La mort de [[character/1|Christine Hammond]] fait du dernier chapitre une affaire personnelle.", false],
		[14, "", "Après avoir tué Vlad, il refuse de retourner dans la flotte et préfère choisir sa propre voie à travers la galaxie.", false],
	],
	"character/1": [
		[1, "", "Le lieutenant Christine Hammond, de la flotte spatiale terranienne, accueille Maxwell à [[station/0]], lui montre son vaisseau et effectue avec lui son premier vol d'essai. Elle lui demande de l'appeler Christine.", false],
		[5, "", "Elle est aussi agent : sur [[station/2]], elle est sous couverture sur ordre de l'amiral Smith, et elle associe Maxwell à l'attaque du convoi d'armes vossk.", false],
		[8, "", "Elle mène l'escadrille qui capture un croiseur de combat vossk hors d'état de manœuvrer.", false],
		[12, "", "Elle découvre que [[character/2|Vlad Borsikov]] est derrière les hors-la-loi et prépare l'assaut contre leur station.", false],
		[13, "", "Elle fonce sur Vlad après la bataille et il l'abat. Sa mort lance Maxwell à la poursuite de Vlad dans le dernier chapitre.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov est commandant de la flotte spatiale terranienne et, selon Maxwell, le pire type qui s'y trouve. Il donne à Maxwell son premier travail payé : dégager un couloir spatial de ses débris contre la montre.", false],
		[7, "", "Il abat l'espion Corsair Lockwood après sa reddition et insiste sur le fait que l'ordre était de détruire le vaisseau.", false],
		[12, "", "C'est lui le traître : le meneur des hors-la-loi, qui s'est servi de son grade pour couvrir les attaques contre les transports et a fait voler par Lockwood des secrets militaires qu'il a vendus aux Vossk.", false],
		[13, "", "Quand Christine Hammond le poursuit après l'assaut contre sa station, il l'abat et s'échappe.", false],
		[14, "", "La flotte le retrouve avec les derniers de ses hors-la-loi, et Maxwell le tue en duel.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon est un client agité qui doit gagner [[station/1]] immédiatement pour sauver une affaire, et paie bien un pilote prêt à lui faire traverser l'espace vossk.", false],
		[4, "", "Il survit à l'embuscade vossk et promet de recommander Maxwell.", false],
	],
	"character/4": [
		[4, "", "Un Vossk avec ce visage hèle Maxwell en route vers Phoebos et exige sa reddition au nom de l'Empire vossk.", false],
		[11, "", "Nartok Brek est un chef de clan des [[race/1]]. Il contacte Maxwell en secret parce qu'un de ses propres commandants conspire avec un officier terranien et les hors-la-loi, et demande qu'on tende une embuscade au traître dans la nébuleuse de Yarapu. Il exige la parole d'honneur de Maxwell avant de dire quoi que ce soit.", false],
		[12, "", "Après l'embuscade, il révèle à Maxwell que celui-ci connaît déjà le traître terranien.", false],
	],
	"character/5": [
		[4, "", "John Washington, que ses amis appellent Doc, a besoin d'une escorte pour son vaisseau jusqu'à [[station/2]]. Il offre 3 000 crédits et se résout à 4 500, à condition qu'il n'y ait pas de témoins. Maxwell soupçonne une livraison d'armes pour les hors-la-loi.", false],
		[5, "", "Sa cargaison arrive. Ce qu'elle contenait, il le garde pour lui.", false],
	],
	"character/6": [
		[6, "", "Un pilote de l'escadrille de Christine Hammond, qui demande par radio si ce Maxwell a seulement l'expérience du combat, sans remarquer qu'il l'entend.", false],
		[13, "", "La même escadrille reste en arrière pour sécuriser la station des hors-la-loi pendant que Christine et Maxwell poursuivent Vlad.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom est l'officier de sécurité de la flotte spatiale. Il envoie Maxwell aux trousses de l'espion [[character/8]], avec l'ordre que le vaisseau volé ne tombe pas aux mains de l'ennemi.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood est un espion qui s'est enfui avec l'un des vaisseaux secrets de la flotte spatiale.", false],
		[7, "", "Acculé dans un champ d'astéroïdes, il se rend, et Vlad Borsikov l'abat malgré tout.", false],
		[12, "", "On apprend plus tard que c'est Vlad qui l'avait chargé de voler des secrets militaires.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt transporte du fret pour la bande des Octopodes, connue pour convoyer des marchandises volées. Il assure que tout ce qui est à bord est parfaitement légal et paie Maxwell pour mener ses vaisseaux jusqu'à [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor des Grey a entendu parler de Maxwell et lui propose un travail difficile : quatre vaisseaux jusqu'à [[station/5]] à travers le territoire vossk, à 4 000 crédits par vaisseau arrivé.", false],
	],
	"character/11": [
		[1, "", "L'amiral Smith, de la flotte spatiale terranienne, a donné son vaisseau à Maxwell après sa libération et charge le lieutenant Hammond de lui apprendre à s'en servir.", false],
		[10, "", "Il fait appel à Maxwell quand la station nivelienne est attaquée. Leur conversation se tend quand Maxwell parle de ses tarifs et de ce que les Vossk pourraient payer.", false],
		[13, "", "Après la mort de Christine, il présente ses condoléances à Maxwell et lui indique où se trouvent les hors-la-loi de Vlad.", false],
		[14, "", "Il laisse Maxwell poursuivre Vlad seul, lui offre une place dans la flotte et lui donne un moteur hyperspatial quand il refuse.", false],
	],
	"character/12": [
		[11, "", "Botom Krant commande la station nivelienne attaquée par les Vossk. Il demande à Maxwell de se concentrer sur les croiseurs et le remercie une fois l'attaque repoussée.", false],
	],
	"race/0": [
		[1, "", "Des humains, en guerre contre les [[race/1]] au quatrième millénaire. Maxwell est terranien, et la plupart des clients de la campagne servent la flotte spatiale terranienne. Les Terraniens possèdent plus de planètes et de stations que tout autre peuple.", false],
		[1, "", "Beaucoup des vaisseaux en vente sont de conception terranienne : le [[ship/0]], le [[ship/6]] et son dérivé modifié le [[ship/7]], ainsi que la canonnière [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "L'ennemi des Terraniens. Les boutiques vossk ne vendent que leur propre chasseur, le [[ship/8]], et sont les seules à vendre les armes vossk. Un pilote qui travaille pour les Terraniens doit verser des pots-de-vin dans les stations vossk, et inversement.", false],
	],
	"race/2": [
		[1, "", "L'un des peuples de la galaxie, avec ses propres planètes et stations.", false],
	],
	"race/3": [
		[1, "", "L'un des peuples de la galaxie, avec ses propres planètes et stations.", false],
	],
	"race/4": [
		[1, "", "Leurs composants spéciaux entrent dans des armes comme le [[equipment/23]], et le lourd bombardier [[ship/3]] est le leur.", false],
	],
	"race/5": [
		[1, "", "Les vaisseaux grey sont connus pour leur blindage extrêmement lourd. L'éclaireur [[ship/9]] vient de leur flotte et n'a été adapté que récemment aux pilotes humanoïdes, et le missile [[equipment/4]] est fabriqué avec des composants grey. Feknor des Grey engage Maxwell pour un convoi dangereux.", false],
	],
	"race/6": [
		[1, "", "Alliés des Terraniens. Le chasseur [[ship/1]] est un développement nivelien, et le laser [[equipment/2]] repose sur la technologie d'armement nivelienne. L'attaque vossk contre l'une de leurs stations entraîne Maxwell pour de bon dans la guerre.", false],
	],
	"race/7": [
		[1, "", "L'un des peuples de la galaxie, avec ses propres planètes et stations.", false],
	],
	"race/8": [
		[1, "", "L'un des peuples de la galaxie, avec ses propres planètes et stations.", false],
	],
	"race/9": [
		[1, "", "Les hors-la-loi ne sont pas un peuple mais un mode de vie : pirates et contrebandiers qui possèdent leurs propres planètes et stations. Leurs boutiques sont les seules à vendre le [[ship/7]], et [[station/2]] est leur repaire le plus connu.", false],
	],
	"galaxy": [
		[1, "", "Quatre quadrants, cent systèmes et cinq cents planètes et stations. Chaque quadrant est plus difficile que le précédent : ses contrats paient davantage, ses ennemis sont plus coriaces et ses boutiques vendent un meilleur équipement.", false],
		[1, "", "Voler au sein d'un quadrant coûte des crédits selon la distance ; passer dans le quadrant voisin ou le quadrant opposé coûte un supplément. Une fois tous les lieux de la galaxie visités, les voyages sont gratuits.", false],
	],
	"progress/ranks": [
		[1, "Réputation", "La réputation compte les ennemis que vous avez détruits. Chaque seuil du tableau ci-dessous élève votre rang, affiché à l'écran État.", false],
		[1, "Niveau", "Votre niveau augmente avec l'argent gagné grâce aux missions et aux contrats. Dès que vos gains totaux dépassent 1,6 fois leur montant à votre dernier niveau, vous passez au suivant. Des niveaux plus élevés rendent les ennemis de vos missions plus coriaces.", false],
	],
	"progress/milestones": [
		[1, "", "Quand vous vous amarrez, la station vous accueille par un message la première fois que vos crédits franchissent une étape ou que votre exploration de la galaxie atteint un nouveau palier. Les messages ci-dessous sont ceux du jeu.", false],
		[1, "Richesse", "La richesse n'est pas qu'un chiffre. Avec plus de 999 999 crédits, vous pouvez commercer sur chaque planète et station : le hangar s'ouvre même là où il n'y a pas de commerce, et vous pouvez y acheter, vendre votre cargaison et votre butin, et rééquiper votre vaisseau.", false],
		[1, "Exploration", "Chaque lieu visité compte. Les visiter tous les cinq cents rend chaque voyage gratuit.", false],
	],
	"progress/loyalty": [
		[1, "", "Votre loyauté se situe quelque part entre les Terraniens et les Vossk, indiquée par le curseur de l'écran État. Chaque mission pour un client terranien la déplace d'un cran vers les Terraniens ; chaque mission pour un client vossk, d'un cran vers les Vossk. Elle ne peut pas dépasser dix crans dans un sens ou dans l'autre.", false],
		[1, "", "Si vous vous rendez dans un lieu terranien alors que votre loyauté penche vers les Vossk, ou dans un lieu vossk alors qu'elle penche vers les Terraniens, un pot-de-vin vous est demandé en plus des frais de vol : 150 crédits par cran. Payer un pot-de-vin ramène votre loyauté d'un cran vers le centre.", false],
	],
	"mode/survival": [
		[1, "", "Survie est un mode à part, avec son propre pilote et son tableau des meilleurs scores. Choisissez-le dans Commencer partie. Les vaisseaux ennemis arrivent sans cesse, chaque destruction rapporte des points et répare votre coque, et la couleur des repères d'un ennemi indique sa force. Votre score vous vaut un rang tiré du tableau ci-dessous.", false],
	],
	"mode/swarm": [
		[1, "", "Essaim est un mode écrit pour ce remake, accessible depuis Commencer partie. Il commence avec une poignée de chasseurs et devient une foule qui se referme de tous côtés, avec des vagues après la cinquième minute.", false],
		[1, "", "Chaque destruction remplit la barre de niveau. Chaque niveau propose trois cartes d'amélioration : une nouvelle arme, une meilleure version d'une arme que vous portez, un canon supplémentaire, plus de portée ou de vitesse de projectile, un bouclier plus fort, une réparation à chaque destruction ou une autre coque. Refuser une carte répare un quart de votre coque à la place.", false],
		[1, "", "Les armes, boucliers et coques sont ceux de votre fichier de jeu. Atteindre un rang au classement de Survie débloque la coque suivante pour Essaim.", false],
	],
	"guide/start": [
		[1, "", "Une fois le fichier de jeu importé, Commencer partie propose la campagne, l'exploration libre, Survie et Essaim. La campagne commence à [[station/0]] avec un [[ship/0]] et 5 000 crédits.", false],
		[1, "Le menu de la station", "Dans une station, Info décrit le lieu, Hangar ouvre la boutique et votre vaisseau, Missions affiche le tableau des contrats et Carte permet de voyager. Pendant la campagne, le tableau des contrats et la carte restent verrouillés, et Continuer lance le briefing suivant. État indique votre niveau, votre réputation, votre temps de jeu, vos destructions et votre loyauté, et Menu contient les options et la sauvegarde.", false],
		[1, "", "Tous les lieux n'ont pas un hangar ouvert à tous : sans commerce, le hangar ne s'ouvre que pendant la campagne ou à partir de plus de 999 999 crédits.", false],
	],
	"guide/flight": [
		[1, "", "Les points de passage sont marqués en jaune, les alliés en vert et les ennemis en rouge. Les objets hors de votre champ de vision apparaissent au bord de l'écran. La force restante d'un ennemi s'affiche sous son repère.", false],
		[1, "", "Votre bouclier absorbe les collisions et les tirs et se recharge avec le temps ; une fois épuisé, les dégâts touchent la coque. Le boost donne une brève accélération et doit ensuite se recharger.", false],
		[1, "Commandes", "Au clavier, dirigez avec la souris ou les flèches, réglez la poussée avec W et S et faites des pas de côté avec A et D. Tirez d'un clic ou avec Espace, changez d'arme avec Q, lancez des missiles avec F et boostez avec Maj. R active le pilote automatique, T accélère le temps sur les trajets sûrs, E amarre près d'une station et Échap met en pause. Une manette vise avec le stick droit et tire avec la gâchette droite. Les commandes tactiles ont un stick, une manette des gaz et des boutons pour le tir, les missiles, le boost et la navigation ; un double appui sur Tir active le tir automatique.", false],
		[1, "Pilote automatique et temps", "Le pilote automatique vole jusqu'au prochain point de passage ou à la station. Tant que rien ne vous menace, le temps peut s'écouler plus vite ; les ennemis, les dégâts ou l'arrivée à destination le ramènent à la normale.", false],
	],
	"guide/weapons": [
		[1, "", "Les vaisseaux ont des supports pour cinq types d'armes : lasers, canons à plasma, canons à photons, missiles et canons thermiques. Chaque support porte une arme, et chaque vaisseau a son propre jeu de supports. Un générateur de bouclier s'adapte à tous les vaisseaux.", false],
		[1, "", "Les lasers et canons à plasma tirent vite à moyenne portée. Les canons à photons portent le plus loin et frappent le plus fort par tir, mais se rechargent lentement. Les canons thermiques projettent des particules à courte portée avec une cadence de tir très élevée. Les missiles se lancent avec leur propre bouton, sans changer d'arme, et font de lourds dégâts avec un long rechargement.", false],
		[1, "", "Les boucliers diffèrent par leur capacité et leur vitesse de recharge. Les armes les plus puissantes ne sont vendues qu'à partir du deuxième quadrant, et les armes vossk uniquement dans les boutiques vossk.", false],
	],
	"guide/hangar": [
		[1, "", "Le hangar a trois parties : Vaisseau montre votre vaisseau avec ses armes montées et son bouclier, Fret contient vos marchandises et votre équipement de rechange, et Shop propose le stock de la station.", false],
		[1, "", "L'équipement acheté va dans la soute ; installez-le de là si votre vaisseau a un support libre pour lui. Équipement et vaisseaux se revendent à la moitié de leur prix.", false],
		[1, "", "Acheter un vaisseau fait reprendre l'actuel. L'équipement compatible avec le nouveau vaisseau reste monté et le reste passe en soute, tant qu'il y a de la place.", false],
		[1, "", "Les boutiques vendent entre une et quatre armes ou boucliers et jusqu'à trois vaisseaux, choisis selon ce que le quadrant et le peuple du lieu permettent. Le stock d'une boutique se renouvelle quand vous revenez après avoir volé ailleurs. Pendant la campagne, chaque chapitre a son propre stock fixe.", false],
	],
	"guide/trade": [
		[1, "", "Les marchandises proviennent des débris des vaisseaux détruits et rejoignent votre soute après la mission. Vendez-les dans la partie fret du hangar. Certaines rapportent le plus là où la technologie est faible, d'autres là où elle est élevée, et d'autres le même prix partout ; chaque page de marchandise indique son prix à chaque niveau technologique.", false],
		[1, "", "Les boutiques n'ont pas de marchandises à elles. Ce que vous vendez dans une boutique reste dans son stock, et vous pouvez le racheter au même prix.", false],
		[1, "", "Le commerce exige un hangar : les planètes et stations sans commerce n'ouvrent le leur qu'aux pilotes possédant plus de 999 999 crédits.", false],
	],
	"guide/travel": [
		[1, "", "La carte montre la galaxie, ses quadrants et ses systèmes. Choisissez un lieu et rendez-vous-y pour les frais de vol indiqués, plus un pot-de-vin si votre loyauté va contre son peuple. Vous arrivez amarré.", false],
		[1, "", "Les frais de vol augmentent avec la distance. Changer de quadrant ajoute 15 000 crédits au trajet, et 30 000 pour le quadrant opposé. La carte montre quelle part de la galaxie vous avez explorée ; une fois tous les lieux visités, les voyages ne coûtent rien.", false],
		[1, "", "La galaxie s'ouvre quand la campagne est terminée ou quand vous la passez.", false],
	],
	"guide/jobs": [
		[1, "", "En dehors de la campagne, le tableau des contrats de chaque station propose quelques contrats de clients de différents peuples. Chacun indique sa difficulté et sa récompense ; les contrats difficiles paient davantage, tout comme les quadrants plus éloignés.", false],
		[1, "", "De temps en temps, un escroc louche propose un contrat payant quarante pour cent de plus que d'habitude. Un contrat terminé verse sa récompense et rapproche votre loyauté du peuple du client.", false],
	],
	"guide/campaign": [
		[1, "", "La campagne est une suite de treize missions. Une mission réussie verse sa récompense ; une mission échouée peut être retentée. Une fois la campagne terminée, le moteur hyperspatial ouvre la galaxie, et le tableau des contrats et la carte deviennent disponibles.", false],
		[1, "", "Passer la campagne · Explorer, dans le menu de départ ou le menu de la station, mène directement à l'exploration libre. Passer la campagne ne donne aucune récompense de fin et garde votre pilote de campagne dans son propre emplacement.", false],
	],
	"guide/saves": [
		[1, "", "Le jeu sauvegarde automatiquement après chaque mission et aux points de contrôle. Campagne, exploration, Survie et Essaim ont des sauvegardes séparées. Charger / récupérer dans le menu de pause, ou Charger après une défaite, ramène à la dernière sauvegarde automatique, au début du vol ou à la dernière station.", false],
		[1, "", "Fichiers du jeu → Transférer les sauvegardes déplace vos sauvegardes vers un autre appareil qui a importé le même fichier de jeu.", false],
	],
	"guide/tips": [
		[1, "", "Vendez la cargaison récupérée sur les épaves avant d'acheter de l'équipement ; la soute se remplit vite sur les petits vaisseaux.", true],
		[1, "", "Vérifiez les supports d'un vaisseau avant de lui acheter des armes : une arme sans support adapté reste en soute.", true],
		[1, "", "Gardez vos marchandises jusqu'à ce que vous vous amarriez là où le niveau technologique les favorise.", true],
		[1, "", "Voler pour un seul camp rend les stations de l'autre coûteuses à visiter.", true],
		[1, "", "Visitez de nouveaux lieux quand vous voyagez de toute façon : explorer toute la galaxie rend chaque voyage gratuit.", true],
	],
}
