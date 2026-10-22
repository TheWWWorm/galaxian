extends RefCounted
## The reference's own writing in Spanish. Same blocks, chapter gates and links
## as prose/en.gd; see there for the format.

const PAGES := {
	"home": {"title": "Referencia"},
	"world/setting": {"title": "Una galaxia en guerra"},
	"world/fleet": {"title": "La flota espacial Terran"},
	"world/outlaws": {"title": "Forajidos y piratas"},
	"chapter/1": {"title": "Una nave nueva"},
	"chapter/2": {"title": "Chatarra espacial"},
	"chapter/3": {"title": "Pasaje a Phoebos"},
	"chapter/4": {"title": "La carga de Doc"},
	"chapter/5": {"title": "El convoy de armas"},
	"chapter/6": {"title": "El espía fugitivo"},
	"chapter/7": {"title": "Mercancía delicada"},
	"chapter/8": {"title": "Abordaje al gigante"},
	"chapter/9": {"title": "Cuatro naves a Opos"},
	"chapter/10": {"title": "El frente niveliano"},
	"chapter/11": {"title": "Emboscada en la nebulosa"},
	"chapter/12": {"title": "La estación forajida"},
	"chapter/13": {"title": "Venganza"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Piloto mercenario"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Teniente de la flota espacial"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Comandante de la flota espacial"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Pasajero con prisa"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Jefe de clan vossk", "early_title": "Piloto vossk"},
	"character/5": {"title": "John «Doc» Washington", "subtitle": "Comerciante"},
	"character/6": {"title": "Piloto de escuadrón", "subtitle": "Flota espacial"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Oficial de seguridad"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Espía a la fuga"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Comerciante Octopod"},
	"character/10": {"title": "Feknor", "subtitle": "De los Grey"},
	"character/11": {"title": "Almirante Smith", "subtitle": "Flota espacial Terran"},
	"character/12": {"title": "Botom Krant", "subtitle": "Comandante de estación niveliano"},
	"progress/ranks": {"title": "Reputación y nivel"},
	"progress/milestones": {"title": "Hitos"},
	"progress/loyalty": {"title": "Lealtad y sobornos"},
	"mode/survival": {"title": "Supervivencia", "subtitle": "Modo de juego"},
	"mode/swarm": {"title": "Enjambre", "subtitle": "Modo de juego del remake"},
	"guide/start": {"title": "Primeros pasos"},
	"guide/flight": {"title": "Volar y combatir"},
	"guide/weapons": {"title": "Armas y escudos"},
	"guide/hangar": {"title": "El hangar"},
	"guide/trade": {"title": "Comercio y botín"},
	"guide/travel": {"title": "Viajes y mapa"},
	"guide/jobs": {"title": "El tablón de trabajos"},
	"guide/campaign": {"title": "Campaña y exploración libre"},
	"guide/saves": {"title": "Guardar y cargar"},
	"guide/tips": {"title": "Consejos"},
}

const BLOCKS := {
	"home": [
		[1, "", "Esta referencia describe tu propia copia de Galaxy on Fire: cada planeta y estación de la galaxia, las naves, armas y mercancías de sus tiendas, los trabajos de sus tablones, los personajes de su historia y las reglas del comercio, los viajes y la reputación. Los nombres, descripciones y diálogos proceden del archivo de juego que importaste; las cifras siguen las reglas con las que juega este remake.", false],
		[1, "", "Las páginas de la historia crecen con tu campaña. Los capítulos que aún no has alcanzado y las personas que no conoces quedan fuera de la referencia, y el desenlace de un capítulo aparece cuando lo has jugado.", false],
	],
	"intro/world": [
		[1, "", "El trasfondo del juego: la guerra entre Terran y vossk, la flota espacial que Keith Maxwell acaba de dejar y los forajidos que atacan a ambos bandos.", false],
	],
	"intro/story": [
		[1, "", "La campaña es una sola línea de trece capítulos. Cada uno empieza con instrucciones en una estación y sigue con un vuelo lleno de llamadas por radio. Los capítulos de abajo llegan hasta donde ha llegado tu piloto.", false],
	],
	"intro/characters": [
		[1, "", "Las personas que hablan con Keith Maxwell en las instrucciones y por radio. Cada retrato procede del arte del propio juego.", false],
	],
	"intro/races": [
		[1, "", "Diez pueblos viven en los planetas y estaciones de la galaxia. Los habitantes de un lugar deciden qué naves puede vender su tienda y, en el caso de Terran y vossk, si tu lealtad te cuesta un soborno al viajar allí.", false],
	],
	"intro/galaxy": [
		[1, "", "La galaxia se divide en cuatro cuadrantes de veinticinco sistemas cada uno, y cada sistema contiene cinco planetas o estaciones. El mapa de abajo los muestra todos; los viajes entre ellos se abren al terminar la campaña, o enseguida si la saltas.", false],
	],
	"intro/stations": [
		[1, "", "Los quinientos planetas y estaciones. El nivel tecnológico de un lugar fija sus precios de carga y sus descuentos en naves; solo los lugares con comercio tienen un hangar abierto a todos.", false],
	],
	"intro/ships": [
		[1, "", "Las naves que puedes comprar. Casco, bodega y soportes de armas las distinguen; las tiendas de casi todos los pueblos las venden todas salvo el caza vossk, que solo venden los vossk.", false],
	],
	"intro/equipment": [
		[1, "", "Armas y generadores de escudo. Una nave solo puede llevar un arma si tiene un soporte para ese tipo de arma, y solo un arma de cada tipo a la vez.", false],
	],
	"intro/goods": [
		[1, "", "Carga hallada entre los restos de naves destruidas. Cada mercancía sigue su propia regla sobre cómo el nivel tecnológico de una estación cambia su precio.", false],
	],
	"intro/jobs": [
		[1, "", "Los tipos de trabajo que ofrece el tablón una vez abierta la galaxia. La recompensa depende del trabajo y del cuadrante en el que estés.", false],
	],
	"intro/progress": [
		[1, "", "Cómo mide el juego a tu piloto: reputación por derribos, nivel por ganancias, lealtad entre Terran y vossk, y los mensajes que celebran tu riqueza y tu exploración.", false],
	],
	"intro/modes": [
		[1, "", "Otras formas de jugar además de la campaña y la exploración libre.", false],
	],
	"intro/guide": [
		[1, "", "Cómo jugar: volar, combatir, equiparse, comerciar, viajar y abrirse camino.", false],
	],
	"world/setting": [
		[1, "", "En el cuarto milenio, los Terran libran una guerra interplanetaria contra los [[race/1]]. Otros pueblos comparten la galaxia con ellos: unos aliados con un bando, otros comerciando con ambos y otros apenas conocidos.", false],
		[1, "", "El juego empieza en el año 3587 en [[station/0]], una estación Terran, donde el crucero de batalla SS Ulysses deja a [[character/0]]. Tras una baja honrosa de la flota espacial, ha recibido una nave propia del [[character/11|almirante Smith]] y piensa ganarse la vida como mercenario.", false],
		[1, "Dónde ocurre", "Toda la campaña transcurre en el primer cuadrante, [[quadrant/0]], cerca de [[station/0]]. El resto de la galaxia se abre cuando termina la historia.", false],
		[14, "Después de la guerra", "Con el cabecilla de los forajidos muerto y un motor hiperespacial a bordo, Maxwell rechaza un puesto en la flota. La galaxia es suya para explorarla, comerciar en ella y luchar para quien pague.", false],
	],
	"world/fleet": [
		[1, "", "La flota espacial Terran es el ejército de los mundos Terran. Maxwell sirvió en ella antes de que empiece el juego, y la mayoría de sus misiones de campaña vienen de sus oficiales o de su entorno.", false],
		[1, "", "Su caza estándar es la [[ship/6]]. Entre sus oficiales en la historia están [[character/1]], que enseña a Maxwell su nueva nave, y el [[character/11|almirante Smith]], que se la dio.", false],
		[5, "", "La flota también tiene agentes. La teniente Hammond trabaja de incógnito en [[station/2]] por orden del almirante.", false],
		[6, "", "El oficial de seguridad [[character/7]] persigue a los traidores dentro de la flota.", false],
		[12, "", "No todos sus comandantes son leales: uno de ellos ha tratado con los vossk y los forajidos a espaldas de la flota.", false],
	],
	"world/outlaws": [
		[9, "", "Los forajidos pilotan naves Terran modificadas y atacan convoyes. Cuando tienden una emboscada a un convoy grey en pleno territorio vossk, queda claro que trabajan con los vossk.", false],
		[12, "", "Los forajidos tienen un cabecilla dentro de la propia flota espacial, que vendió secretos militares robados a los vossk y encubrió los ataques a los transportes. Resisten en una estación propia tras un campo de minas.", false],
		[1, "", "Los forajidos también tienen su propio pueblo en el mapa de la galaxia: los lugares habitados por [[race/9]] son sus estaciones y planetas. Sus tiendas son las únicas que venden la [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell llega a [[station/0]] y lo recibe la teniente [[character/1]], que tiene órdenes del almirante Smith de enseñarle su nueva nave, una vieja exploradora [[ship/0]]. Ella le explica el hangar: naves, armas y equipo se compran en la tienda, y la carga recogida en el espacio se vende desde la bodega.", false],
		[1, "", "Luego viene un vuelo de prueba. Christine lo guía por los puntos de ruta, le explica los escudos, el cambio de arma, el disparo y el impulso, y al final suelta unos drones de entrenamiento para derribar.", false],
		[2, "Desenlace", "Maxwell destruye los drones y vuelve a la estación. Christine le desea suerte y espera volver a verlo de una pieza.", false],
	],
	"chapter/2": [
		[2, "", "Una cara poco grata de la flota: el comandante [[character/2]], al que Maxwell nunca ha soportado, tiene un trabajo para él. Hay que limpiar de restos un corredor espacial cerca de la estación antes de que llegue el próximo convoy, y solo hay dos minutos para hacerlo.", false],
		[3, "Desenlace", "El corredor queda limpio a tiempo y Vlad paga, comentando que Maxwell está hecho para este trabajo.", false],
	],
	"chapter/3": [
		[3, "", "Un cliente pequeño y nervioso, [[character/3]], quiere que lo lleven a [[station/1]] de inmediato, antes de que se le caiga un negocio. El lugar está plagado de vossk, pero paga bien y Maxwell acepta.", false],
		[4, "Desenlace", "Por el camino, una patrulla vossk les exige rendirse. Maxwell hace llegar a Bolar, y el pasajero promete recomendarlo en cuanto deje de temblar.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] necesita escolta para su nave hasta [[station/2]], la guarida de los piratas. Maxwell sube la tarifa por el riesgo y sospecha que la carga es otro envío de armas para los forajidos.", false],
		[5, "Desenlace", "Los cazas vossk atacan al carguero dos veces. Llega a Tortuga, y Doc deja claro que lo que llevaba no es asunto de Maxwell.", false],
	],
	"chapter/5": [
		[5, "", "En Tortuga, Maxwell se encuentra con [[character/1]], que está allí de incógnito. La flota tiene órdenes de interceptar un convoy de armas vossk cerca de [[station/3]]; si el envío pasa, habrá una masacre. Su escuadrón necesita otro piloto experimentado.", false],
		[6, "Desenlace", "Primero cae la escolta y luego los cargueros. El convoy queda detenido, y Christine espera que el almirante Smith quede satisfecho.", false],
	],
	"chapter/6": [
		[6, "", "El oficial de seguridad [[character/7]] tiene un trabajo que no puede salir mal: [[character/8]], un espía, ha huido con una de las naves secretas de la flota. No debe caer en manos enemigas y, si hace falta, hay que destruirla.", false],
		[7, "Desenlace", "Maxwell encuentra a Lockwood en un campo de asteroides y daña su nave hasta que se rinde. Antes de que nadie pueda detenerlo, [[character/2|Vlad Borsikov]] lo derriba y recuerda a Maxwell que la orden era destruir la nave. Maxwell empieza a sospechar que nunca se trató solo de una nave.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] pide escolta para sus naves hasta [[station/4]]. Maxwell reconoce a la banda Octopod, famosa por ir repleta de mercancía robada, pero acepta mientras las autoridades se mantengan al margen.", false],
		[8, "Desenlace", "Lo que empieza como dinero fácil se convierte en una lucha contra cazas vossk y un crucero. Al menos una nave pasa, y Maxwell nota que los vossk se vuelven más agresivos.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] ha localizado un crucero de batalla vossk inutilizado. La flota quiere capturarlo y tomar vivo a su comandante, pero antes hay que destruir cada cañón fijo de su casco.", false],
		[9, "Desenlace", "Mientras el escuadrón de Christine atrae el fuego, Maxwell elimina los cañones y la nave es abordada.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]], de los Grey, contrata a Maxwell para llevar un convoy de cuatro naves hasta [[station/5]], atravesando el territorio vossk, y paga por cada nave que llegue.", false],
		[10, "Desenlace", "Los atacantes no son vossk sino naves Terran modificadas. Maxwell los repele y concluye que los forajidos trabajan con los vossk.", false],
	],
	"chapter/10": [
		[10, "", "El [[character/11]] necesita a todos los pilotos disponibles: una estación de los aliados de los Terran, los nivelianos, sufre el ataque de fuertes fuerzas vossk. Tras un tenso intercambio sobre los precios y las lealtades de Maxwell, el almirante lo envía.", false],
		[11, "Desenlace", "El comandante de la estación, [[character/12]], pide a Maxwell que se centre en los cruceros mientras [[character/1|Christine]] se ocupa de los cazas. El ataque es rechazado, y ambos coinciden en que los forajidos son el peligro que queda.", false],
	],
	"chapter/11": [
		[11, "", "Un jefe de clan vossk, [[character/4]], contacta en secreto con Maxwell. Uno de los comandantes vossk conspira con un oficial Terran y los forajidos, y el clan lo quiere muerto. El mejor lugar para una emboscada es la nebulosa Yarapu.", false],
		[12, "Desenlace", "Maxwell destruye el crucero del comandante y su escolta. Nartok le cuenta que el traidor del lado Terran es un viejo conocido de Maxwell, y que la teniente Hammond ya le sigue la pista.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] trae la noticia: [[character/2]] es el cabecilla de los forajidos. Como comandante encubrió los ataques a los transportes e hizo que Lockwood robara secretos militares para vendérselos a los vossk. Su banda se ha atrincherado en una estación forajida protegida por un campo de minas, que Maxwell debe despejar antes del ataque.", false],
		[13, "Desenlace", "El campo de minas queda despejado y los defensores de la estación caen. Christine se lanza contra Vlad, que la derriba antes de que Maxwell pueda cubrirla, y escapa.", false],
	],
	"chapter/13": [
		[13, "", "El [[character/11]] le da el pésame; Maxwell solo quiere saber adónde ha ido Vlad. La flota ha encontrado a Vlad y a los últimos de sus forajidos, y sus escuadrones necesitan la ayuda de Maxwell para acabar con ellos.", false],
		[14, "Desenlace", "Una vez derrotados los forajidos, Maxwell deja a la flota con su trabajo, persigue a Vlad en solitario y lo mata. El almirante le ofrece un puesto en la flota; Maxwell lo rechaza. Recibe un motor hiperespacial, que le abre todos los cuadrantes de la galaxia.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell es el piloto del jugador: un antiguo piloto de la flota espacial Terran que, tras una baja honrosa, recibe una nave del [[character/11|almirante Smith]] y empieza una vida de mercenario en [[station/0]].", false],
		[1, "", "Es sarcástico y rápido para regatear sus tarifas, pero termina los trabajos que acepta.", false],
		[7, "", "Protesta cuando [[character/2|Vlad Borsikov]] derriba a un hombre que se había rendido.", false],
		[13, "", "La muerte de [[character/1|Christine Hammond]] convierte el último capítulo en algo personal.", false],
		[14, "", "Tras matar a Vlad, rechaza volver a la flota y prefiere elegir su propio camino por la galaxia.", false],
	],
	"character/1": [
		[1, "", "La teniente Christine Hammond, de la flota espacial Terran, recibe a Maxwell en [[station/0]], le enseña su nave y hace con él su primer vuelo de prueba. Le pide que la llame Christine.", false],
		[5, "", "También trabaja como agente: en [[station/2]] está de incógnito por orden del almirante Smith, y suma a Maxwell al ataque contra el convoy de armas vossk.", false],
		[8, "", "Dirige el escuadrón que captura un crucero de batalla vossk inutilizado.", false],
		[12, "", "Descubre que [[character/2|Vlad Borsikov]] está detrás de los forajidos y planea el ataque a su estación.", false],
		[13, "", "Se lanza contra Vlad tras la batalla y él la derriba. Su muerte lanza a Maxwell tras Vlad en el último capítulo.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov es comandante de la flota espacial Terran y, en palabras de Maxwell, el tipo más miserable que hay en ella. Le da a Maxwell su primer trabajo pagado: limpiar de restos un corredor espacial contrarreloj.", false],
		[7, "", "Derriba al espía Corsair Lockwood después de que este se rinda, e insiste en que la orden era destruir la nave.", false],
		[12, "", "Él es el traidor: el cabecilla de los forajidos, que usó su rango para encubrir los ataques a los transportes e hizo que Lockwood robara secretos militares que vendió a los vossk.", false],
		[13, "", "Cuando Christine Hammond va tras él después del ataque a su estación, la derriba y escapa.", false],
		[14, "", "La flota lo encuentra con los últimos de sus forajidos, y Maxwell lo mata en un duelo.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon es un cliente inquieto que necesita llegar a [[station/1]] de inmediato para salvar un negocio, y paga bien a un piloto dispuesto a llevarlo por el espacio vossk.", false],
		[4, "", "Sobrevive a la emboscada vossk y promete recomendar a Maxwell.", false],
	],
	"character/4": [
		[4, "", "Un vossk con esta cara llama a Maxwell de camino a Phoebos y exige su rendición en nombre del Imperio vossk.", false],
		[11, "", "Nartok Brek es un jefe de clan de los [[race/1]]. Contacta en secreto con Maxwell porque uno de sus propios comandantes conspira con un oficial Terran y los forajidos, y pide que se embosque al traidor en la nebulosa Yarapu. Exige la palabra de honor de Maxwell antes de decir nada.", false],
		[12, "", "Tras la emboscada, le cuenta a Maxwell que Maxwell ya conoce al traidor Terran.", false],
	],
	"character/5": [
		[4, "", "John Washington, a quien sus amigos llaman Doc, necesita escolta para su nave hasta [[station/2]]. Ofrece 3000 créditos y acepta 4500, con la condición de que no haya testigos. Maxwell sospecha un envío de armas para los forajidos.", false],
		[5, "", "Su carga llega. Qué era, se lo guarda para él.", false],
	],
	"character/6": [
		[6, "", "Un piloto del escuadrón de Christine Hammond, que pregunta por radio si ese Maxwell tiene experiencia en combate siquiera, sin darse cuenta de que él lo oye.", false],
		[13, "", "El mismo escuadrón se queda para asegurar la estación forajida mientras Christine y Maxwell persiguen a Vlad.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom es el oficial de seguridad de la flota espacial. Envía a Maxwell tras el espía [[character/8]], con la orden de que la nave robada no caiga en manos enemigas.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood es un espía que huyó con una de las naves secretas de la flota espacial.", false],
		[7, "", "Acorralado en un campo de asteroides, se rinde, y aun así Vlad Borsikov lo derriba.", false],
		[12, "", "Más tarde se descubre que fue Vlad quien le encargó robar secretos militares.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt transporta carga para la banda Octopod, famosa por llevar mercancía robada. Insiste en que todo lo que hay a bordo es completamente legal y paga a Maxwell por llevar sus naves hasta [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor, de los Grey, ha oído hablar de Maxwell y le ofrece un trabajo difícil: cuatro naves hasta [[station/5]] cruzando el territorio vossk, a 4000 créditos por cada nave que llegue.", false],
	],
	"character/11": [
		[1, "", "El almirante Smith, de la flota espacial Terran, dio a Maxwell su nave tras su baja y encarga a la teniente Hammond que le enseñe a usarla.", false],
		[10, "", "Llama a Maxwell cuando atacan la estación niveliana. La conversación se pone tensa cuando Maxwell habla de sus precios y de lo que podrían pagar los vossk.", false],
		[13, "", "Tras la muerte de Christine, da el pésame a Maxwell y le revela dónde están los forajidos de Vlad.", false],
		[14, "", "Deja que Maxwell persiga a Vlad en solitario, le ofrece un puesto en la flota y le da un motor hiperespacial cuando lo rechaza.", false],
	],
	"character/12": [
		[11, "", "Botom Krant está al mando de la estación niveliana atacada por los vossk. Pide a Maxwell que se centre en los cruceros y le da las gracias cuando el ataque es rechazado.", false],
	],
	"race/0": [
		[1, "", "Humanos, en guerra con los [[race/1]] en el cuarto milenio. Maxwell es Terran, y la mayoría de los clientes de la campaña sirven en la flota espacial Terran. Los Terran tienen más planetas y estaciones que ningún otro pueblo.", false],
		[1, "", "Muchas de las naves a la venta son diseños Terran: la [[ship/0]], la [[ship/6]] y su versión modificada, la [[ship/7]], y la cañonera [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "El enemigo de los Terran. Las tiendas vossk solo venden su propio caza, la [[ship/8]], y son las únicas que venden las armas vossk. A un piloto que trabaja para los Terran le piden sobornos en las estaciones vossk, y al revés.", false],
	],
	"race/2": [
		[1, "", "Uno de los pueblos de la galaxia, con planetas y estaciones propios.", false],
	],
	"race/3": [
		[1, "", "Uno de los pueblos de la galaxia, con planetas y estaciones propios.", false],
	],
	"race/4": [
		[1, "", "Sus componentes especiales forman parte de armas como el [[equipment/23]], y el pesado bombardero [[ship/3]] es suyo.", false],
	],
	"race/5": [
		[1, "", "Las naves grey son conocidas por su blindaje enormemente pesado. La exploradora [[ship/9]] viene de su flota y se adaptó hace poco para pilotos humanoides, y el misil [[equipment/4]] se fabrica con componentes grey. Feknor, de los Grey, contrata a Maxwell para un convoy peligroso.", false],
	],
	"race/6": [
		[1, "", "Aliados de los Terran. El caza [[ship/1]] es un desarrollo niveliano, y el láser [[equipment/2]] se basa en tecnología de armas niveliana. El ataque vossk contra una de sus estaciones mete a Maxwell de lleno en la guerra.", false],
	],
	"race/7": [
		[1, "", "Uno de los pueblos de la galaxia, con planetas y estaciones propios.", false],
	],
	"race/8": [
		[1, "", "Uno de los pueblos de la galaxia, con planetas y estaciones propios.", false],
	],
	"race/9": [
		[1, "", "Los forajidos no son un pueblo sino una forma de vida: piratas y contrabandistas con planetas y estaciones propios. Sus tiendas son las únicas que venden la [[ship/7]], y [[station/2]] es su guarida más conocida.", false],
	],
	"galaxy": [
		[1, "", "Cuatro cuadrantes, cien sistemas y quinientos planetas y estaciones. Cada cuadrante es más difícil que el anterior: sus trabajos pagan más, sus enemigos son más duros y sus tiendas venden mejor equipo.", false],
		[1, "", "Volar dentro de un cuadrante cuesta créditos según la distancia; pasar al cuadrante vecino o al opuesto cuesta un extra. Cuando has visitado todos los lugares de la galaxia, viajar es gratis.", false],
	],
	"progress/ranks": [
		[1, "Reputación", "La reputación cuenta los enemigos que has destruido. Cada umbral de la tabla de abajo eleva tu rango, que se muestra en la pantalla Estado.", false],
		[1, "Nivel", "Tu nivel crece con el dinero que ganas en misiones y trabajos. Cuando tus ganancias totales superan 1,6 veces lo que eran en tu último nivel, alcanzas el siguiente. Los niveles más altos hacen más duros a los enemigos de tus misiones.", false],
	],
	"progress/milestones": [
		[1, "", "Al atracar, la estación te recibe con un mensaje la primera vez que tus créditos superan un hito o tu exploración de la galaxia alcanza una nueva marca. Los mensajes de abajo son los del propio juego.", false],
		[1, "Riqueza", "La riqueza es más que un número. Con más de 999 999 créditos puedes comerciar en todos los planetas y estaciones: el hangar se abre incluso donde no hay comercio, y allí puedes comprar, vender tu carga y tu botín y reequipar tu nave.", false],
		[1, "Exploración", "Cada lugar visitado cuenta. Visitar los quinientos hace gratis todos los viajes.", false],
	],
	"progress/loyalty": [
		[1, "", "Tu lealtad está en algún punto entre Terran y vossk, como indica el marcador de la pantalla Estado. Cada misión para un cliente Terran la mueve un paso hacia los Terran; cada misión para un cliente vossk, un paso hacia los vossk. No puede pasar de diez pasos en ningún sentido.", false],
		[1, "", "Si viajas a un lugar Terran mientras tu lealtad se inclina hacia los vossk, o a un lugar vossk mientras se inclina hacia los Terran, te piden un soborno además del coste del vuelo: 150 créditos por cada paso. Pagar un soborno devuelve tu lealtad un paso hacia el centro.", false],
	],
	"mode/survival": [
		[1, "", "Supervivencia es un modo aparte, con su propio piloto y su tabla de récords. Elígelo en Iniciar juego. Las naves enemigas no dejan de llegar, cada derribo da puntos y repara tu casco, y el color de los marcadores de un enemigo indica su fuerza. Tu puntuación te da un rango de la tabla de abajo.", false],
	],
	"mode/swarm": [
		[1, "", "Enjambre es un modo creado para este remake, disponible en Iniciar juego. Empieza con un puñado de cazas y crece hasta una multitud que se cierra desde todas partes, con oleadas a partir del quinto minuto.", false],
		[1, "", "Cada derribo llena la barra de nivel. Cada nivel ofrece tres cartas de mejora: un arma nueva, una versión mejor de una que llevas, un cañón extra, más alcance o velocidad de proyectil, un escudo más fuerte, reparación con cada derribo o un casco distinto. Rechazar una carta repara en su lugar una cuarta parte de tu casco.", false],
		[1, "", "Las armas, escudos y cascos son los de tu archivo de juego. Alcanzar un rango en la clasificación de Supervivencia desbloquea el siguiente casco para Enjambre.", false],
	],
	"guide/start": [
		[1, "", "Tras importar el archivo de juego, Iniciar juego ofrece la campaña, la exploración libre, Supervivencia y Enjambre. La campaña empieza en [[station/0]] con una [[ship/0]] y 5000 créditos.", false],
		[1, "El menú de la estación", "En una estación, Info describe el lugar, Hangar abre la tienda y tu nave, Misiones muestra el tablón de trabajos y Mapa te permite viajar. Durante la campaña, el tablón y el mapa siguen bloqueados, y Continuar inicia las siguientes instrucciones. Estado muestra tu nivel, reputación, tiempo de juego, derribos y lealtad, y Menú contiene las opciones y el guardado.", false],
		[1, "", "No todos los lugares tienen un hangar abierto a todos: sin comercio, el hangar solo se abre durante la campaña o cuando tienes más de 999 999 créditos.", false],
	],
	"guide/flight": [
		[1, "", "Los puntos de ruta se marcan en amarillo, los aliados en verde y los enemigos en rojo. Los objetos fuera de tu vista aparecen en el borde de la pantalla. La fuerza restante de un enemigo se muestra bajo su marcador.", false],
		[1, "", "Tu escudo absorbe choques e impactos y se recarga con el tiempo; cuando se agota, el daño va al casco. El impulso da una breve ráfaga de velocidad y necesita tiempo para recargarse.", false],
		[1, "Controles", "Con teclado, dirige con el ratón o las flechas, ajusta el empuje con W y S y desplázate lateralmente con A y D. Dispara con un clic o Espacio, cambia de arma con Q, lanza misiles con F e impúlsate con Mayús. R activa el piloto automático, T acelera el tiempo en tramos seguros, E atraca cerca de una estación y Esc pausa. Un mando apunta con el stick derecho y dispara con el gatillo derecho. Los controles táctiles tienen un stick, un acelerador y botones para disparo, misiles, impulso y navegación; un doble toque en Disparar activa el disparo automático.", false],
		[1, "Piloto automático y tiempo", "El piloto automático vuela hasta el siguiente punto de ruta o la estación. Mientras nada te amenace, el tiempo puede correr más rápido; los enemigos, el daño o la llegada al destino lo devuelven a la normalidad.", false],
	],
	"guide/weapons": [
		[1, "", "Las naves tienen soportes para cinco tipos de arma: láseres, cañones de plasma, cañones de fotones, misiles y cañones térmicos. Cada soporte lleva un arma, y cada nave tiene su propio juego de soportes. Un generador de escudo cabe en cualquier nave.", false],
		[1, "", "Los láseres y cañones de plasma disparan rápido a media distancia. Los cañones de fotones llegan más lejos y golpean más fuerte por disparo, pero recargan despacio. Los cañones térmicos rocían partículas a corta distancia con una cadencia altísima. Los misiles se lanzan con su propio botón, sin cambiar de arma, y causan mucho daño con una recarga larga.", false],
		[1, "", "Los escudos difieren en capacidad y en velocidad de recarga. Las armas más potentes solo se venden a partir del segundo cuadrante, y las armas vossk solo en tiendas vossk.", false],
	],
	"guide/hangar": [
		[1, "", "El hangar tiene tres partes: Nave muestra tu nave con sus armas montadas y su escudo, Carga guarda tus mercancías y equipo de repuesto, y Tienda ofrece las existencias de la estación.", false],
		[1, "", "El equipo comprado va a la bodega; instálalo desde allí si tu nave tiene un soporte libre para él. El equipo y las naves se revenden por la mitad de su precio.", false],
		[1, "", "Comprar una nave entrega la actual como parte del pago. El equipo compatible con la nueva nave sigue montado y el resto pasa a la bodega, mientras haya sitio.", false],
		[1, "", "Las tiendas venden entre una y cuatro armas o escudos y hasta tres naves, elegidas según lo que permitan el cuadrante y el pueblo del lugar. Las existencias se renuevan cuando vuelves tras volar a otro sitio. Durante la campaña, cada capítulo tiene sus propias existencias fijas.", false],
	],
	"guide/trade": [
		[1, "", "Las mercancías salen de los restos de naves destruidas y pasan a tu bodega al terminar la misión. Véndelas en la sección de carga del hangar. Algunas valen más donde la tecnología es baja, otras donde es alta y otras lo mismo en todas partes; cada página de mercancía indica su precio en cada nivel tecnológico.", false],
		[1, "", "Las tiendas no tienen mercancías propias. Lo que vendes en una tienda se queda en sus existencias, y puedes recomprarlo allí al mismo precio.", false],
		[1, "", "El comercio necesita un hangar: los planetas y estaciones sin comercio solo abren el suyo a pilotos con más de 999 999 créditos.", false],
	],
	"guide/travel": [
		[1, "", "El mapa muestra la galaxia, sus cuadrantes y sistemas. Elige un lugar y viaja allí por el coste de vuelo indicado, más un soborno si tu lealtad está en contra de su pueblo. Llegas ya atracado.", false],
		[1, "", "El coste del vuelo crece con la distancia. Cambiar de cuadrante añade 15 000 créditos al billete, y 30 000 para el cuadrante opuesto. El mapa muestra cuánto de la galaxia has explorado; con todos los lugares visitados, viajar no cuesta nada.", false],
		[1, "", "La galaxia se abre cuando la campaña está completa o cuando la saltas.", false],
	],
	"guide/jobs": [
		[1, "", "Fuera de la campaña, el tablón de cada estación ofrece algunos trabajos de clientes de distintos pueblos. Cada uno muestra su dificultad y su recompensa; los trabajos difíciles pagan más, y también los cuadrantes más lejanos.", false],
		[1, "", "De vez en cuando, un estafador turbio ofrece un trabajo que paga un cuarenta por ciento más de lo habitual. Un trabajo terminado paga su recompensa y acerca tu lealtad al pueblo del cliente.", false],
	],
	"guide/campaign": [
		[1, "", "La campaña es una línea de trece misiones. Una misión cumplida paga su recompensa; una fallida se puede repetir. Al completarla, el motor hiperespacial abre la galaxia y el tablón de trabajos y el mapa quedan disponibles.", false],
		[1, "", "Saltar campaña · Explorar, en el menú de inicio o en el de la estación, lleva directamente a la exploración libre. Saltarla no da recompensas de finalización y mantiene a tu piloto de campaña en su propia ranura.", false],
	],
	"guide/saves": [
		[1, "", "El juego guarda automáticamente tras cada misión y en los puntos de control. Campaña, exploración, Supervivencia y Enjambre tienen partidas separadas. Cargar / recuperar en el menú de pausa, o Cargar tras una derrota, vuelve al último guardado automático, al inicio del vuelo o a la última estación.", false],
		[1, "", "Archivos del juego → Transferir partidas lleva tus partidas a otro dispositivo que haya importado el mismo archivo de juego.", false],
	],
	"guide/tips": [
		[1, "", "Vende la carga recogida de los restos antes de comprar equipo; en las naves pequeñas la bodega se llena enseguida.", true],
		[1, "", "Revisa los soportes de una nave antes de comprarle armas: un arma sin soporte adecuado se queda en la bodega.", true],
		[1, "", "Guarda las mercancías hasta atracar donde el nivel tecnológico las favorezca.", true],
		[1, "", "Volar solo para un bando encarece las visitas a las estaciones del otro.", true],
		[1, "", "Visita lugares nuevos cuando viajes de todos modos: explorar toda la galaxia hace gratis todos los viajes.", true],
	],
}
