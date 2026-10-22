extends RefCounted
## The reference's own writing in German. Same blocks, chapter gates and links
## as prose/en.gd; see there for the format.

const PAGES := {
	"home": {"title": "Nachschlagewerk"},
	"world/setting": {"title": "Die Galaxie im Krieg"},
	"world/fleet": {"title": "Die terranische Raumflotte"},
	"world/outlaws": {"title": "Gesetzlose und Piraten"},
	"chapter/1": {"title": "Ein neues Schiff"},
	"chapter/2": {"title": "Weltraumschrott"},
	"chapter/3": {"title": "Passage nach Phoebos"},
	"chapter/4": {"title": "Docs Fracht"},
	"chapter/5": {"title": "Der Waffenkonvoi"},
	"chapter/6": {"title": "Der flüchtige Spion"},
	"chapter/7": {"title": "Heikle Ware"},
	"chapter/8": {"title": "Entern des Riesen"},
	"chapter/9": {"title": "Vier Schiffe nach Opos"},
	"chapter/10": {"title": "Die nivelianische Front"},
	"chapter/11": {"title": "Hinterhalt im Nebel"},
	"chapter/12": {"title": "Die Gesetzlosenstation"},
	"chapter/13": {"title": "Vergeltung"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Söldnerpilot"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Leutnant der Raumflotte"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Kommandant der Raumflotte"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Eiliger Passagier"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Vossk-Clanoberhaupt", "early_title": "Vossk-Pilot"},
	"character/5": {"title": "John „Doc“ Washington", "subtitle": "Händler"},
	"character/6": {"title": "Staffelpilot", "subtitle": "Raumflotte"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Sicherheitsoffizier"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Spion auf der Flucht"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Oktopoden-Händler"},
	"character/10": {"title": "Feknor", "subtitle": "Von den Grey"},
	"character/11": {"title": "Admiral Smith", "subtitle": "Terranische Raumflotte"},
	"character/12": {"title": "Botom Krant", "subtitle": "Nivelianischer Stationskommandant"},
	"progress/ranks": {"title": "Ruf und Level"},
	"progress/milestones": {"title": "Meilensteine"},
	"progress/loyalty": {"title": "Loyalität und Bestechung"},
	"mode/survival": {"title": "Überleben", "subtitle": "Spielmodus"},
	"mode/swarm": {"title": "Schwarm", "subtitle": "Spielmodus des Remakes"},
	"guide/start": {"title": "Erste Schritte"},
	"guide/flight": {"title": "Fliegen und kämpfen"},
	"guide/weapons": {"title": "Waffen und Schilde"},
	"guide/hangar": {"title": "Der Hangar"},
	"guide/trade": {"title": "Handel und Beute"},
	"guide/travel": {"title": "Reisen und die Karte"},
	"guide/jobs": {"title": "Die Auftragstafel"},
	"guide/campaign": {"title": "Kampagne und freie Erkundung"},
	"guide/saves": {"title": "Speichern und Laden"},
	"guide/tips": {"title": "Tipps"},
}

const BLOCKS := {
	"home": [
		[1, "", "Dieses Nachschlagewerk beschreibt dein eigenes Galaxy on Fire: jeden Planeten und jede Station der Galaxie, die Schiffe, Waffen und Waren in den Läden, die Aufträge an den Tafeln, die Figuren der Geschichte und die Regeln für Handel, Reisen und Ruf. Namen, Beschreibungen und Dialoge stammen aus der importierten Spieldatei; die Zahlen folgen den Regeln, nach denen dieses Remake spielt.", false],
		[1, "", "Die Seiten zur Geschichte wachsen mit deiner Kampagne. Kapitel, die du noch nicht erreicht hast, und Figuren, die du noch nicht kennst, bleiben verborgen, und der Ausgang eines Kapitels erscheint erst, wenn du es geflogen bist.", false],
	],
	"intro/world": [
		[1, "", "Die Welt des Spiels: der Krieg zwischen Terranern und Vossk, die Raumflotte, die Keith Maxwell gerade verlassen hat, und die Gesetzlosen, die beide Seiten ausplündern.", false],
	],
	"intro/story": [
		[1, "", "Die Kampagne ist eine einzige Abfolge von dreizehn Kapiteln. Jedes beginnt mit einer Einsatzbesprechung auf einer Station und geht im Flug mit Funksprüchen weiter. Die Kapitel unten reichen so weit, wie dein Pilot gekommen ist.", false],
	],
	"intro/characters": [
		[1, "", "Die Figuren, die in Einsatzbesprechungen und über Funk mit Keith Maxwell sprechen. Jedes Porträt stammt aus der Grafik des Spiels.", false],
	],
	"intro/races": [
		[1, "", "Zehn Völker leben auf den Planeten und Stationen der Galaxie. Die Bewohner eines Ortes bestimmen, welche Schiffe sein Laden verkaufen darf, und bei Terranern und Vossk auch, ob dich deine Loyalität bei der Anreise ein Bestechungsgeld kostet.", false],
	],
	"intro/galaxy": [
		[1, "", "Die Galaxie ist in vier Quadranten mit je fünfundzwanzig Systemen geteilt, und jedes System umfasst fünf Planeten oder Stationen. Die Karte unten zeigt sie alle; Reisen zwischen ihnen sind möglich, sobald die Kampagne vorbei ist, oder sofort, wenn du sie überspringst.", false],
	],
	"intro/stations": [
		[1, "", "Alle fünfhundert Planeten und Stationen. Die Technologiestufe eines Ortes bestimmt seine Frachtpreise und Schiffsrabatte; nur Orte mit Handel haben einen Hangar, der allen offensteht.", false],
	],
	"intro/ships": [
		[1, "", "Die Schiffe, die du kaufen kannst. Rumpf, Frachtraum und Waffenhalterungen unterscheiden sie; die Läden der meisten Völker verkaufen alle außer dem Vossk-Jäger, den nur die Vossk anbieten.", false],
	],
	"intro/equipment": [
		[1, "", "Waffen und Schildgeneratoren. Ein Schiff kann eine Waffe nur tragen, wenn es eine Halterung für diese Waffenart hat, und von jeder Art nur eine zugleich.", false],
	],
	"intro/goods": [
		[1, "", "Fracht aus den Trümmern zerstörter Schiffe. Jede Warenart folgt ihrer eigenen Regel dafür, wie die Technologiestufe einer Station ihren Preis verändert.", false],
	],
	"intro/jobs": [
		[1, "", "Die Arten von Arbeit, die die Auftragstafel anbietet, sobald die Galaxie offen ist. Die Belohnung hängt vom Auftrag und vom Quadranten ab, in dem du bist.", false],
	],
	"intro/progress": [
		[1, "", "Wie das Spiel deinen Piloten misst: Ruf durch Abschüsse, Level durch Einnahmen, Loyalität zwischen Terranern und Vossk und die Nachrichten, die deinen Reichtum und deine Erkundung würdigen.", false],
	],
	"intro/modes": [
		[1, "", "Spielweisen neben Kampagne und freier Erkundung.", false],
	],
	"intro/guide": [
		[1, "", "So wird gespielt: fliegen, kämpfen, ausrüsten, handeln, reisen und sich hocharbeiten.", false],
	],
	"world/setting": [
		[1, "", "Im vierten Jahrtausend führen die Terraner einen interplanetaren Krieg gegen die [[race/1]]. Andere Völker teilen die Galaxie mit ihnen: manche mit einer Seite verbündet, manche mit beiden im Handel, manche kaum bekannt.", false],
		[1, "", "Das Spiel beginnt im Jahr 3587 auf [[station/0]], einer terranischen Station, wo der Schlachtkreuzer SS Ulysses [[character/0]] absetzt. Nach seiner ehrenhaften Entlassung aus der Raumflotte hat er von [[character/11|Admiral Smith]] ein eigenes Schiff bekommen und will sich als Söldner durchschlagen.", false],
		[1, "Schauplatz", "Die ganze Kampagne spielt im ersten Quadranten, [[quadrant/0]], in der Nähe von [[station/0]]. Der Rest der Galaxie öffnet sich, wenn die Geschichte vorbei ist.", false],
		[14, "Nach dem Krieg", "Der Anführer der Gesetzlosen ist tot, ein Hyperspace-Antrieb ist an Bord, und Maxwell lehnt einen Platz in der Flotte ab. Die Galaxie gehört ihm: zum Erkunden, zum Handeln und zum Kämpfen für jeden, der zahlt.", false],
	],
	"world/fleet": [
		[1, "", "Die terranische Raumflotte ist das Militär der terranischen Welten. Maxwell hat vor Spielbeginn in ihr gedient, und die meisten Aufträge seiner Kampagne kommen von ihren Offizieren oder aus deren Umfeld.", false],
		[1, "", "Ihr Standardjäger ist die [[ship/6]]. Zu ihren Offizieren in der Geschichte gehören [[character/1]], die Maxwell sein neues Schiff zeigt, und [[character/11|Admiral Smith]], der es ihm gegeben hat.", false],
		[5, "", "Die Flotte setzt auch Agenten ein. Leutnant Hammond arbeitet auf Befehl des Admirals verdeckt auf [[station/2]].", false],
		[6, "", "Sicherheitsoffizier [[character/7]] jagt Verräter innerhalb der Flotte.", false],
		[12, "", "Nicht alle ihre Kommandanten sind loyal: einer von ihnen hat hinter dem Rücken der Flotte mit den Vossk und den Gesetzlosen paktiert.", false],
	],
	"world/outlaws": [
		[9, "", "Gesetzlose fliegen umgebaute terranische Schiffe und überfallen Konvois. Als sie einen Grey-Konvoi tief im Vossk-Gebiet angreifen, wird klar, dass sie mit den Vossk zusammenarbeiten.", false],
		[12, "", "Die Gesetzlosen haben einen Anführer in der Raumflotte selbst, der gestohlene Militärgeheimnisse an die Vossk verkauft und die Angriffe auf die Transporter gedeckt hat. Sie verschanzen sich in einer eigenen Station hinter einem Minenfeld.", false],
		[1, "", "Gesetzlose haben auf der Galaxiekarte auch ein eigenes Volk: Orte mit den Bewohnern [[race/9]] sind ihre Stationen und Planeten. Nur ihre Läden verkaufen die [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell kommt auf [[station/0]] an und wird von Leutnant [[character/1]] empfangen, die von Admiral Smith den Befehl hat, ihm sein neues Schiff zu zeigen, einen alten [[ship/0]]-Aufklärer. Sie erklärt den Hangar: Schiffe, Waffen und Ausrüstung kauft man im Shop, und im All gesammelte Fracht verkauft man aus dem Frachtraum.", false],
		[1, "", "Dann folgt ein Testflug. Christine führt ihn durch die Wegpunkte, erklärt Schilde, Waffenwechsel, Feuern und den Boost und lässt zum Schluss ein paar Übungsdrohnen zum Abschießen aufsteigen.", false],
		[2, "Ausgang", "Maxwell zerstört die Drohnen und kehrt zur Station zurück. Christine wünscht ihm Glück und hofft, ihn in einem Stück wiederzusehen.", false],
	],
	"chapter/2": [
		[2, "", "Ein unwillkommenes Gesicht aus der Flotte: Kommandant [[character/2]], den Maxwell noch nie ausstehen konnte, hat einen Auftrag für ihn. Ein Raumkorridor nahe der Station muss von Trümmern befreit werden, bevor der nächste Konvoi eintrifft, und dafür bleiben nur zwei Minuten.", false],
		[3, "Ausgang", "Der Korridor ist rechtzeitig frei, und Vlad zahlt, mit der Bemerkung, Maxwell sei wie gemacht für diese Arbeit.", false],
	],
	"chapter/3": [
		[3, "", "Ein nervöser kleiner Kunde, [[character/3]], will sofort nach [[station/1]] gebracht werden, bevor ihm ein Geschäft platzt. Dort wimmelt es von Vossk, aber er zahlt gut, und Maxwell nimmt an.", false],
		[4, "Ausgang", "Unterwegs verlangt eine Vossk-Patrouille ihre Kapitulation. Maxwell bringt Bolar durch, und der Passagier verspricht, ihn weiterzuempfehlen, sobald er aufgehört hat zu zittern.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] braucht Geleitschutz für sein Schiff nach [[station/2]], dem Versteck der Piraten. Maxwell handelt das Honorar wegen des Risikos hoch und vermutet, dass die Fracht wieder eine Waffenlieferung für die Gesetzlosen ist.", false],
		[5, "Ausgang", "Zweimal gehen Vossk-Jäger auf den Frachter los. Er erreicht Tortuga, und Doc macht klar, dass seine Ladung Maxwell nichts angeht.", false],
	],
	"chapter/5": [
		[5, "", "Auf Tortuga trifft Maxwell [[character/1]], die dort verdeckt ermittelt. Die Flotte soll einen Vossk-Waffenkonvoi nahe [[station/3]] abfangen; kommt die Lieferung durch, droht ein Massaker. Ihre Staffel braucht noch einen erfahrenen Piloten.", false],
		[6, "Ausgang", "Zuerst fällt der Geleitschutz, dann die Frachter. Der Konvoi ist gestoppt, und Christine rechnet damit, dass Admiral Smith zufrieden sein wird.", false],
	],
	"chapter/6": [
		[6, "", "Sicherheitsoffizier [[character/7]] hat einen Auftrag, der nicht schiefgehen darf: [[character/8]], ein Spion, ist mit einem der Geheimschiffe der Flotte geflohen. Es darf nicht in Feindeshand fallen und ist notfalls zu zerstören.", false],
		[7, "Ausgang", "Maxwell findet Lockwood in einem Asteroidenfeld und beschädigt sein Schiff, bis er sich ergibt. Bevor jemand ihn festnehmen kann, schießt [[character/2|Vlad Borsikov]] ihn ab und erinnert Maxwell daran, dass der Befehl lautete, das Schiff zu zerstören. Maxwell beginnt zu ahnen, dass es nie nur um ein Schiff ging.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] bittet um Geleitschutz für seine Schiffe nach [[station/4]]. Maxwell erkennt die Oktopoden-Bande, die dafür bekannt ist, mit Diebesgut vollgestopft zu sein, nimmt den Auftrag aber an, solange die Behörden außen vor bleiben.", false],
		[8, "Ausgang", "Was als leichtes Geld beginnt, wird zum Kampf gegen Vossk-Jäger und einen Kreuzer. Mindestens ein Schiff kommt durch, und Maxwell stellt fest, dass die Vossk immer aggressiver werden.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] hat einen manövrierunfähigen Vossk-Schlachtkreuzer aufgespürt. Die Flotte will ihn kapern und seinen Kommandanten lebend fassen, doch zuerst muss jede fest montierte Kanone auf seinem Rumpf zerstört werden.", false],
		[9, "Ausgang", "Während Christines Staffel das Feuer auf sich zieht, schaltet Maxwell die Kanonen aus, und das Schiff wird geentert.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]] von den Grey heuert Maxwell an, einen Konvoi aus vier Schiffen nach [[station/5]] zu bringen, quer durch das Vossk-Gebiet, und zahlt für jedes Schiff, das ankommt.", false],
		[10, "Ausgang", "Die Angreifer sind keine Vossk, sondern umgebaute terranische Schiffe. Maxwell schlägt sie zurück und schließt daraus, dass die Gesetzlosen mit den Vossk zusammenarbeiten.", false],
	],
	"chapter/10": [
		[10, "", "[[character/11]] braucht jeden verfügbaren Piloten: Eine Station der Verbündeten der Terraner, der Nivelianer, wird von starken Vossk-Verbänden angegriffen. Nach einem scharfen Wortwechsel über Maxwells Preise und Loyalitäten schickt der Admiral ihn los.", false],
		[11, "Ausgang", "Stationskommandant [[character/12]] bittet Maxwell, sich auf die Kreuzer zu konzentrieren, während [[character/1|Christine]] die Jäger übernimmt. Der Angriff wird abgewehrt, und beide sind sich einig, dass die Gesetzlosen die verbleibende Gefahr sind.", false],
	],
	"chapter/11": [
		[11, "", "Ein Vossk-Clanoberhaupt, [[character/4]], nimmt heimlich Kontakt zu Maxwell auf. Einer der Vossk-Kommandanten verschwört sich mit einem terranischen Offizier und den Gesetzlosen, und der Clan will ihn tot sehen. Der beste Ort für einen Hinterhalt ist der Yarapu-Nebel.", false],
		[12, "Ausgang", "Maxwell zerstört den Kreuzer des Kommandanten und seine Eskorte. Nartok verrät ihm, dass der Verräter auf terranischer Seite ein alter Bekannter von Maxwell ist und dass Leutnant Hammond ihm bereits auf der Spur ist.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] bringt die Nachricht: [[character/2]] ist der Anführer der Gesetzlosen. Als Kommandant hat er die Angriffe auf die Transporter vertuscht und Lockwood Militärgeheimnisse stehlen lassen, um sie an die Vossk zu verkaufen. Seine Bande hat sich in einer Gesetzlosenstation verschanzt, die ein Minenfeld schützt, das Maxwell vor dem Angriff räumen muss.", false],
		[13, "Ausgang", "Das Minenfeld ist geräumt, und die Verteidiger der Station fallen. Christine stürmt auf Vlad zu, der sie abschießt, bevor Maxwell sie decken kann, und entkommt.", false],
	],
	"chapter/13": [
		[13, "", "[[character/11]] spricht sein Beileid aus; Maxwell will nur wissen, wohin Vlad verschwunden ist. Die Flotte hat Vlad und den Rest seiner Gesetzlosen gefunden, und ihre Staffeln brauchen Maxwells Hilfe, um sie zu zerschlagen.", false],
		[14, "Ausgang", "Als die Gesetzlosen zerschlagen sind, überlässt Maxwell der Flotte ihre Arbeit, verfolgt Vlad allein und tötet ihn. Der Admiral bietet ihm einen Platz in der Flotte an; Maxwell lehnt ab. Er erhält einen Hyperspace-Antrieb, der ihm jeden Quadranten der Galaxie öffnet.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell ist der Pilot des Spielers: ein ehemaliger Pilot der terranischen Raumflotte, der nach seiner ehrenhaften Entlassung von [[character/11|Admiral Smith]] ein Schiff erhält und auf [[station/0]] ein Leben als Söldner beginnt.", false],
		[1, "", "Er ist sarkastisch und feilscht gern um sein Honorar, aber die Aufträge, die er annimmt, bringt er zu Ende.", false],
		[7, "", "Er protestiert, als [[character/2|Vlad Borsikov]] einen Mann erschießt, der sich ergeben hatte.", false],
		[13, "", "Der Tod von [[character/1|Christine Hammond]] macht das letzte Kapitel zu einer persönlichen Angelegenheit.", false],
		[14, "", "Nachdem er Vlad getötet hat, lehnt er die Rückkehr in die Flotte ab und sucht sich lieber seinen eigenen Weg durch die Galaxie.", false],
	],
	"character/1": [
		[1, "", "Leutnant Christine Hammond von der terranischen Raumflotte empfängt Maxwell auf [[station/0]], zeigt ihm sein Schiff und fliegt mit ihm seinen ersten Testflug. Sie bittet ihn, sie Christine zu nennen.", false],
		[5, "", "Sie arbeitet auch als Agentin: Auf [[station/2]] ist sie auf Befehl von Admiral Smith verdeckt im Einsatz, und sie holt Maxwell zum Schlag gegen den Vossk-Waffenkonvoi.", false],
		[8, "", "Sie führt die Staffel, die einen manövrierunfähigen Vossk-Schlachtkreuzer kapert.", false],
		[12, "", "Sie deckt auf, dass [[character/2|Vlad Borsikov]] hinter den Gesetzlosen steckt, und plant den Angriff auf ihre Station.", false],
		[13, "", "Nach der Schlacht stürmt sie auf Vlad zu und wird von ihm abgeschossen. Ihr Tod treibt Maxwell im letzten Kapitel hinter Vlad her.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov ist Kommandant der terranischen Raumflotte und, mit Maxwells Worten, der mieseste Kerl darin. Er gibt Maxwell seinen ersten bezahlten Auftrag: einen Raumkorridor gegen die Uhr von Trümmern zu befreien.", false],
		[7, "", "Er schießt den Spion Corsair Lockwood ab, nachdem dieser sich ergeben hat, und besteht darauf, dass der Befehl lautete, das Schiff zu zerstören.", false],
		[12, "", "Er ist der Verräter: der Anführer der Gesetzlosen, der seinen Rang nutzte, um die Angriffe auf die Transporter zu decken, und Lockwood Militärgeheimnisse stehlen ließ, die er an die Vossk verkaufte.", false],
		[13, "", "Als Christine Hammond ihm nach dem Angriff auf seine Station nachsetzt, schießt er sie ab und entkommt.", false],
		[14, "", "Die Flotte findet ihn mit dem Rest seiner Gesetzlosen, und Maxwell tötet ihn im Duell.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon ist ein fahriger Kunde, der sofort nach [[station/1]] muss, um ein Geschäft zu retten, und einen Piloten gut bezahlt, der ihn durch den Vossk-Raum bringt.", false],
		[4, "", "Er überlebt den Hinterhalt der Vossk und verspricht, Maxwell weiterzuempfehlen.", false],
	],
	"character/4": [
		[4, "", "Ein Vossk mit diesem Gesicht ruft Maxwell auf dem Weg nach Phoebos an und fordert im Namen des Vossk-Imperiums die Kapitulation.", false],
		[11, "", "Nartok Brek ist ein Clanoberhaupt der [[race/1]]. Er nimmt heimlich Kontakt zu Maxwell auf, weil einer seiner eigenen Kommandanten sich mit einem terranischen Offizier und den Gesetzlosen verschworen hat, und bittet darum, den Verräter im Yarapu-Nebel in einen Hinterhalt zu locken. Bevor er etwas sagt, verlangt er Maxwells Ehrenwort.", false],
		[12, "", "Nach dem Hinterhalt verrät er Maxwell, dass Maxwell den terranischen Verräter von früher kennt.", false],
	],
	"character/5": [
		[4, "", "John Washington, von Freunden Doc genannt, braucht Geleitschutz für sein Schiff nach [[station/2]]. Er bietet 3.000 Credits und lässt sich auf 4.500 ein, unter der Bedingung, dass es keine Zeugen gibt. Maxwell vermutet eine Waffenlieferung für die Gesetzlosen.", false],
		[5, "", "Seine Fracht kommt an. Was es war, behält er für sich.", false],
	],
	"character/6": [
		[6, "", "Ein Pilot aus Christine Hammonds Staffel, der über Funk fragt, ob dieser Maxwell überhaupt kampferprobt ist, ohne zu merken, dass er mithört.", false],
		[13, "", "Dieselbe Staffel bleibt zurück, um die Gesetzlosenstation zu sichern, während Christine und Maxwell Vlad verfolgen.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom ist der Sicherheitsoffizier der Raumflotte. Er schickt Maxwell hinter dem Spion [[character/8]] her, mit dem Befehl, dass das gestohlene Schiff nicht in Feindeshand fallen darf.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood ist ein Spion, der mit einem der Geheimschiffe der Raumflotte geflohen ist.", false],
		[7, "", "In einem Asteroidenfeld in die Enge getrieben, ergibt er sich und wird trotzdem von Vlad Borsikov abgeschossen.", false],
		[12, "", "Später stellt sich heraus, dass Vlad ihn überhaupt erst beauftragt hatte, Militärgeheimnisse zu stehlen.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt fliegt Fracht für die Oktopoden-Bande, die dafür bekannt ist, Diebesgut zu transportieren. Er beteuert, dass alles an Bord völlig legal ist, und bezahlt Maxwell dafür, seine Schiffe nach [[station/4]] zu bringen.", false],
	],
	"character/10": [
		[9, "", "Feknor von den Grey hat von Maxwell gehört und bietet ihm einen schwierigen Auftrag an: vier Schiffe nach [[station/5]] quer durch das Vossk-Gebiet, für 4.000 Credits pro Schiff, das ankommt.", false],
	],
	"character/11": [
		[1, "", "Admiral Smith von der terranischen Raumflotte gab Maxwell nach seiner Entlassung sein Schiff und lässt ihn von Leutnant Hammond einweisen.", false],
		[10, "", "Er ruft Maxwell, als die nivelianische Station angegriffen wird. Ihr Gespräch wird scharf, als Maxwell von seinen Preisen spricht und davon, was die Vossk wohl zahlen würden.", false],
		[13, "", "Nach Christines Tod spricht er Maxwell sein Beileid aus und nennt ihm den Aufenthaltsort von Vlads Gesetzlosen.", false],
		[14, "", "Er lässt Maxwell allein hinter Vlad her, bietet ihm einen Platz in der Flotte an und gibt ihm einen Hyperspace-Antrieb, als er ablehnt.", false],
	],
	"character/12": [
		[11, "", "Botom Krant befehligt die nivelianische Station, die von den Vossk angegriffen wird. Er bittet Maxwell, sich auf die Kreuzer zu konzentrieren, und dankt ihm, als der Angriff abgewehrt ist.", false],
	],
	"race/0": [
		[1, "", "Menschen, die im vierten Jahrtausend Krieg gegen die [[race/1]] führen. Maxwell ist Terraner, und die meisten Auftraggeber der Kampagne dienen in der terranischen Raumflotte. Terraner besitzen mehr Planeten und Stationen als jedes andere Volk.", false],
		[1, "", "Viele der angebotenen Schiffe sind terranische Konstruktionen: die [[ship/0]], die [[ship/6]] und ihre umgebaute [[ship/7]] sowie das Kanonenschiff [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "Der Feind der Terraner. Vossk-Läden verkaufen nur ihren eigenen Jäger, die [[ship/8]], und nur sie verkaufen die Vossk-Waffen. Wer für die Terraner arbeitet, muss an Vossk-Stationen Bestechungsgeld zahlen, und umgekehrt.", false],
	],
	"race/2": [
		[1, "", "Eines der Völker der Galaxie, mit eigenen Planeten und Stationen.", false],
	],
	"race/3": [
		[1, "", "Eines der Völker der Galaxie, mit eigenen Planeten und Stationen.", false],
	],
	"race/4": [
		[1, "", "Ihre Spezialbauteile stecken in Waffen wie dem [[equipment/23]], und der schwere Bomber [[ship/3]] stammt von ihnen.", false],
	],
	"race/5": [
		[1, "", "Grey-Schiffe sind für ihre enorm schwere Panzerung bekannt. Der Aufklärer [[ship/9]] stammt aus ihrer Flotte und wurde erst kürzlich für humanoide Piloten umgebaut, und die Rakete [[equipment/4]] besteht aus Grey-Bauteilen. Feknor von den Grey heuert Maxwell für einen gefährlichen Konvoi an.", false],
	],
	"race/6": [
		[1, "", "Verbündete der Terraner. Der Jäger [[ship/1]] ist eine nivelianische Entwicklung, und der Laser [[equipment/2]] beruht auf nivelianischer Waffentechnik. Der Vossk-Angriff auf eine ihrer Stationen zieht Maxwell endgültig in den Krieg.", false],
	],
	"race/7": [
		[1, "", "Eines der Völker der Galaxie, mit eigenen Planeten und Stationen.", false],
	],
	"race/8": [
		[1, "", "Eines der Völker der Galaxie, mit eigenen Planeten und Stationen.", false],
	],
	"race/9": [
		[1, "", "Die Gesetzlosen sind kein Volk, sondern eine Lebensweise: Piraten und Schmuggler mit eigenen Planeten und Stationen. Nur ihre Läden verkaufen die [[ship/7]], und [[station/2]] ist ihr bekanntestes Versteck.", false],
	],
	"galaxy": [
		[1, "", "Vier Quadranten, hundert Systeme und fünfhundert Planeten und Stationen. Jeder Quadrant ist schwerer als der vorige: Seine Aufträge zahlen mehr, seine Gegner sind zäher und seine Läden verkaufen bessere Ausrüstung.", false],
		[1, "", "Flüge innerhalb eines Quadranten kosten Credits je nach Entfernung; der Wechsel in den benachbarten oder den gegenüberliegenden Quadranten kostet extra. Hast du jeden Ort der Galaxie besucht, ist Reisen kostenlos.", false],
	],
	"progress/ranks": [
		[1, "Ruf", "Der Ruf zählt die Gegner, die du zerstört hast. Jede Schwelle in der Tabelle unten hebt deinen Rang, der im Bildschirm Status angezeigt wird.", false],
		[1, "Level", "Dein Level wächst mit dem Geld, das du mit Missionen und Aufträgen verdienst. Sobald deine Gesamteinnahmen das 1,6-Fache ihres Stands beim letzten Level übersteigen, erreichst du das nächste. Höhere Level machen die Gegner in deinen Missionen zäher.", false],
	],
	"progress/milestones": [
		[1, "", "Beim Andocken begrüßt dich die Station mit einer Nachricht, wenn deine Credits zum ersten Mal einen Meilenstein überschreiten oder deine Erkundung der Galaxie eine neue Marke erreicht. Die Nachrichten unten stammen aus dem Spiel selbst.", false],
		[1, "Reichtum", "Reichtum ist mehr als eine Zahl. Mit mehr als 999.999 Credits kannst du auf jedem Planeten und jeder Station handeln: Der Hangar öffnet sich auch dort, wo es keinen Handel gibt, und du kannst dort kaufen, deine Fracht und Beute verkaufen und dein Schiff umrüsten.", false],
		[1, "Erkundung", "Jeder besuchte Ort zählt. Wer alle fünfhundert besucht, reist überall kostenlos hin.", false],
	],
	"progress/loyalty": [
		[1, "", "Deine Loyalität liegt irgendwo zwischen Terranern und Vossk; der Zeiger im Bildschirm Status zeigt sie an. Jede Mission für einen terranischen Auftraggeber rückt sie einen Schritt zu den Terranern, jede Mission für einen Vossk-Auftraggeber einen Schritt zu den Vossk. Mehr als zehn Schritte in eine Richtung sind nicht möglich.", false],
		[1, "", "Reist du zu einem terranischen Ort, während deine Loyalität zu den Vossk neigt, oder zu einem Vossk-Ort, während sie zu den Terranern neigt, wird zusätzlich zu den Flugkosten Bestechungsgeld verlangt: 150 Credits pro Schritt. Wer zahlt, rückt seine Loyalität einen Schritt zur Mitte zurück.", false],
	],
	"mode/survival": [
		[1, "", "Überleben ist ein eigener Modus mit eigenem Piloten und eigener Bestenliste. Du findest ihn unter Spiel starten. Feindschiffe kommen ohne Pause, jeder Abschuss bringt Punkte und repariert deinen Rumpf, und die Farbe der Zielmarkierung zeigt, wie stark ein Gegner ist. Deine Punktzahl bringt dir einen Rang aus der Tabelle unten.", false],
	],
	"mode/swarm": [
		[1, "", "Schwarm ist ein Modus, der für dieses Remake geschrieben wurde, und findet sich unter Spiel starten. Er beginnt mit einer Handvoll Jägern und wächst zu einer Masse an, die von allen Seiten heranrückt, mit Wellen ab der fünften Minute.", false],
		[1, "", "Jeder Abschuss füllt die Levelleiste. Jedes Level bietet drei Verbesserungskarten: eine neue Waffe, eine bessere Version einer mitgeführten, eine zusätzliche Mündung, mehr Reichweite oder Projektilgeschwindigkeit, einen stärkeren Schild, Reparatur bei jedem Abschuss oder einen anderen Rumpf. Wer eine Karte ablehnt, repariert stattdessen ein Viertel seines Rumpfes.", false],
		[1, "", "Waffen, Schilde und Rümpfe sind die aus deiner Spieldatei. Ein Rang auf der Bestenliste von Überleben schaltet den nächsten Rumpf für Schwarm frei.", false],
	],
	"guide/start": [
		[1, "", "Nach dem Import der Spieldatei bietet Spiel starten die Kampagne, die freie Erkundung, Überleben und Schwarm an. Die Kampagne beginnt auf [[station/0]] mit einer [[ship/0]] und 5.000 Credits.", false],
		[1, "Das Stationsmenü", "Auf einer Station beschreibt Info den Ort, Hangar öffnet den Shop und dein Schiff, Missionen zeigt die Auftragstafel und Karte lässt dich reisen. Während der Kampagne bleiben Auftragstafel und Karte gesperrt, und Weiter startet die nächste Einsatzbesprechung. Status zeigt Level, Ruf, Spielzeit, Abschüsse und Loyalität, und Menü enthält die Optionen und das Speichern.", false],
		[1, "", "Nicht jeder Ort hat einen Hangar, der allen offensteht: Ohne Handel öffnet sich der Hangar nur während der Kampagne oder ab mehr als 999.999 Credits.", false],
	],
	"guide/flight": [
		[1, "", "Wegpunkte sind gelb markiert, Verbündete grün und Gegner rot. Objekte außerhalb deines Blickfelds erscheinen am Bildschirmrand. Unter der Markierung eines Gegners steht seine verbleibende Stärke.", false],
		[1, "", "Dein Schild fängt Kollisionen und Treffer ab und lädt sich mit der Zeit wieder auf; ist er erschöpft, trifft der Schaden den Rumpf. Der Boost gibt einen kurzen Geschwindigkeitsschub und muss sich danach wieder aufladen.", false],
		[1, "Steuerung", "Mit der Tastatur steuerst du mit der Maus oder den Pfeiltasten, regelst den Schub mit W und S und weichst mit A und D seitlich aus. Feuern mit Klick oder Leertaste, Waffe wechseln mit Q, Raketen mit F und Boost mit Umschalt. R schaltet den Autopiloten ein, T beschleunigt die Zeit auf sicheren Strecken, E dockt nahe einer Station an und Esc pausiert. Ein Controller zielt mit dem rechten Stick und feuert mit dem rechten Trigger. Die Touch-Steuerung hat einen Stick, einen Schubregler und Tasten für Feuer, Raketen, Boost und Navigation; ein Doppeltipp auf Feuer schaltet Dauerfeuer ein.", false],
		[1, "Autopilot und Zeit", "Der Autopilot fliegt zum nächsten Wegpunkt oder zur Station. Solange dich nichts bedroht, kann die Zeit schneller laufen; Gegner, Schaden oder die Ankunft am Ziel setzen sie wieder auf normal.", false],
	],
	"guide/weapons": [
		[1, "", "Schiffe haben Halterungen für fünf Waffenarten: Laser, Plasmakanonen, Photonenkanonen, Raketen und Thermokanonen. Jede Halterung trägt eine Waffe, und jedes Schiff hat seinen eigenen Satz Halterungen. Ein Schildgenerator passt in jedes Schiff.", false],
		[1, "", "Laser und Plasmakanonen feuern schnell auf mittlere Entfernung. Photonenkanonen reichen am weitesten und treffen pro Schuss am härtesten, laden aber langsam nach. Thermokanonen sprühen Partikel auf kurze Distanz mit sehr hoher Feuerrate. Raketen werden mit einer eigenen Taste abgefeuert, ohne die Waffe zu wechseln, und richten schweren Schaden an, laden aber lange nach.", false],
		[1, "", "Schilde unterscheiden sich in Kapazität und Ladegeschwindigkeit. Die stärksten Waffen gibt es erst ab dem zweiten Quadranten, die Vossk-Waffen nur in Vossk-Läden.", false],
	],
	"guide/hangar": [
		[1, "", "Der Hangar hat drei Bereiche: Schiff zeigt dein Schiff mit den montierten Waffen und dem Schild, Fracht enthält deine Waren und Ersatzausrüstung, und Shop bietet das Sortiment der Station.", false],
		[1, "", "Gekaufte Ausrüstung kommt in den Frachtraum; baue sie von dort ein, wenn dein Schiff eine freie Halterung dafür hat. Ausrüstung und Schiffe verkaufen sich für die Hälfte ihres Preises zurück.", false],
		[1, "", "Wer ein Schiff kauft, gibt sein aktuelles in Zahlung. Ausrüstung, die zum neuen Schiff passt, bleibt montiert, der Rest wandert in den Frachtraum, solange dort Platz ist.", false],
		[1, "", "Läden verkaufen ein bis vier Waffen oder Schilde und bis zu drei Schiffe, ausgewählt aus dem, was Quadrant und Volk des Ortes erlauben. Das Sortiment erneuert sich, wenn du nach einem Flug anderswohin zurückkehrst. In der Kampagne hat jedes Kapitel sein eigenes festes Sortiment.", false],
	],
	"guide/trade": [
		[1, "", "Waren stammen aus den Trümmern zerstörter Schiffe und landen nach der Mission in deinem Frachtraum. Verkaufe sie im Frachtbereich des Hangars. Manche bringen am meisten, wo die Technologie niedrig ist, manche, wo sie hoch ist, und manche überall gleich viel; jede Warenseite nennt den Preis für jede Technologiestufe.", false],
		[1, "", "Läden führen keine eigenen Waren. Was du in einem Laden verkaufst, bleibt in seinem Sortiment, und du kannst es dort zum gleichen Preis zurückkaufen.", false],
		[1, "", "Handel braucht einen Hangar: Planeten und Stationen ohne Handel öffnen ihren nur Piloten mit mehr als 999.999 Credits.", false],
	],
	"guide/travel": [
		[1, "", "Die Karte zeigt die Galaxie, ihre Quadranten und Systeme. Wähle einen Ort und reise für die angezeigten Flugkosten dorthin, zuzüglich Bestechungsgeld, wenn deine Loyalität gegen sein Volk steht. Du kommst angedockt an.", false],
		[1, "", "Die Flugkosten wachsen mit der Entfernung. Ein Quadrantenwechsel kostet 15.000 Credits extra, der gegenüberliegende Quadrant 30.000. Die Karte zeigt, wie viel der Galaxie du erkundet hast; hast du jeden Ort besucht, kostet Reisen nichts.", false],
		[1, "", "Die Galaxie öffnet sich, wenn die Kampagne abgeschlossen ist oder wenn du sie überspringst.", false],
	],
	"guide/jobs": [
		[1, "", "Außerhalb der Kampagne bietet die Auftragstafel jeder Station einige Aufträge von Kunden verschiedener Völker. Jeder zeigt Schwierigkeit und Belohnung; schwierige Aufträge zahlen mehr, ebenso die äußeren Quadranten.", false],
		[1, "", "Ab und zu bietet ein zwielichtiger Gauner einen Auftrag, der vierzig Prozent mehr als üblich zahlt. Ein erledigter Auftrag zahlt seine Belohnung und rückt deine Loyalität zum Volk des Kunden.", false],
	],
	"guide/campaign": [
		[1, "", "Die Kampagne ist eine Abfolge von dreizehn Missionen. Eine erfüllte Mission zahlt ihre Belohnung; eine gescheiterte kann wiederholt werden. Ist sie abgeschlossen, öffnet der Hyperspace-Antrieb die Galaxie, und Auftragstafel und Karte werden verfügbar.", false],
		[1, "", "Kampagne überspringen · Erkunden im Startmenü oder im Stationsmenü führt direkt in die freie Erkundung. Das Überspringen bringt keine Abschlussbelohnungen und behält deinen Kampagnenpiloten in seinem eigenen Platz.", false],
	],
	"guide/saves": [
		[1, "", "Das Spiel speichert automatisch nach jeder Mission und an Kontrollpunkten. Kampagne, Erkundung, Überleben und Schwarm haben getrennte Spielstände. Laden / wiederherstellen im Pausenmenü oder Laden nach einer Niederlage führt zum letzten automatischen Speicherstand, zum Flugbeginn oder zur letzten Station zurück.", false],
		[1, "", "Spieldateien → Spielstände übertragen bringt deine Spielstände auf ein anderes Gerät, das dieselbe Spieldatei importiert hat.", false],
	],
	"guide/tips": [
		[1, "", "Verkaufe die Fracht aus Wracks, bevor du Ausrüstung kaufst; auf kleinen Schiffen ist der Frachtraum schnell voll.", true],
		[1, "", "Prüfe die Halterungen eines Schiffs, bevor du Waffen dafür kaufst: Eine Waffe ohne passende Halterung bleibt im Frachtraum.", true],
		[1, "", "Behalte Waren, bis du dort andockst, wo die Technologiestufe sie begünstigt.", true],
		[1, "", "Wer nur für eine Seite fliegt, macht die Stationen der anderen Seite teuer.", true],
		[1, "", "Besuche neue Orte, wenn du ohnehin reist: Wer die ganze Galaxie erkundet, reist überall kostenlos.", true],
	],
}
