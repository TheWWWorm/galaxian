extends RefCounted
## The reference's own writing in Turkish. Same blocks, chapter gates and links
## as prose/en.gd; see there for the format. The game has no Turkish text, so
## names and the game's own menu labels stay as the game shows them.

const PAGES := {
	"home": {"title": "Başvuru"},
	"world/setting": {"title": "Savaştaki galaksi"},
	"world/fleet": {"title": "Terran uzay filosu"},
	"world/outlaws": {"title": "Kanun kaçakları ve korsanlar"},
	"chapter/1": {"title": "Yeni bir gemi"},
	"chapter/2": {"title": "Uzay hurdası"},
	"chapter/3": {"title": "Phoebos'a yolculuk"},
	"chapter/4": {"title": "Doc'un kargosu"},
	"chapter/5": {"title": "Silah konvoyu"},
	"chapter/6": {"title": "Kaçak casus"},
	"chapter/7": {"title": "Hassas mallar"},
	"chapter/8": {"title": "Devin içine çıkarma"},
	"chapter/9": {"title": "Opos'a dört gemi"},
	"chapter/10": {"title": "Nivelian cephesi"},
	"chapter/11": {"title": "Bulutsuda pusu"},
	"chapter/12": {"title": "Kanun kaçaklarının istasyonu"},
	"chapter/13": {"title": "İntikam"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Paralı asker pilot"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Uzay filosu teğmeni"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Uzay filosu komutanı"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Aceleci yolcu"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Vossk klan reisi", "early_title": "Vossk pilotu"},
	"character/5": {"title": "John \"Doc\" Washington", "subtitle": "Tüccar"},
	"character/6": {"title": "Filo pilotu", "subtitle": "Uzay filosu"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Güvenlik subayı"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Kaçak casus"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Octopod tüccarı"},
	"character/10": {"title": "Feknor", "subtitle": "Grey halkından"},
	"character/11": {"title": "Amiral Smith", "subtitle": "Terran uzay filosu"},
	"character/12": {"title": "Botom Krant", "subtitle": "Nivelian istasyon komutanı"},
	"progress/ranks": {"title": "İtibar ve seviye"},
	"progress/milestones": {"title": "Dönüm noktaları"},
	"progress/loyalty": {"title": "Sadakat ve rüşvet"},
	"mode/survival": {"title": "Hayatta kalma", "subtitle": "Oyun modu"},
	"mode/swarm": {"title": "Sürü", "subtitle": "Yeniden yapımın oyun modu"},
	"guide/start": {"title": "Başlarken"},
	"guide/flight": {"title": "Uçuş ve çatışma"},
	"guide/weapons": {"title": "Silahlar ve kalkanlar"},
	"guide/hangar": {"title": "Hangar"},
	"guide/trade": {"title": "Ticaret ve ganimet"},
	"guide/travel": {"title": "Yolculuk ve harita"},
	"guide/jobs": {"title": "İş panosu"},
	"guide/campaign": {"title": "Sefer ve serbest keşif"},
	"guide/saves": {"title": "Kaydetme ve yükleme"},
	"guide/tips": {"title": "İpuçları"},
}

const BLOCKS := {
	"home": [
		[1, "", "Bu başvuru, kendi Galaxy on Fire kopyanızı anlatır: galaksideki her gezegen ve istasyonu, dükkânlardaki gemileri, silahları ve malları, panolardaki işleri, hikâyedeki kişileri ve ticaret, yolculuk ve itibarın kurallarını. Adlar, açıklamalar ve diyaloglar içe aktardığınız oyun dosyasından gelir; rakamlar bu yeniden yapımın oynadığı kurallara uyar.", false],
		[1, "", "Hikâye sayfaları seferinizle birlikte büyür. Henüz ulaşmadığınız bölümler ve henüz tanışmadığınız kişiler başvuruda yer almaz; bir bölümün sonu da onu uçtuktan sonra görünür.", false],
	],
	"intro/world": [
		[1, "", "Oyunun dünyası: Terranlar ile Vosskların savaşı, Keith Maxwell'in az önce ayrıldığı uzay filosu ve iki tarafı da yağmalayan kanun kaçakları.", false],
	],
	"intro/story": [
		[1, "", "Sefer, on üç bölümden oluşan tek bir çizgidir. Her bölüm bir istasyondaki brifingle başlar ve telsiz konuşmalarıyla dolu bir uçuşla sürer. Aşağıdaki bölümler pilotunuzun ulaştığı yere kadar gider.", false],
	],
	"intro/characters": [
		[1, "", "Brifinglerde ve telsizde Keith Maxwell ile konuşan kişiler. Her portre oyunun kendi çizimlerinden gelir.", false],
	],
	"intro/races": [
		[1, "", "Galaksinin gezegenlerinde ve istasyonlarında on halk yaşar. Bir yerin sakinleri, dükkânının hangi gemileri satabileceğine ve Terranlar ile Vossklarda sadakatinizin oraya giderken size rüşvete mal olup olmayacağına karar verir.", false],
	],
	"intro/galaxy": [
		[1, "", "Galaksi, her biri yirmi beş sistemden oluşan dört çeyreğe bölünmüştür ve her sistemde beş gezegen ya da istasyon vardır. Aşağıdaki harita hepsini gösterir; aralarındaki yolculuklar sefer bitince ya da seferi atlarsanız hemen açılır.", false],
	],
	"intro/stations": [
		[1, "", "Beş yüz gezegen ve istasyonun tamamı. Bir yerin teknoloji seviyesi kargo fiyatlarını ve gemi indirimlerini belirler; herkese açık hangarı yalnızca ticaret yapılan yerler vardır.", false],
	],
	"intro/ships": [
		[1, "", "Satın alabileceğiniz gemiler. Onları gövde, kargo ambarı ve silah yuvaları ayırır; çoğu halkın dükkânı, yalnızca Vosskların sattığı Vossk avcısı dışında hepsini satar.", false],
	],
	"intro/equipment": [
		[1, "", "Silahlar ve kalkan jeneratörleri. Bir gemi bir silahı ancak o silah türü için yuvası varsa taşıyabilir ve her türden aynı anda yalnızca bir silah taşır.", false],
	],
	"intro/goods": [
		[1, "", "Yok edilen gemilerin enkazında bulunan kargo. Her mal, bir istasyonun teknoloji seviyesinin fiyatını nasıl değiştirdiğine dair kendi kuralına uyar.", false],
	],
	"intro/jobs": [
		[1, "", "Galaksi açıldığında iş panosunda sunulan iş türleri. Ödül, işe ve bulunduğunuz çeyreğe bağlıdır.", false],
	],
	"intro/progress": [
		[1, "", "Oyun pilotunuzu nasıl ölçer: vuruşlardan itibar, kazançtan seviye, Terranlar ile Vossklar arasında sadakat ve servetinizi ile keşiflerinizi kutlayan mesajlar.", false],
	],
	"intro/modes": [
		[1, "", "Sefer ve serbest keşif dışındaki oynama biçimleri.", false],
	],
	"intro/guide": [
		[1, "", "Nasıl oynanır: uçmak, savaşmak, donanmak, ticaret yapmak, yolculuk etmek ve yükselmek.", false],
	],
	"world/setting": [
		[1, "", "Dördüncü binyılda Terranlar, [[race/1]] halkına karşı gezegenler arası bir savaş yürütür. Galaksiyi onlarla başka halklar da paylaşır: bazıları bir tarafla müttefik, bazıları iki tarafla da ticaret yapar, bazıları ise neredeyse hiç tanınmaz.", false],
		[1, "", "Oyun 3587 yılında bir Terran istasyonu olan [[station/0]] üzerinde başlar; SS Ulysses savaş kruvazörü [[character/0]] adlı pilotu buraya bırakır. Uzay filosundan onurla terhis edildikten sonra [[character/11|Amiral Smith]] ona kendi gemisini vermiştir ve o da geçimini paralı asker olarak sağlamaya niyetlidir.", false],
		[1, "Nerede geçer", "Seferin tamamı ilk çeyrek olan [[quadrant/0]] içinde, [[station/0]] yakınlarında geçer. Galaksinin geri kalanı hikâye bitince açılır.", false],
		[14, "Savaştan sonra", "Kanun kaçaklarının elebaşı öldü, gemide bir hiperuzay sürücüsü var ve Maxwell filodaki yeri geri çevirir. Galaksi artık onundur: keşfetmek, ticaret yapmak ve kim öderse onun için savaşmak üzere.", false],
	],
	"world/fleet": [
		[1, "", "Terran uzay filosu, Terran dünyalarının ordusudur. Maxwell oyun başlamadan önce orada hizmet etmiştir ve seferdeki işlerinin çoğu filonun subaylarından ya da çevrelerindeki kişilerden gelir.", false],
		[1, "", "Standart avcısı [[ship/6]]'dir. Hikâyedeki subayları arasında Maxwell'e yeni gemisini gösteren [[character/1]] ve gemiyi ona veren [[character/11|Amiral Smith]] vardır.", false],
		[5, "", "Filonun ajanları da vardır. Teğmen Hammond, amiralin emriyle [[station/2]] üzerinde gizli görevdedir.", false],
		[6, "", "Güvenlik subayı [[character/7]], filonun içindeki hainlerin peşindedir.", false],
		[12, "", "Komutanlarının hepsi sadık değildir: biri, filonun arkasından Vossklar ve kanun kaçaklarıyla iş çevirmektedir.", false],
	],
	"world/outlaws": [
		[9, "", "Kanun kaçakları değiştirilmiş Terran gemileri uçurur ve konvoylara saldırır. Vossk topraklarının derinliklerinde bir Grey konvoyunu pusuya düşürdüklerinde, Vossklarla birlikte çalıştıkları anlaşılır.", false],
		[12, "", "Kanun kaçaklarının uzay filosunun içinde bir lideri vardır; çalınan askeri sırları Vossklara satmış ve nakliye gemilerine yapılan saldırıları örtbas etmiştir. Bir mayın tarlasının ardındaki kendi istasyonlarında direnirler.", false],
		[1, "", "Kanun kaçaklarının galaksi haritasında kendi halkı da vardır: sakinleri [[race/9]] olarak listelenen yerler onların istasyonları ve gezegenleridir. [[ship/7]] gemisini yalnızca onların dükkânları satar.", false],
	],
	"chapter/1": [
		[1, "", "Maxwell [[station/0]] istasyonuna varır ve onu, Amiral Smith'ten ona yeni gemisini, eski bir [[ship/0]] keşif gemisini gösterme emri almış olan Teğmen [[character/1]] karşılar. Hangarı anlatır: gemiler, silahlar ve donanım dükkândan alınır, uzayda toplanan kargo ise ambardan satılır.", false],
		[1, "", "Ardından bir deneme uçuşu gelir. Christine onu yol noktalarından geçirir, kalkanları, silah değiştirmeyi, ateş etmeyi ve hız artırmayı anlatır ve son olarak vurulması için birkaç eğitim dronu salar.", false],
		[2, "Sonuç", "Maxwell dronları yok eder ve istasyona döner. Christine ona bol şans diler ve onu tekrar tek parça görmeyi umar.", false],
	],
	"chapter/2": [
		[2, "", "Filodan istenmeyen bir yüz: Maxwell'in hiç çekemediği komutan [[character/2]], ona bir iş verir. Bir sonraki konvoy gelmeden istasyonun yakınındaki bir uzay koridoru enkazdan temizlenmelidir ve bunun için yalnızca iki dakika vardır.", false],
		[3, "Sonuç", "Koridor zamanında temizlenir ve Vlad, Maxwell'in bu iş için yaratıldığını söyleyerek parasını öder.", false],
	],
	"chapter/3": [
		[3, "", "Gergin, ufak tefek bir müşteri, [[character/3]], bir anlaşması suya düşmeden hemen [[station/1]] istasyonuna götürülmek ister. Orası Vossk kaynıyor ama iyi para veriyor ve Maxwell kabul ediyor.", false],
		[4, "Sonuç", "Yolda bir Vossk devriyesi teslim olmalarını ister. Maxwell Bolar'ı ulaştırır ve yolcu, titremesi geçer geçmez onu tavsiye edeceğine söz verir.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]], gemisi için korsanların sığınağı olan [[station/2]] istasyonuna kadar eskort ister. Maxwell risk yüzünden ücreti yükseltir ve kargonun kanun kaçakları için yine bir silah teslimatı olduğundan şüphelenir.", false],
		[5, "Sonuç", "Vossk avcıları yük gemisine iki kez saldırır. Gemi Tortuga'ya ulaşır ve Doc, taşınan şeyin Maxwell'i ilgilendirmediğini açıkça belirtir.", false],
	],
	"chapter/5": [
		[5, "", "Maxwell Tortuga'da, orada gizli görevde olan [[character/1]] ile karşılaşır. Filoya [[station/3]] yakınlarında bir Vossk silah konvoyunu durdurma emri verilmiştir; teslimat geçerse bir katliam yaşanacaktır. Onun filosuna deneyimli bir pilot daha gerekir.", false],
		[6, "Sonuç", "Önce eskort düşer, sonra yük gemileri. Konvoy durdurulur ve Christine, Amiral Smith'in memnun kalacağını düşünür.", false],
	],
	"chapter/6": [
		[6, "", "Güvenlik subayı [[character/7]] ters gitmemesi gereken bir iş verir: bir casus olan [[character/8]], filonun gizli gemilerinden biriyle kaçmıştır. Gemi düşman eline geçmemeli, gerekirse yok edilmelidir.", false],
		[7, "Sonuç", "Maxwell, Lockwood'u bir asteroit alanında bulur ve teslim olana kadar gemisine hasar verir. Kimse onu tutuklayamadan [[character/2|Vlad Borsikov]] onu vurur ve Maxwell'e emrin gemiyi yok etmek olduğunu hatırlatır. Maxwell, meselenin hiçbir zaman yalnızca bir gemi olmadığından şüphelenmeye başlar.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]], gemileri için [[station/4]] istasyonuna kadar eskort ister. Maxwell, çalıntı mallarla dolup taşmasıyla bilinen Octopod çetesini tanır ama yetkililer işin dışında kaldığı sürece işi kabul eder.", false],
		[8, "Sonuç", "Kolay para gibi başlayan iş, Vossk avcıları ve bir kruvazörle çatışmaya dönüşür. En az bir gemi geçer ve Maxwell, Vosskların giderek daha saldırgan hâle geldiğini fark eder.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]], hareketsiz kalmış bir Vossk savaş kruvazörü bulmuştur. Filo onu ele geçirmek ve komutanını canlı yakalamak ister, ama önce gövdesindeki her sabit top yok edilmelidir.", false],
		[9, "Sonuç", "Christine'in filosu ateşi üzerine çekerken Maxwell topları susturur ve gemiye çıkarma yapılır.", false],
	],
	"chapter/9": [
		[9, "", "Grey halkından [[character/10]], dört gemilik bir konvoyu doğrudan Vossk topraklarından geçirerek [[station/5]] istasyonuna götürmesi için Maxwell'i tutar ve ulaşan her gemi için ödeme yapar.", false],
		[10, "Sonuç", "Saldırganlar Vossk değil, değiştirilmiş Terran gemileridir. Maxwell onları püskürtür ve kanun kaçaklarının Vossklarla birlikte çalıştığı sonucuna varır.", false],
	],
	"chapter/10": [
		[10, "", "[[character/11]] tüm boştaki pilotlara ihtiyaç duyar: Terranların müttefiki Nivelianlara ait bir istasyon güçlü Vossk kuvvetlerinin saldırısı altındadır. Maxwell'in ücretleri ve sadakati üzerine sert bir tartışmanın ardından amiral onu gönderir.", false],
		[11, "Sonuç", "İstasyon komutanı [[character/12]], [[character/1|Christine]] avcılarla uğraşırken Maxwell'den kruvazörlere yoğunlaşmasını ister. Saldırı püskürtülür ve ikisi de geriye kalan tehlikenin kanun kaçakları olduğu konusunda hemfikirdir.", false],
	],
	"chapter/11": [
		[11, "", "Bir Vossk klan reisi, [[character/4]], Maxwell ile gizlice temasa geçer. Vossk komutanlarından biri bir Terran subayı ve kanun kaçaklarıyla komplo kurmaktadır ve klan onun ölümünü ister. Pusu için en iyi yer Yarapu Bulutsusu'dur.", false],
		[12, "Sonuç", "Maxwell komutanın kruvazörünü ve eskortunu yok eder. Nartok ona, Terran tarafındaki hainin Maxwell'in eski bir tanıdığı olduğunu ve Teğmen Hammond'ın şimdiden onun izini sürdüğünü söyler.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] haberi getirir: [[character/2]], kanun kaçaklarının elebaşıdır. Komutan olarak nakliye gemilerine yapılan saldırıları örtbas etmiş ve Vossklara satmak üzere askeri sırları Lockwood'a çaldırmıştır. Çetesi, bir mayın tarlasıyla korunan bir kanun kaçağı istasyonuna barikat kurmuştur; Maxwell saldırıdan önce mayınları temizlemelidir.", false],
		[13, "Sonuç", "Mayın tarlası temizlenir ve istasyonun savunucuları düşer. Christine Vlad'ın üzerine atılır; Vlad, Maxwell onu koruyamadan onu vurur ve kaçar.", false],
	],
	"chapter/13": [
		[13, "", "[[character/11]] başsağlığı diler; Maxwell yalnızca Vlad'ın nereye gittiğini bilmek ister. Filo Vlad'ı ve son kanun kaçaklarını bulmuştur ve filoların onları dağıtmak için Maxwell'in yardımına ihtiyacı vardır.", false],
		[14, "Sonuç", "Kanun kaçakları dağıtılınca Maxwell filoyu işiyle baş başa bırakır, Vlad'ın peşine tek başına düşer ve onu öldürür. Amiral ona filoda bir yer teklif eder; Maxwell reddeder. Galaksinin her çeyreğini açan bir hiperuzay sürücüsü alır.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell oyuncunun pilotudur: onurla terhis edildikten sonra [[character/11|Amiral Smith]]'ten bir gemi alan ve [[station/0]] üzerinde paralı asker olarak yeni bir hayata başlayan eski bir Terran uzay filosu pilotu.", false],
		[1, "", "Alaycıdır ve ücreti konusunda pazarlığa hemen girişir, ama üstlendiği işleri bitirir.", false],
		[7, "", "[[character/2|Vlad Borsikov]] teslim olmuş bir adamı vurduğunda itiraz eder.", false],
		[13, "", "[[character/1|Christine Hammond]]'ın ölümü son bölümü kişisel bir meseleye dönüştürür.", false],
		[14, "", "Vlad'ı öldürdükten sonra filoya dönmeyi reddeder ve galakside kendi yolunu seçmeyi tercih eder.", false],
	],
	"character/1": [
		[1, "", "Terran uzay filosundan Teğmen Christine Hammond, Maxwell'i [[station/0]] üzerinde karşılar, gemisini gösterir ve ilk deneme uçuşunu onunla birlikte uçar. Ondan kendisine Christine demesini ister.", false],
		[5, "", "Aynı zamanda ajan olarak çalışır: [[station/2]] üzerinde Amiral Smith'in emriyle gizli görevdedir ve Maxwell'i Vossk silah konvoyuna yapılan saldırıya dâhil eder.", false],
		[8, "", "Hareketsiz kalmış bir Vossk savaş kruvazörünü ele geçiren filoya komuta eder.", false],
		[12, "", "Kanun kaçaklarının arkasında [[character/2|Vlad Borsikov]]'un olduğunu ortaya çıkarır ve onların istasyonuna saldırıyı planlar.", false],
		[13, "", "Savaştan sonra Vlad'ın üzerine atılır ve onun tarafından vurulur. Ölümü, son bölümde Maxwell'i Vlad'ın peşine düşürür.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov, Terran uzay filosunda bir komutandır ve Maxwell'in sözleriyle filodaki en berbat adamdır. Maxwell'e ilk ücretli işini verir: bir uzay koridorunu zamana karşı enkazdan temizlemek.", false],
		[7, "", "Casus Corsair Lockwood teslim olduktan sonra onu vurur ve emrin gemiyi yok etmek olduğunda ısrar eder.", false],
		[12, "", "Hain odur: rütbesini nakliye gemilerine yapılan saldırıları örtbas etmek için kullanan ve Vossklara sattığı askeri sırları Lockwood'a çaldıran kanun kaçakları elebaşı.", false],
		[13, "", "Christine Hammond, istasyonuna yapılan saldırının ardından peşine düştüğünde onu vurur ve kaçar.", false],
		[14, "", "Filo onu son kanun kaçaklarıyla birlikte bulur ve Maxwell onu bir düelloda öldürür.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon, bir anlaşmayı kurtarmak için hemen [[station/1]] istasyonuna ulaşması gereken telaşlı bir müşteridir ve onu Vossk uzayından geçirmeye razı bir pilota iyi para öder.", false],
		[4, "", "Vossk pususundan sağ çıkar ve Maxwell'i tavsiye edeceğine söz verir.", false],
	],
	"character/4": [
		[4, "", "Bu yüze sahip bir Vossk, Phoebos yolunda Maxwell'e seslenir ve Vossk İmparatorluğu adına teslim olmasını ister.", false],
		[11, "", "Nartok Brek, [[race/1]] halkının bir klan reisidir. Kendi komutanlarından biri bir Terran subayı ve kanun kaçaklarıyla komplo kurduğu için Maxwell ile gizlice temasa geçer ve hainin Yarapu Bulutsusu'nda pusuya düşürülmesini ister. Bir şey söylemeden önce Maxwell'den şeref sözü ister.", false],
		[12, "", "Pusudan sonra Maxwell'e, Terran hainin Maxwell'in eski bir tanıdığı olduğunu söyler.", false],
	],
	"character/5": [
		[4, "", "Arkadaşlarının Doc dediği John Washington, gemisi için [[station/2]] istasyonuna kadar eskort ister. 3.000 kredi önerir ve tanık olmaması şartıyla 4.500'e razı olur. Maxwell, kanun kaçakları için bir silah teslimatından şüphelenir.", false],
		[5, "", "Kargosu ulaşır. Ne olduğunu kendine saklar.", false],
	],
	"character/6": [
		[6, "", "Christine Hammond'ın filosundan, bu Maxwell'in hiç savaş görüp görmediğini telsizden soran ve onun duyduğunu fark etmeyen bir pilot.", false],
		[13, "", "Christine ve Maxwell Vlad'ın peşine düşerken aynı filo kanun kaçaklarının istasyonunu güvence altına almak için geride kalır.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom, uzay filosunun güvenlik subayıdır. Çalınan geminin düşman eline geçmemesi emriyle Maxwell'i casus [[character/8]] peşine gönderir.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood, uzay filosunun gizli gemilerinden biriyle kaçan bir casustur.", false],
		[7, "", "Bir asteroit alanında köşeye sıkışınca teslim olur, ama Vlad Borsikov yine de onu vurur.", false],
		[12, "", "Daha sonra, askeri sırları çalması için onu en başta Vlad'ın görevlendirdiği ortaya çıkar.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt, çalıntı mal taşımasıyla bilinen Octopod çetesi için yük taşır. Gemideki her şeyin tamamen yasal olduğunda ısrar eder ve gemilerini [[station/4]] istasyonuna götürmesi için Maxwell'e ödeme yapar.", false],
	],
	"character/10": [
		[9, "", "Grey halkından Feknor, Maxwell'in adını duymuştur ve ona zor bir iş teklif eder: Vossk topraklarından geçerek [[station/5]] istasyonuna dört gemi, ulaşan her gemi için 4.000 kredi.", false],
	],
	"character/11": [
		[1, "", "Terran uzay filosundan Amiral Smith, terhisinden sonra Maxwell'e gemisini vermiş ve kullanmayı göstermesi için Teğmen Hammond'ı görevlendirmiştir.", false],
		[10, "", "Nivelian istasyonu saldırıya uğradığında Maxwell'i çağırır. Maxwell ücretlerinden ve Vosskların ne ödeyebileceğinden söz edince konuşma sertleşir.", false],
		[13, "", "Christine'in ölümünden sonra Maxwell'e başsağlığı diler ve Vlad'ın kanun kaçaklarının yerini söyler.", false],
		[14, "", "Maxwell'in Vlad'ın peşine tek başına gitmesine izin verir, ona filoda bir yer teklif eder ve reddedince ona bir hiperuzay sürücüsü verir.", false],
	],
	"character/12": [
		[11, "", "Botom Krant, Vossk saldırısına uğrayan Nivelian istasyonunun komutanıdır. Maxwell'den kruvazörlere yoğunlaşmasını ister ve saldırı püskürtülünce ona teşekkür eder.", false],
	],
	"race/0": [
		[1, "", "Dördüncü binyılda [[race/1]] halkıyla savaşan insanlar. Maxwell bir Terran'dır ve seferdeki müşterilerin çoğu Terran uzay filosunda görev yapar. Terranlar, diğer tüm halklardan daha fazla gezegen ve istasyona sahiptir.", false],
		[1, "", "Satıştaki gemilerin çoğu Terran tasarımıdır: [[ship/0]], [[ship/6]] ve onun değiştirilmiş hâli [[ship/7]] ile [[ship/4]] top gemisi.", false],
	],
	"race/1": [
		[1, "", "Terranların düşmanı. Vossk dükkânları yalnızca kendi avcıları [[ship/8]]'i satar ve Vossk silahlarını yalnızca onlar satar. Terranlar için çalışan bir pilottan Vossk istasyonlarında rüşvet istenir, tersi de geçerlidir.", false],
	],
	"race/2": [
		[1, "", "Kendi gezegenleri ve istasyonları olan, galaksinin halklarından biri.", false],
	],
	"race/3": [
		[1, "", "Kendi gezegenleri ve istasyonları olan, galaksinin halklarından biri.", false],
	],
	"race/4": [
		[1, "", "Özel parçaları [[equipment/23]] gibi silahlarda kullanılır ve ağır bombardıman gemisi [[ship/3]] onlarındır.", false],
	],
	"race/5": [
		[1, "", "Grey gemileri son derece ağır zırhlarıyla bilinir. [[ship/9]] keşif gemisi onların filosundan gelir ve insansı pilotlar için daha yeni uyarlanmıştır; [[equipment/4]] füzesi de Grey parçalarıyla yapılır. Grey halkından Feknor, tehlikeli bir konvoy için Maxwell'i tutar.", false],
	],
	"race/6": [
		[1, "", "Terranların müttefikleri. [[ship/1]] avcısı bir Nivelian geliştirmesidir ve [[equipment/2]] lazeri Nivelian silah teknolojisine dayanır. Vosskların istasyonlarından birine saldırması Maxwell'i savaşın tam içine çeker.", false],
	],
	"race/7": [
		[1, "", "Kendi gezegenleri ve istasyonları olan, galaksinin halklarından biri.", false],
	],
	"race/8": [
		[1, "", "Kendi gezegenleri ve istasyonları olan, galaksinin halklarından biri.", false],
	],
	"race/9": [
		[1, "", "Kanun kaçakları bir halk değil, bir yaşam biçimidir: kendi gezegenleri ve istasyonları olan korsanlar ve kaçakçılar. [[ship/7]] gemisini yalnızca onların dükkânları satar ve [[station/2]] en bilinen sığınaklarıdır.", false],
	],
	"galaxy": [
		[1, "", "Dört çeyrek, yüz sistem ve beş yüz gezegen ve istasyon. Her çeyrek bir öncekinden zordur: işleri daha çok öder, düşmanları daha dayanıklıdır ve dükkânları daha iyi donanım satar.", false],
		[1, "", "Bir çeyrek içinde uçmak mesafeye göre kredi tutar; komşu ya da karşı çeyreğe geçmek ek ücretlidir. Galaksideki her yeri ziyaret ettiğinizde yolculuk ücretsiz olur.", false],
	],
	"progress/ranks": [
		[1, "İtibar", "İtibar, yok ettiğiniz düşmanları sayar. Aşağıdaki tablodaki her eşik, \"Status\" ekranında gösterilen rütbenizi yükseltir.", false],
		[1, "Seviye", "Seviyeniz görevlerden ve işlerden kazandığınız parayla artar. Toplam kazancınız son seviyenizdeki miktarın 1,6 katını aştığında bir sonraki seviyeye ulaşırsınız. Yüksek seviyeler görevlerinizdeki düşmanları daha dayanıklı yapar.", false],
	],
	"progress/milestones": [
		[1, "", "Kenetlendiğinizde, kredileriniz ilk kez bir dönüm noktasını geçtiğinde ya da galaksi keşfiniz yeni bir eşiğe ulaştığında istasyon sizi bir mesajla karşılar. Aşağıdaki mesajlar oyunun kendisine aittir.", false],
		[1, "Servet", "Servet bir sayıdan fazlasıdır. 999.999 krediden fazlasıyla her gezegen ve istasyonda ticaret yapabilirsiniz: hangar ticaret olmayan yerlerde bile açılır ve orada satın alabilir, kargonuzu ve ganimetinizi satabilir, geminizi yeniden donatabilirsiniz.", false],
		[1, "Keşif", "Ziyaret ettiğiniz her yer sayılır. Beş yüzünü de ziyaret etmek her yolculuğu ücretsiz yapar.", false],
	],
	"progress/loyalty": [
		[1, "", "Sadakatiniz Terranlar ile Vossklar arasında bir yerdedir ve \"Status\" ekranındaki gösterge bunu gösterir. Bir Terran müşteri için uçtuğunuz her görev onu Terranlara doğru bir adım, bir Vossk müşteri için her görev Vossklara doğru bir adım kaydırır. Hiçbir yöne on adımdan fazla gidemez.", false],
		[1, "", "Sadakatiniz Vossklara eğilimliyken bir Terran yerine ya da Terranlara eğilimliyken bir Vossk yerine giderseniz, uçuş ücretine ek olarak rüşvet istenir: her adım için 150 kredi. Rüşvet ödemek sadakatinizi bir adım ortaya doğru geri çeker.", false],
	],
	"mode/survival": [
		[1, "", "Hayatta kalma, kendi pilotu ve yüksek skor tablosu olan ayrı bir moddur. \"Start Game\" altından seçin. Düşman gemileri durmadan gelir, her vuruş puan kazandırır ve gövdenizi onarır; bir düşmanın işaret çerçevesinin rengi ne kadar güçlü olduğunu gösterir. Skorunuz size aşağıdaki tablodan bir rütbe kazandırır.", false],
	],
	"mode/swarm": [
		[1, "", "Sürü, bu yeniden yapım için yazılmış bir moddur ve \"Start Game\" altında bulunur. Bir avuç avcıyla başlar ve her yandan kapanan bir kalabalığa dönüşür; beşinci dakikadan sonra dalgalar gelir.", false],
		[1, "", "Her vuruş seviye çubuğunu doldurur. Her seviye üç geliştirme kartı sunar: yeni bir silah, taşıdığınız bir silahın daha iyisi, ek bir namlu, daha fazla menzil ya da mermi hızı, daha güçlü bir kalkan, her vuruşta onarım ya da farklı bir gövde. Bir kartı reddetmek bunun yerine gövdenizin dörtte birini onarır.", false],
		[1, "", "Silahlar, kalkanlar ve gövdeler oyun dosyanızdakilerdir. Hayatta kalma skor sıralamasında bir rütbeye ulaşmak, Sürü için bir sonraki gövdenin kilidini açar.", false],
	],
	"guide/start": [
		[1, "", "Oyun dosyası içe aktarıldıktan sonra \"Start Game\"; seferi, serbest keşfi, Hayatta kalma'yı ve Sürü'yü sunar. Sefer [[station/0]] üzerinde bir [[ship/0]] ve 5.000 krediyle başlar.", false],
		[1, "İstasyon menüsü", "Bir istasyonda \"Info\" yeri anlatır, \"Hangar\" dükkânı ve geminizi açar, \"Missions\" iş panosunu gösterir ve \"Map\" yolculuk etmenizi sağlar. Sefer sırasında iş panosu ve harita kilitli kalır ve \"Go on\" bir sonraki brifingi başlatır. \"Status\" seviyenizi, itibarınızı, oyun sürenizi, vuruşlarınızı ve sadakatinizi gösterir; \"Menu\" ise seçenekleri ve kaydetmeyi içerir.", false],
		[1, "", "Her yerin herkese açık bir hangarı yoktur: ticaret yoksa hangar yalnızca sefer sırasında ya da 999.999 krediden fazlanız olduğunda açılır.", false],
	],
	"guide/flight": [
		[1, "", "Yol noktaları sarı, müttefikler yeşil, düşmanlar kırmızı işaretlenir. Görüş alanınızın dışındaki nesneler ekranın kenarında gösterilir. Bir düşmanın kalan gücü işaretinin altında yazar.", false],
		[1, "", "Kalkanınız çarpışmaları ve isabetleri emer ve zamanla dolar; tükendiğinde hasar gövdeye gider. Hız artırma kısa bir sürat patlaması verir ve yeniden dolması zaman alır.", false],
		[1, "Kontroller", "Klavyede fare ya da ok tuşlarıyla yönlendirin, itkiyi W ve S ile ayarlayın, A ve D ile yana kayın. Tıklama ya da Boşluk ile ateş edin, Q ile silah değiştirin, F ile füze atın, Shift ile hız artırın. R otomatik pilotu açar, T güvenli kısımlarda zamanı hızlandırır, E bir istasyonun yakınında kenetler ve Esc duraklatır. Bir oyun kumandası sağ çubukla nişan alır ve sağ tetikle ateş eder. Dokunmatik kontrollerde bir çubuk, bir gaz kolu ve ateş, füze, hız artırma ve navigasyon düğmeleri vardır; Ateş'e çift dokunmak otomatik ateşi açar.", false],
		[1, "Otomatik pilot ve zaman", "Otomatik pilot bir sonraki yol noktasına ya da istasyona uçar. Sizi tehdit eden bir şey yokken zaman daha hızlı akabilir; düşmanlar, hasar ya da hedefe varış onu normale döndürür.", false],
	],
	"guide/weapons": [
		[1, "", "Gemilerde beş silah türü için yuva vardır: lazerler, plazma topları, foton topları, füzeler ve termo toplar. Her yuva bir silah taşır ve her geminin kendi yuva düzeni vardır. Kalkan jeneratörü her gemiye uyar.", false],
		[1, "", "Lazerler ve plazma topları orta mesafede hızlı ateş eder. Foton topları en uzağa ulaşır ve atış başına en sert vurur ama yavaş dolar. Termo toplar yakın mesafede çok yüksek atış hızıyla parçacık püskürtür. Füzeler silah değiştirmeden kendi düğmeleriyle atılır ve uzun bir dolum süresiyle ağır hasar verir.", false],
		[1, "", "Kalkanlar kapasite ve dolum hızı bakımından farklıdır. En güçlü silahlar yalnızca ikinci çeyrekten itibaren, Vossk silahları ise yalnızca Vossk dükkânlarında satılır.", false],
	],
	"guide/hangar": [
		[1, "", "Hangarın üç bölümü vardır: \"Ship\" geminizi takılı silahları ve kalkanıyla gösterir, \"Cargo\" mallarınızı ve yedek donanımınızı tutar, \"Shop\" ise istasyonun stokunu sunar.", false],
		[1, "", "Satın alınan donanım kargo ambarına gider; geminizde onun için boş bir yuva varsa oradan takın. Donanım ve gemiler fiyatlarının yarısına geri satılır.", false],
		[1, "", "Gemi satın almak, mevcut geminizi takasa verir. Yeni gemiye uyan donanım takılı kalır, geri kalanı yer olduğu sürece ambara geçer.", false],
		[1, "", "Dükkânlar, yerin çeyreğinin ve halkının izin verdiklerinden seçilen bir ila dört silah ya da kalkan ve en fazla üç gemi satar. Bir dükkânın stoku, başka bir yere uçup geri döndüğünüzde yenilenir. Sefer sırasında her bölümün kendi sabit stoku vardır.", false],
	],
	"guide/trade": [
		[1, "", "Mallar yok edilen gemilerin enkazından gelir ve görevden sonra ambarınıza toplanır. Onları hangarın kargo bölümünde satın. Bazıları teknolojinin düşük, bazıları yüksek olduğu yerlerde en çok getirir, bazıları ise her yerde aynı fiyattır; her mal sayfası her teknoloji seviyesindeki fiyatını listeler.", false],
		[1, "", "Dükkânların kendi malları yoktur. Bir dükkâna sattığınız şey onun stokunda kalır ve orada aynı fiyata geri alabilirsiniz.", false],
		[1, "", "Ticaret için hangar gerekir: ticaret olmayan gezegen ve istasyonlar hangarlarını yalnızca 999.999 krediden fazlası olan pilotlara açar.", false],
	],
	"guide/travel": [
		[1, "", "Harita galaksiyi, çeyreklerini ve sistemlerini gösterir. Bir yer seçin ve gösterilen uçuş ücretine, sadakatiniz halkına karşıysa rüşveti de ekleyerek oraya gidin. Kenetlenmiş olarak varırsınız.", false],
		[1, "", "Uçuş ücreti mesafeyle artar. Çeyrek değiştirmek ücrete 15.000 kredi, karşı çeyrek ise 30.000 kredi ekler. Harita galaksinin ne kadarını keşfettiğinizi gösterir; her yeri ziyaret ettiğinizde yolculuk hiçbir şey tutmaz.", false],
		[1, "", "Galaksi, sefer tamamlandığında ya da onu atladığınızda açılır.", false],
	],
	"guide/jobs": [
		[1, "", "Sefer dışında her istasyonun iş panosu, farklı halklardan müşterilerin birkaç işini sunar. Her biri zorluğunu ve ödülünü gösterir; zor işler daha çok öder, daha uzak çeyrekler de öyle.", false],
		[1, "", "Arada bir şaibeli bir dolandırıcı, her zamankinden yüzde kırk fazla ödeyen bir iş teklif eder. Bitirilen bir iş ödülünü öder ve sadakatinizi müşterinin halkına doğru kaydırır.", false],
	],
	"guide/campaign": [
		[1, "", "Sefer, on üç görevden oluşan tek bir çizgidir. Başarılan bir görev ödülünü öder; başarısız olan yeniden denenebilir. Sefer tamamlandığında hiperuzay sürücüsü galaksiyi açar, iş panosu ve harita kullanılabilir olur.", false],
		[1, "", "Başlangıç menüsündeki ya da istasyon menüsündeki \"Kampanyayı atla · Keşfet\" doğrudan serbest keşfe geçer. Atlamak tamamlama ödülü vermez ve sefer pilotunuzu kendi yuvasında tutar.", false],
	],
	"guide/saves": [
		[1, "", "Oyun her görevden sonra ve kontrol noktalarında otomatik kaydeder. Sefer, keşif, Hayatta kalma ve Sürü ayrı kayıtlar tutar. Duraklatma menüsündeki \"Yükle / kurtar\" ya da yenilgiden sonra \"Load\", son otomatik kayda, uçuşun başına ya da son istasyona döner.", false],
		[1, "", "\"Oyun dosyaları\" → \"Kayıtları aktar\", kayıtlarınızı aynı oyun dosyasını içe aktarmış başka bir cihaza taşır.", false],
	],
	"guide/tips": [
		[1, "", "Donanım almadan önce enkazdan topladığınız kargoyu satın; küçük gemilerde ambar çabuk dolar.", true],
		[1, "", "Bir gemi için silah almadan önce yuvalarını kontrol edin: uygun yuvası olmayan silah ambarda kalır.", true],
		[1, "", "Malları, teknoloji seviyesinin onlardan yana olduğu yere kenetlenene kadar saklayın.", true],
		[1, "", "Yalnızca bir taraf için uçmak, diğer tarafın istasyonlarını ziyaret etmeyi pahalılaştırır.", true],
		[1, "", "Zaten yolculuk ederken yeni yerleri ziyaret edin: tüm galaksiyi keşfetmek her yolculuğu ücretsiz yapar.", true],
	],
}
