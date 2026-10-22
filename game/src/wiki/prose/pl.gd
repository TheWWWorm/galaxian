extends RefCounted
## The reference's own writing in Polish. Same blocks, chapter gates and links
## as prose/en.gd; see there for the format. The game has no Polish text, so
## names and the game's own menu labels stay as the game shows them.

const PAGES := {
	"home": {"title": "Kompendium"},
	"world/setting": {"title": "Galaktyka w stanie wojny"},
	"world/fleet": {"title": "Terrańska flota kosmiczna"},
	"world/outlaws": {"title": "Banici i piraci"},
	"chapter/1": {"title": "Nowy statek"},
	"chapter/2": {"title": "Kosmiczne śmieci"},
	"chapter/3": {"title": "Przelot na Phoebos"},
	"chapter/4": {"title": "Ładunek Doca"},
	"chapter/5": {"title": "Konwój z bronią"},
	"chapter/6": {"title": "Zbiegły szpieg"},
	"chapter/7": {"title": "Drażliwy towar"},
	"chapter/8": {"title": "Abordaż olbrzyma"},
	"chapter/9": {"title": "Cztery statki na Opos"},
	"chapter/10": {"title": "Front nivelański"},
	"chapter/11": {"title": "Zasadzka w mgławicy"},
	"chapter/12": {"title": "Stacja banitów"},
	"chapter/13": {"title": "Zemsta"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Pilot najemnik"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Porucznik floty kosmicznej"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Dowódca floty kosmicznej"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Spieszący się pasażer"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Przywódca klanu Vossków", "early_title": "Pilot Vossków"},
	"character/5": {"title": "John „Doc” Washington", "subtitle": "Handlarz"},
	"character/6": {"title": "Pilot eskadry", "subtitle": "Flota kosmiczna"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Oficer bezpieczeństwa"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Szpieg w ucieczce"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Handlarz Octopodów"},
	"character/10": {"title": "Feknor", "subtitle": "Z ludu Grey"},
	"character/11": {"title": "Admirał Smith", "subtitle": "Terrańska flota kosmiczna"},
	"character/12": {"title": "Botom Krant", "subtitle": "Nivelański dowódca stacji"},
	"progress/ranks": {"title": "Reputacja i poziom"},
	"progress/milestones": {"title": "Kamienie milowe"},
	"progress/loyalty": {"title": "Lojalność i łapówki"},
	"mode/survival": {"title": "Przetrwanie", "subtitle": "Tryb gry"},
	"mode/swarm": {"title": "Rój", "subtitle": "Tryb gry remake'u"},
	"guide/start": {"title": "Pierwsze kroki"},
	"guide/flight": {"title": "Latanie i walka"},
	"guide/weapons": {"title": "Broń i osłony"},
	"guide/hangar": {"title": "Hangar"},
	"guide/trade": {"title": "Handel i łupy"},
	"guide/travel": {"title": "Podróże i mapa"},
	"guide/jobs": {"title": "Tablica zleceń"},
	"guide/campaign": {"title": "Kampania i swobodna eksploracja"},
	"guide/saves": {"title": "Zapisywanie i wczytywanie"},
	"guide/tips": {"title": "Wskazówki"},
}

const BLOCKS := {
	"home": [
		[1, "", "To kompendium opisuje twój własny egzemplarz Galaxy on Fire: każdą planetę i stację galaktyki, statki, broń i towary w jej sklepach, zlecenia na jej tablicach, postacie jej fabuły oraz zasady handlu, podróży i reputacji. Nazwy, opisy i dialogi pochodzą z zaimportowanego pliku gry; liczby odpowiadają zasadom, według których działa ten remake.", false],
		[1, "", "Strony fabuły rosną razem z twoją kampanią. Rozdziały, do których jeszcze nie dotarłeś, i osoby, których jeszcze nie poznałeś, pozostają poza kompendium, a zakończenie rozdziału pojawia się dopiero po jego przejściu.", false],
	],
	"intro/world": [
		[1, "", "Świat gry: wojna Terran z Vosskami, flota kosmiczna, którą Keith Maxwell właśnie opuścił, i banici żerujący na obu stronach.", false],
	],
	"intro/story": [
		[1, "", "Kampania to jeden ciąg trzynastu rozdziałów. Każdy zaczyna się odprawą na stacji i toczy dalej w locie pełnym rozmów radiowych. Rozdziały poniżej sięgają tak daleko, jak dotarł twój pilot.", false],
	],
	"intro/characters": [
		[1, "", "Osoby, które rozmawiają z Keithem Maxwellem na odprawach i przez radio. Każdy portret pochodzi z grafik samej gry.", false],
	],
	"intro/races": [
		[1, "", "Na planetach i stacjach galaktyki żyje dziesięć ludów. Mieszkańcy miejsca decydują, jakie statki może sprzedawać jego sklep, a w przypadku Terran i Vossków także o tym, czy twoja lojalność kosztuje cię łapówkę przy przylocie.", false],
	],
	"intro/galaxy": [
		[1, "", "Galaktyka dzieli się na cztery kwadranty po dwadzieścia pięć systemów, a każdy system obejmuje pięć planet lub stacji. Mapa poniżej pokazuje je wszystkie; podróże między nimi otwierają się po kampanii albo od razu, jeśli ją pominiesz.", false],
	],
	"intro/stations": [
		[1, "", "Wszystkie pięćset planet i stacji. Poziom technologii miejsca wyznacza ceny ładunków i rabaty na statki; hangar otwarty dla wszystkich mają tylko miejsca z handlem.", false],
	],
	"intro/ships": [
		[1, "", "Statki, które możesz kupić. Różnią się kadłubem, ładownią i mocowaniami broni; sklepy większości ludów sprzedają wszystkie poza myśliwcem Vossków, który sprzedają tylko Vosskowie.", false],
	],
	"intro/equipment": [
		[1, "", "Broń i generatory osłon. Statek może nieść broń tylko wtedy, gdy ma mocowanie na ten rodzaj broni, i tylko jedną broń każdego rodzaju naraz.", false],
	],
	"intro/goods": [
		[1, "", "Ładunek znaleziony we wrakach zniszczonych statków. Każdy towar ma własną regułę tego, jak poziom technologii stacji zmienia jego cenę.", false],
	],
	"intro/jobs": [
		[1, "", "Rodzaje pracy oferowane na tablicy zleceń, gdy galaktyka jest otwarta. Nagroda zależy od zlecenia i kwadrantu, w którym jesteś.", false],
	],
	"intro/progress": [
		[1, "", "Jak gra mierzy twojego pilota: reputacja za zestrzelenia, poziom za zarobki, lojalność między Terranami a Vosskami i wiadomości, które odnotowują twoje bogactwo i odkrycia.", false],
	],
	"intro/modes": [
		[1, "", "Inne sposoby gry poza kampanią i swobodną eksploracją.", false],
	],
	"intro/guide": [
		[1, "", "Jak grać: latać, walczyć, wyposażać się, handlować, podróżować i piąć się w górę.", false],
	],
	"world/setting": [
		[1, "", "W czwartym tysiącleciu Terranie toczą międzyplanetarną wojnę z ludem [[race/1]]. Galaktykę dzielą z nimi też inne ludy: jedne sprzymierzone z którąś ze stron, inne handlujące z obiema, jeszcze inne ledwie znane.", false],
		[1, "", "Gra zaczyna się w roku 3587 na [[station/0]], terrańskiej stacji, gdzie krążownik liniowy SS Ulysses wysadza [[character/0]]. Po honorowym zwolnieniu z floty kosmicznej dostał od [[character/11|admirała Smitha]] własny statek i zamierza zarabiać na życie jako najemnik.", false],
		[1, "Gdzie to się dzieje", "Cała kampania toczy się w pierwszym kwadrancie, [[quadrant/0]], w pobliżu [[station/0]]. Reszta galaktyki otwiera się po zakończeniu fabuły.", false],
		[14, "Po wojnie", "Przywódca banitów nie żyje, na pokładzie jest napęd nadprzestrzenny, a Maxwell odrzuca miejsce we flocie. Galaktyka należy do niego: może ją odkrywać, handlować w niej i walczyć dla każdego, kto zapłaci.", false],
	],
	"world/fleet": [
		[1, "", "Terrańska flota kosmiczna to wojsko terrańskich światów. Maxwell służył w niej przed początkiem gry, a większość jego zadań w kampanii pochodzi od jej oficerów lub ich otoczenia.", false],
		[1, "", "Jej standardowym myśliwcem jest [[ship/6]]. Wśród jej oficerów w fabule są [[character/1]], która pokazuje Maxwellowi jego nowy statek, i [[character/11|admirał Smith]], który mu go dał.", false],
		[5, "", "Flota ma też agentów. Porucznik Hammond na rozkaz admirała pracuje pod przykrywką na [[station/2]].", false],
		[6, "", "Oficer bezpieczeństwa [[character/7]] tropi zdrajców wewnątrz floty.", false],
		[12, "", "Nie wszyscy jej dowódcy są lojalni: jeden z nich za plecami floty dogadywał się z Vosskami i banitami.", false],
	],
	"world/outlaws": [
		[9, "", "Banici latają zmodyfikowanymi statkami Terran i napadają na konwoje. Gdy urządzają zasadzkę na konwój Grey w głębi terytorium Vossków, staje się jasne, że współpracują z Vosskami.", false],
		[12, "", "Banici mają przywódcę w samej flocie kosmicznej, który sprzedawał Vosskom skradzione tajemnice wojskowe i tuszował ataki na transporty. Bronią się we własnej stacji za polem minowym.", false],
		[1, "", "Na mapie galaktyki banici mają też własny lud: miejsca zamieszkane przez [[race/9]] to ich stacje i planety. Tylko ich sklepy sprzedają [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell przybywa na [[station/0]], gdzie wita go porucznik [[character/1]], która ma rozkaz admirała Smitha pokazać mu nowy statek, starego zwiadowcę [[ship/0]]. Wyjaśnia mu hangar: statki, broń i wyposażenie kupuje się w sklepie, a ładunek zebrany w kosmosie sprzedaje się z ładowni.", false],
		[1, "", "Potem przychodzi lot próbny. Christine prowadzi go przez punkty nawigacyjne, objaśnia osłony, zmianę broni, strzelanie i dopalacz, a na koniec wypuszcza kilka dronów treningowych do zestrzelenia.", false],
		[2, "Zakończenie", "Maxwell niszczy drony i wraca na stację. Christine życzy mu powodzenia i ma nadzieję zobaczyć go znów w jednym kawałku.", false],
	],
	"chapter/2": [
		[2, "", "Niemile widziana twarz z floty: dowódca [[character/2]], którego Maxwell nigdy nie mógł znieść, ma dla niego robotę. Korytarz kosmiczny przy stacji trzeba oczyścić z wraków, zanim przyleci następny konwój, a na to są tylko dwie minuty.", false],
		[3, "Zakończenie", "Korytarz zostaje oczyszczony na czas, a Vlad płaci, rzucając uwagę, że Maxwell jest stworzony do tej roboty.", false],
	],
	"chapter/3": [
		[3, "", "Nerwowy mały klient, [[character/3]], chce natychmiast dostać się na [[station/1]], zanim przepadnie mu interes. Roi się tam od Vossków, ale płaci dobrze i Maxwell się zgadza.", false],
		[4, "Zakończenie", "Po drodze patrol Vossków żąda kapitulacji. Maxwell dowozi Bolara, a pasażer obiecuje go polecić, gdy tylko przestanie się trząść.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] potrzebuje eskorty dla swojego statku na [[station/2]], do pirackiej kryjówki. Maxwell podbija stawkę za ryzyko i podejrzewa, że ładunek to kolejna dostawa broni dla banitów.", false],
		[5, "Zakończenie", "Myśliwce Vossków dwukrotnie atakują frachtowiec. Dociera on na Tortugę, a Doc daje jasno do zrozumienia, że jego ładunek to nie sprawa Maxwella.", false],
	],
	"chapter/5": [
		[5, "", "Na Tortudze Maxwell wpada na [[character/1]], która działa tam pod przykrywką. Flota ma przechwycić konwój z bronią Vossków w pobliżu [[station/3]]; jeśli dostawa przejdzie, dojdzie do masakry. Jej eskadrze potrzebny jest jeszcze jeden doświadczony pilot.", false],
		[6, "Zakończenie", "Najpierw pada eskorta, potem frachtowce. Konwój zostaje zatrzymany, a Christine spodziewa się, że admirał Smith będzie zadowolony.", false],
	],
	"chapter/6": [
		[6, "", "Oficer bezpieczeństwa [[character/7]] ma zadanie, które nie może się nie udać: [[character/8]], szpieg, uciekł jednym z tajnych statków floty. Nie może on wpaść w ręce wroga, a w razie potrzeby należy go zniszczyć.", false],
		[7, "Zakończenie", "Maxwell znajduje Lockwooda w polu asteroid i uszkadza jego statek, aż ten się poddaje. Zanim ktokolwiek zdąży go zatrzymać, [[character/2|Vlad Borsikov]] go zestrzeliwuje i przypomina Maxwellowi, że rozkaz brzmiał: zniszczyć statek. Maxwell zaczyna podejrzewać, że nigdy nie chodziło tylko o statek.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] prosi o eskortę dla swoich statków na [[station/4]]. Maxwell rozpoznaje bandę Octopodów, znaną z tego, że wozi pełno kradzionego towaru, ale bierze zlecenie, dopóki władze trzymają się z daleka.", false],
		[8, "Zakończenie", "To, co zaczyna się jako łatwy zarobek, zmienia się w walkę z myśliwcami Vossków i krążownikiem. Przynajmniej jeden statek się przedostaje, a Maxwell zauważa, że Vosskowie stają się coraz agresywniejsi.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] namierzyła unieruchomiony krążownik liniowy Vossków. Flota chce go przejąć i pojmać żywcem jego dowódcę, ale najpierw trzeba zniszczyć każde stałe działo na jego kadłubie.", false],
		[9, "Zakończenie", "Podczas gdy eskadra Christine ściąga na siebie ogień, Maxwell niszczy działa, a statek zostaje wzięty abordażem.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]] z ludu Grey wynajmuje Maxwella, by przeprowadził konwój czterech statków na [[station/5]], prosto przez terytorium Vossków, i płaci za każdy statek, który dotrze.", false],
		[10, "Zakończenie", "Napastnicy to nie Vosskowie, lecz zmodyfikowane statki Terran. Maxwell ich odpiera i dochodzi do wniosku, że banici współpracują z Vosskami.", false],
	],
	"chapter/10": [
		[10, "", "[[character/11]] potrzebuje każdego wolnego pilota: stację sojuszników Terran, Nivelan, atakują silne siły Vossków. Po ostrej wymianie zdań o stawkach i lojalności Maxwella admirał wysyła go do walki.", false],
		[11, "Zakończenie", "Dowódca stacji [[character/12]] prosi Maxwella, by skupił się na krążownikach, a [[character/1|Christine]] zajmie się myśliwcami. Atak zostaje odparty, a oboje zgadzają się, że pozostałym zagrożeniem są banici.", false],
	],
	"chapter/11": [
		[11, "", "Przywódca klanu Vossków, [[character/4]], potajemnie kontaktuje się z Maxwellem. Jeden z dowódców Vossków spiskuje z terrańskim oficerem i banitami, a klan chce jego śmierci. Najlepsze miejsce na zasadzkę to mgławica Yarapu.", false],
		[12, "Zakończenie", "Maxwell niszczy krążownik dowódcy i jego eskortę. Nartok zdradza mu, że zdrajca po stronie Terran to stary znajomy Maxwella i że porucznik Hammond jest już na jego tropie.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] przynosi wiadomość: [[character/2]] jest przywódcą banitów. Jako dowódca tuszował ataki na transporty i kazał Lockwoodowi wykraść tajemnice wojskowe, by sprzedać je Vosskom. Jego banda zabarykadowała się w stacji banitów chronionej polem minowym, które Maxwell musi oczyścić przed atakiem.", false],
		[13, "Zakończenie", "Pole minowe zostaje oczyszczone, a obrońcy stacji padają. Christine rzuca się na Vlada, który zestrzeliwuje ją, zanim Maxwell zdąży ją osłonić, i ucieka.", false],
	],
	"chapter/13": [
		[13, "", "[[character/11]] składa kondolencje; Maxwell chce tylko wiedzieć, dokąd zniknął Vlad. Flota odnalazła Vlada i resztki jego banitów, a jej eskadry potrzebują pomocy Maxwella, by ich rozbić.", false],
		[14, "Zakończenie", "Gdy banici zostają rozbici, Maxwell zostawia flotę przy jej robocie, sam ściga Vlada i go zabija. Admirał proponuje mu miejsce we flocie; Maxwell odmawia. Otrzymuje napęd nadprzestrzenny, który otwiera przed nim każdy kwadrant galaktyki.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell to pilot gracza: były pilot terrańskiej floty kosmicznej, który po honorowym zwolnieniu dostaje statek od [[character/11|admirała Smitha]] i zaczyna życie najemnika na [[station/0]].", false],
		[1, "", "Jest sarkastyczny i chętnie targuje się o stawki, ale kończy zlecenia, których się podejmuje.", false],
		[7, "", "Protestuje, gdy [[character/2|Vlad Borsikov]] zestrzeliwuje człowieka, który się poddał.", false],
		[13, "", "Śmierć [[character/1|Christine Hammond]] czyni z ostatniego rozdziału sprawę osobistą.", false],
		[14, "", "Po zabiciu Vlada odmawia powrotu do floty i woli sam wybierać swoją drogę przez galaktykę.", false],
	],
	"character/1": [
		[1, "", "Porucznik Christine Hammond z terrańskiej floty kosmicznej wita Maxwella na [[station/0]], pokazuje mu statek i odbywa z nim pierwszy lot próbny. Prosi, by mówił do niej Christine.", false],
		[5, "", "Działa też jako agentka: na [[station/2]] pracuje pod przykrywką na rozkaz admirała Smitha i wciąga Maxwella do uderzenia na konwój z bronią Vossków.", false],
		[8, "", "Dowodzi eskadrą, która przejmuje unieruchomiony krążownik liniowy Vossków.", false],
		[12, "", "Odkrywa, że za banitami stoi [[character/2|Vlad Borsikov]], i planuje atak na ich stację.", false],
		[13, "", "Po bitwie rzuca się na Vlada i zostaje przez niego zestrzelona. Jej śmierć popycha Maxwella w pościg za Vladem w ostatnim rozdziale.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov to dowódca terrańskiej floty kosmicznej i, według Maxwella, najpodlejszy typ w całej flocie. Daje Maxwellowi pierwszą płatną robotę: oczyszczenie korytarza kosmicznego z wraków na czas.", false],
		[7, "", "Zestrzeliwuje szpiega Corsaira Lockwooda po tym, jak ten się poddał, i upiera się, że rozkaz brzmiał: zniszczyć statek.", false],
		[12, "", "To on jest zdrajcą: przywódcą banitów, który wykorzystywał swój stopień, by tuszować ataki na transporty, i kazał Lockwoodowi wykraść tajemnice wojskowe, które sprzedał Vosskom.", false],
		[13, "", "Gdy Christine Hammond rusza za nim po ataku na jego stację, zestrzeliwuje ją i ucieka.", false],
		[14, "", "Flota znajduje go z resztkami banitów, a Maxwell zabija go w pojedynku.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon to roztrzęsiony klient, który musi natychmiast dostać się na [[station/1]], by ratować interes, i dobrze płaci pilotowi gotowemu przewieźć go przez przestrzeń Vossków.", false],
		[4, "", "Przeżywa zasadzkę Vossków i obiecuje polecić Maxwella.", false],
	],
	"character/4": [
		[4, "", "Vossk o tej twarzy wywołuje Maxwella w drodze na Phoebos i żąda kapitulacji w imieniu Imperium Vossków.", false],
		[11, "", "Nartok Brek to przywódca klanu ludu [[race/1]]. Potajemnie kontaktuje się z Maxwellem, ponieważ jeden z jego własnych dowódców spiskuje z terrańskim oficerem i banitami, i prosi o zasadzkę na zdrajcę w mgławicy Yarapu. Zanim cokolwiek powie, żąda od Maxwella słowa honoru.", false],
		[12, "", "Po zasadzce zdradza Maxwellowi, że ten zna już terrańskiego zdrajcę.", false],
	],
	"character/5": [
		[4, "", "John Washington, przez przyjaciół zwany Dociem, potrzebuje eskorty dla swojego statku na [[station/2]]. Oferuje 3000 kredytów i godzi się na 4500, pod warunkiem że nie będzie świadków. Maxwell podejrzewa dostawę broni dla banitów.", false],
		[5, "", "Jego ładunek dociera. Czym był, zachowuje dla siebie.", false],
	],
	"character/6": [
		[6, "", "Pilot z eskadry Christine Hammond, który pyta przez radio, czy ten Maxwell w ogóle ma doświadczenie bojowe, nie zauważając, że on to słyszy.", false],
		[13, "", "Ta sama eskadra zostaje, by zabezpieczyć stację banitów, podczas gdy Christine i Maxwell ścigają Vlada.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom jest oficerem bezpieczeństwa floty kosmicznej. Wysyła Maxwella za szpiegiem [[character/8]] z rozkazem, że skradziony statek nie może wpaść w ręce wroga.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood to szpieg, który uciekł jednym z tajnych statków floty kosmicznej.", false],
		[7, "", "Osaczony w polu asteroid poddaje się, a mimo to Vlad Borsikov go zestrzeliwuje.", false],
		[12, "", "Później okazuje się, że to Vlad zlecił mu kradzież tajemnic wojskowych.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt wozi towary dla bandy Octopodów, znanej z przewożenia kradzionego towaru. Zapewnia, że wszystko na pokładzie jest całkowicie legalne, i płaci Maxwellowi za doprowadzenie jego statków na [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor z ludu Grey słyszał o Maxwellu i proponuje mu trudne zlecenie: cztery statki na [[station/5]] przez terytorium Vossków, po 4000 kredytów za każdy statek, który dotrze.", false],
	],
	"character/11": [
		[1, "", "Admirał Smith z terrańskiej floty kosmicznej dał Maxwellowi statek po zwolnieniu i kazał porucznik Hammond pokazać mu, jak go używać.", false],
		[10, "", "Wzywa Maxwella, gdy stacja Nivelan zostaje zaatakowana. Rozmowa zaostrza się, gdy Maxwell mówi o swoich stawkach i o tym, ile mogliby zapłacić Vosskowie.", false],
		[13, "", "Po śmierci Christine składa Maxwellowi kondolencje i zdradza, gdzie są banici Vlada.", false],
		[14, "", "Pozwala Maxwellowi samotnie ścigać Vlada, proponuje mu miejsce we flocie, a gdy ten odmawia, daje mu napęd nadprzestrzenny.", false],
	],
	"character/12": [
		[11, "", "Botom Krant dowodzi stacją Nivelan zaatakowaną przez Vossków. Prosi Maxwella, by skupił się na krążownikach, i dziękuje mu po odparciu ataku.", false],
	],
	"race/0": [
		[1, "", "Ludzie, w czwartym tysiącleciu w stanie wojny z ludem [[race/1]]. Maxwell jest Terraninem, a większość klientów kampanii służy w terrańskiej flocie kosmicznej. Terranie mają więcej planet i stacji niż jakikolwiek inny lud.", false],
		[1, "", "Wiele statków na sprzedaż to konstrukcje Terran: [[ship/0]], [[ship/6]] i jej zmodyfikowana wersja [[ship/7]] oraz kanonierka [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "Wrogowie Terran. Sklepy Vossków sprzedają tylko własny myśliwiec, [[ship/8]], i tylko one sprzedają broń Vossków. Pilot pracujący dla Terran musi płacić łapówki na stacjach Vossków, i odwrotnie.", false],
	],
	"race/2": [
		[1, "", "Jeden z ludów galaktyki, z własnymi planetami i stacjami.", false],
	],
	"race/3": [
		[1, "", "Jeden z ludów galaktyki, z własnymi planetami i stacjami.", false],
	],
	"race/4": [
		[1, "", "Ich specjalne podzespoły trafiają do broni takiej jak [[equipment/23]], a ciężki bombowiec [[ship/3]] jest ich dziełem.", false],
	],
	"race/5": [
		[1, "", "Statki Grey słyną z niezwykle ciężkiego pancerza. Zwiadowca [[ship/9]] pochodzi z ich floty i dopiero niedawno przystosowano go do pilotów humanoidalnych, a pocisk [[equipment/4]] zbudowano z podzespołów Grey. Feknor z ludu Grey wynajmuje Maxwella do niebezpiecznego konwoju.", false],
	],
	"race/6": [
		[1, "", "Sojusznicy Terran. Myśliwiec [[ship/1]] to konstrukcja Nivelan, a laser [[equipment/2]] opiera się na ich technologii uzbrojenia. Atak Vossków na jedną z ich stacji na dobre wciąga Maxwella w wojnę.", false],
	],
	"race/7": [
		[1, "", "Jeden z ludów galaktyki, z własnymi planetami i stacjami.", false],
	],
	"race/8": [
		[1, "", "Jeden z ludów galaktyki, z własnymi planetami i stacjami.", false],
	],
	"race/9": [
		[1, "", "Banici to nie lud, lecz sposób życia: piraci i przemytnicy z własnymi planetami i stacjami. Tylko ich sklepy sprzedają [[ship/7]], a [[station/2]] to ich najbardziej znana kryjówka.", false],
	],
	"galaxy": [
		[1, "", "Cztery kwadranty, sto systemów i pięćset planet i stacji. Każdy kwadrant jest trudniejszy od poprzedniego: zlecenia płacą więcej, wrogowie są twardsi, a sklepy sprzedają lepsze wyposażenie.", false],
		[1, "", "Lot w obrębie kwadrantu kosztuje kredyty zależnie od odległości; przejście do sąsiedniego lub przeciwległego kwadrantu kosztuje dodatkowo. Gdy odwiedzisz każde miejsce w galaktyce, podróże są darmowe.", false],
	],
	"progress/ranks": [
		[1, "Reputacja", "Reputacja liczy zniszczonych przez ciebie wrogów. Każdy próg z tabeli poniżej podnosi twoją rangę, widoczną na ekranie „Status”.", false],
		[1, "Poziom", "Twój poziom rośnie wraz z pieniędzmi zarobionymi na misjach i zleceniach. Gdy łączne zarobki przekroczą 1,6-krotność stanu z poprzedniego poziomu, osiągasz kolejny. Wyższe poziomy czynią wrogów w twoich misjach twardszymi.", false],
	],
	"progress/milestones": [
		[1, "", "Po zadokowaniu stacja wita cię wiadomością, gdy twoje kredyty po raz pierwszy przekroczą kamień milowy albo twoja eksploracja galaktyki osiągnie nowy próg. Wiadomości poniżej pochodzą z samej gry.", false],
		[1, "Bogactwo", "Bogactwo to coś więcej niż liczba. Mając ponad 999 999 kredytów, możesz handlować na każdej planecie i stacji: hangar otwiera się nawet tam, gdzie nie ma handlu, i możesz tam kupować, sprzedawać ładunek i łupy oraz przezbrajać statek.", false],
		[1, "Eksploracja", "Liczy się każde odwiedzone miejsce. Odwiedzenie wszystkich pięciuset sprawia, że każda podróż jest darmowa.", false],
	],
	"progress/loyalty": [
		[1, "", "Twoja lojalność leży gdzieś między Terranami a Vosskami, co pokazuje wskaźnik na ekranie „Status”. Każda misja dla klienta Terran przesuwa ją o krok ku Terranom, każda misja dla klienta Vossków o krok ku Vosskom. Nie może przekroczyć dziesięciu kroków w żadną stronę.", false],
		[1, "", "Gdy lecisz do miejsca Terran, a twoja lojalność skłania się ku Vosskom, albo do miejsca Vossków, gdy skłania się ku Terranom, oprócz kosztów lotu żąda się od ciebie łapówki: 150 kredytów za każdy krok. Zapłacenie łapówki przesuwa lojalność o krok z powrotem ku środkowi.", false],
	],
	"mode/survival": [
		[1, "", "Przetrwanie to osobny tryb z własnym pilotem i tabelą wyników. Wybierz go w „Start Game”. Wrogie statki wciąż nadlatują, każde zestrzelenie daje punkty i naprawia kadłub, a kolor ramki wroga pokazuje, jak jest silny. Wynik daje ci rangę z tabeli poniżej.", false],
	],
	"mode/swarm": [
		[1, "", "Rój to tryb napisany dla tego remake'u, dostępny w „Start Game”. Zaczyna się od garstki myśliwców i rośnie w tłum zaciskający się ze wszystkich stron, z falami po piątej minucie.", false],
		[1, "", "Każde zestrzelenie napełnia pasek poziomu. Każdy poziom oferuje trzy karty ulepszeń: nową broń, lepszą wersję posiadanej, dodatkową lufę, większy zasięg lub prędkość pocisków, silniejszą osłonę, naprawę przy każdym zestrzeleniu albo inny kadłub. Odrzucenie karty naprawia zamiast tego ćwierć kadłuba.", false],
		[1, "", "Broń, osłony i kadłuby pochodzą z twojego pliku gry. Osiągnięcie rangi w rankingu Przetrwania odblokowuje kolejny kadłub dla Roju.", false],
	],
	"guide/start": [
		[1, "", "Po zaimportowaniu pliku gry „Start Game” oferuje kampanię, swobodną eksplorację, Przetrwanie i Rój. Kampania zaczyna się na [[station/0]] ze statkiem [[ship/0]] i 5000 kredytów.", false],
		[1, "Menu stacji", "Na stacji „Info” opisuje miejsce, „Hangar” otwiera sklep i twój statek, „Missions” pokazuje tablicę zleceń, a „Map” pozwala podróżować. W czasie kampanii tablica zleceń i mapa są zablokowane, a „Go on” rozpoczyna następną odprawę. „Status” pokazuje poziom, reputację, czas gry, zestrzelenia i lojalność, a w „Menu” są opcje i zapis gry.", false],
		[1, "", "Nie każde miejsce ma hangar otwarty dla wszystkich: bez handlu hangar otwiera się tylko w czasie kampanii albo gdy masz ponad 999 999 kredytów.", false],
	],
	"guide/flight": [
		[1, "", "Punkty nawigacyjne są oznaczone na żółto, sojusznicy na zielono, a wrogowie na czerwono. Obiekty poza polem widzenia pojawiają się na krawędzi ekranu. Pozostała siła wroga jest widoczna pod jego znacznikiem.", false],
		[1, "", "Osłona pochłania zderzenia i trafienia i z czasem się odnawia; gdy się wyczerpie, obrażenia trafiają w kadłub. Dopalacz daje krótki zryw prędkości i potrzebuje czasu na naładowanie.", false],
		[1, "Sterowanie", "Na klawiaturze steruj myszą lub strzałkami, ciąg ustawiaj klawiszami W i S, a w bok przesuwaj się A i D. Strzelaj kliknięciem lub Spacją, zmieniaj broń klawiszem Q, odpalaj pociski klawiszem F, a dopalacz włączaj Shiftem. R włącza autopilota, T przyspiesza czas na bezpiecznych odcinkach, E dokuje przy stacji, a Esc pauzuje. Kontroler celuje prawą gałką i strzela prawym spustem. Sterowanie dotykowe ma gałkę, przepustnicę i przyciski ognia, pocisków, dopalacza i nawigacji; dwukrotne stuknięcie Ognia włącza ogień automatyczny.", false],
		[1, "Autopilot i czas", "Autopilot leci do następnego punktu nawigacyjnego lub do stacji. Gdy nic ci nie grozi, czas może płynąć szybciej; wrogowie, obrażenia lub dotarcie do celu przywracają go do normy.", false],
	],
	"guide/weapons": [
		[1, "", "Statki mają mocowania na pięć rodzajów broni: lasery, działa plazmowe, działa fotonowe, pociski i działa termiczne. Każde mocowanie mieści jedną broń, a każdy statek ma własny zestaw mocowań. Generator osłony pasuje do każdego statku.", false],
		[1, "", "Lasery i działa plazmowe strzelają szybko na średnim dystansie. Działa fotonowe sięgają najdalej i trafiają najmocniej na strzał, ale wolno się przeładowują. Działa termiczne sieją cząstkami z bliska z bardzo dużą szybkostrzelnością. Pociski odpala się osobnym przyciskiem, bez zmiany broni, i zadają ciężkie obrażenia przy długim przeładowaniu.", false],
		[1, "", "Osłony różnią się pojemnością i szybkością odnawiania. Najsilniejszą broń sprzedaje się dopiero od drugiego kwadrantu, a broń Vossków tylko w sklepach Vossków.", false],
	],
	"guide/hangar": [
		[1, "", "Hangar ma trzy części: „Ship” pokazuje twój statek z zamontowaną bronią i osłoną, „Cargo” mieści twoje towary i zapasowe wyposażenie, a „Shop” oferuje asortyment stacji.", false],
		[1, "", "Kupione wyposażenie trafia do ładowni; zamontuj je stamtąd, jeśli statek ma na nie wolne mocowanie. Wyposażenie i statki odsprzedaje się za połowę ceny.", false],
		[1, "", "Kupno statku oznacza oddanie obecnego w rozliczeniu. Wyposażenie pasujące do nowego statku pozostaje zamontowane, a reszta trafia do ładowni, o ile jest w niej miejsce.", false],
		[1, "", "Sklepy sprzedają od jednej do czterech broni lub osłon i do trzech statków, wybranych spośród tego, na co pozwalają kwadrant i lud miejsca. Asortyment odnawia się, gdy wracasz po locie gdzie indziej. W czasie kampanii każdy rozdział ma własny, stały asortyment.", false],
	],
	"guide/trade": [
		[1, "", "Towary pochodzą z wraków zniszczonych statków i po misji trafiają do ładowni. Sprzedawaj je w części ładunku w hangarze. Jedne są najcenniejsze tam, gdzie technologia jest niska, inne tam, gdzie jest wysoka, a jeszcze inne wszędzie kosztują tyle samo; strona każdego towaru podaje jego cenę na każdym poziomie technologii.", false],
		[1, "", "Sklepy nie mają własnych towarów. To, co sprzedasz w sklepie, zostaje w jego asortymencie i możesz to tam odkupić po tej samej cenie.", false],
		[1, "", "Handel wymaga hangaru: planety i stacje bez handlu otwierają swój tylko pilotom mającym ponad 999 999 kredytów.", false],
	],
	"guide/travel": [
		[1, "", "Mapa pokazuje galaktykę, jej kwadranty i systemy. Wybierz miejsce i poleć tam za pokazany koszt lotu, plus łapówkę, jeśli twoja lojalność jest przeciwna jego ludowi. Przylatujesz już zadokowany.", false],
		[1, "", "Koszt lotu rośnie z odległością. Zmiana kwadrantu dodaje 15 000 kredytów do ceny, a przeciwległy kwadrant 30 000. Mapa pokazuje, jaką część galaktyki odkryłeś; gdy odwiedzisz każde miejsce, podróże nic nie kosztują.", false],
		[1, "", "Galaktyka otwiera się, gdy kampania jest ukończona albo gdy ją pominiesz.", false],
	],
	"guide/jobs": [
		[1, "", "Poza kampanią tablica zleceń każdej stacji oferuje kilka zleceń od klientów różnych ludów. Każde pokazuje trudność i nagrodę; trudne zlecenia płacą więcej, podobnie jak dalsze kwadranty.", false],
		[1, "", "Od czasu do czasu podejrzany kombinator oferuje zlecenie płatne o czterdzieści procent więcej niż zwykle. Wykonane zlecenie wypłaca nagrodę i przesuwa twoją lojalność ku ludowi klienta.", false],
	],
	"guide/campaign": [
		[1, "", "Kampania to ciąg trzynastu misji. Wykonana misja wypłaca nagrodę; nieudaną można powtórzyć. Po jej ukończeniu napęd nadprzestrzenny otwiera galaktykę, a tablica zleceń i mapa stają się dostępne.", false],
		[1, "", "„Pomiń kampanię · Eksploruj” w menu startowym lub w menu stacji prowadzi prosto do swobodnej eksploracji. Pominięcie nie daje nagród za ukończenie i zachowuje pilota kampanii w jego własnym slocie.", false],
	],
	"guide/saves": [
		[1, "", "Gra zapisuje się automatycznie po każdej misji i w punktach kontrolnych. Kampania, eksploracja, Przetrwanie i Rój mają osobne zapisy. „Wczytaj / odzyskaj” w menu pauzy albo „Load” po porażce wraca do ostatniego autozapisu, początku lotu lub ostatniej stacji.", false],
		[1, "", "„Pliki gry” → „Przenieś zapisy” przenosi twoje zapisy na inne urządzenie, które zaimportowało ten sam plik gry.", false],
	],
	"guide/tips": [
		[1, "", "Sprzedaj ładunek z wraków, zanim kupisz wyposażenie; na małych statkach ładownia szybko się zapełnia.", true],
		[1, "", "Sprawdź mocowania statku, zanim kupisz do niego broń: broń bez pasującego mocowania zostaje w ładowni.", true],
		[1, "", "Trzymaj towary, aż zadokujesz tam, gdzie poziom technologii im sprzyja.", true],
		[1, "", "Latanie tylko dla jednej strony sprawia, że wizyty na stacjach drugiej są drogie.", true],
		[1, "", "Odwiedzaj nowe miejsca, skoro i tak podróżujesz: odkrycie całej galaktyki sprawia, że każda podróż jest darmowa.", true],
	],
}
