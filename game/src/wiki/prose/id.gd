extends RefCounted
## The reference's own writing in Indonesian. Same blocks, chapter gates and
## links as prose/en.gd; see there for the format. The game has no Indonesian
## text, so names and the game's own menu labels stay as the game shows them.

const PAGES := {
	"home": {"title": "Referensi"},
	"world/setting": {"title": "Galaksi yang dilanda perang"},
	"world/fleet": {"title": "Armada antariksa Terran"},
	"world/outlaws": {"title": "Pelanggar hukum dan bajak laut"},
	"chapter/1": {"title": "Kapal baru"},
	"chapter/2": {"title": "Sampah antariksa"},
	"chapter/3": {"title": "Perjalanan ke Phoebos"},
	"chapter/4": {"title": "Muatan Doc"},
	"chapter/5": {"title": "Konvoi senjata"},
	"chapter/6": {"title": "Mata-mata yang kabur"},
	"chapter/7": {"title": "Barang sensitif"},
	"chapter/8": {"title": "Menaiki sang raksasa"},
	"chapter/9": {"title": "Empat kapal ke Opos"},
	"chapter/10": {"title": "Front Nivelian"},
	"chapter/11": {"title": "Penyergapan di nebula"},
	"chapter/12": {"title": "Stasiun pelanggar hukum"},
	"chapter/13": {"title": "Pembalasan"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Pilot tentara bayaran"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Letnan armada antariksa"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Komandan armada antariksa"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Penumpang yang terburu-buru"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Kepala klan Vossk", "early_title": "Pilot Vossk"},
	"character/5": {"title": "John \"Doc\" Washington", "subtitle": "Pedagang"},
	"character/6": {"title": "Pilot skuadron", "subtitle": "Armada antariksa"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Perwira keamanan"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Mata-mata dalam pelarian"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Pedagang Octopod"},
	"character/10": {"title": "Feknor", "subtitle": "Dari bangsa Grey"},
	"character/11": {"title": "Laksamana Smith", "subtitle": "Armada antariksa Terran"},
	"character/12": {"title": "Botom Krant", "subtitle": "Komandan stasiun Nivelian"},
	"progress/ranks": {"title": "Reputasi dan level"},
	"progress/milestones": {"title": "Tonggak"},
	"progress/loyalty": {"title": "Loyalitas dan suap"},
	"mode/survival": {"title": "Bertahan hidup", "subtitle": "Mode permainan"},
	"mode/swarm": {"title": "Kawanan", "subtitle": "Mode permainan remake"},
	"guide/start": {"title": "Memulai"},
	"guide/flight": {"title": "Terbang dan bertempur"},
	"guide/weapons": {"title": "Senjata dan perisai"},
	"guide/hangar": {"title": "Hanggar"},
	"guide/trade": {"title": "Perdagangan dan jarahan"},
	"guide/travel": {"title": "Perjalanan dan peta"},
	"guide/jobs": {"title": "Papan pekerjaan"},
	"guide/campaign": {"title": "Kampanye dan eksplorasi bebas"},
	"guide/saves": {"title": "Menyimpan dan memuat"},
	"guide/tips": {"title": "Kiat"},
}

const BLOCKS := {
	"home": [
		[1, "", "Referensi ini menjelaskan salinan Galaxy on Fire milikmu sendiri: setiap planet dan stasiun di galaksi, kapal, senjata, dan barang di toko-tokonya, pekerjaan di papan-papannya, tokoh dalam ceritanya, serta aturan perdagangan, perjalanan, dan reputasi. Nama, deskripsi, dan dialog berasal dari berkas gim yang kamu impor; angka-angkanya mengikuti aturan yang dipakai remake ini.", false],
		[1, "", "Halaman cerita bertambah seiring kampanyemu. Bab yang belum kamu capai dan orang yang belum kamu temui tidak dimuat dalam referensi, dan akhir sebuah bab baru muncul setelah kamu menerbangkannya.", false],
	],
	"intro/world": [
		[1, "", "Latar gim: perang antara Terran dan Vossk, armada antariksa yang baru saja ditinggalkan Keith Maxwell, dan para pelanggar hukum yang memangsa kedua pihak.", false],
	],
	"intro/story": [
		[1, "", "Kampanye adalah satu alur berisi tiga belas bab. Setiap bab dimulai dengan pengarahan di sebuah stasiun dan berlanjut dengan penerbangan penuh panggilan radio. Bab-bab di bawah ini sampai sejauh yang telah dicapai pilotmu.", false],
	],
	"intro/characters": [
		[1, "", "Orang-orang yang berbicara dengan Keith Maxwell dalam pengarahan dan melalui radio. Setiap potret berasal dari gambar gim itu sendiri.", false],
	],
	"intro/races": [
		[1, "", "Sepuluh bangsa tinggal di planet dan stasiun galaksi. Penghuni suatu tempat menentukan kapal apa yang boleh dijual tokonya dan, untuk Terran dan Vossk, apakah loyalitasmu membuatmu harus membayar suap saat bepergian ke sana.", false],
	],
	"intro/galaxy": [
		[1, "", "Galaksi terbagi menjadi empat kuadran yang masing-masing berisi dua puluh lima sistem, dan setiap sistem memuat lima planet atau stasiun. Peta di bawah menampilkan semuanya; perjalanan di antara mereka terbuka setelah kampanye usai, atau langsung jika kamu melewatinya.", false],
	],
	"intro/stations": [
		[1, "", "Kelima ratus planet dan stasiun. Tingkat teknologi suatu tempat menentukan harga kargo dan potongan harga kapalnya; hanya tempat yang berdagang yang memiliki hanggar terbuka untuk semua orang.", false],
	],
	"intro/ships": [
		[1, "", "Kapal yang bisa kamu beli. Lambung, palka kargo, dan dudukan senjata membedakan mereka; toko sebagian besar bangsa menjual semuanya kecuali pesawat tempur Vossk, yang hanya dijual oleh Vossk.", false],
	],
	"intro/equipment": [
		[1, "", "Senjata dan generator perisai. Kapal hanya bisa membawa senjata jika memiliki dudukan untuk jenis senjata itu, dan hanya satu senjata dari setiap jenis sekaligus.", false],
	],
	"intro/goods": [
		[1, "", "Kargo yang ditemukan di reruntuhan kapal yang hancur. Setiap jenis barang mengikuti aturannya sendiri tentang bagaimana tingkat teknologi stasiun mengubah harganya.", false],
	],
	"intro/jobs": [
		[1, "", "Jenis pekerjaan yang ditawarkan di papan pekerjaan setelah galaksi terbuka. Imbalannya bergantung pada pekerjaan dan kuadran tempatmu berada.", false],
	],
	"intro/progress": [
		[1, "", "Cara gim mengukur pilotmu: reputasi dari musuh yang dihancurkan, level dari penghasilan, loyalitas antara Terran dan Vossk, serta pesan yang menandai kekayaan dan penjelajahanmu.", false],
	],
	"intro/modes": [
		[1, "", "Cara bermain selain kampanye dan eksplorasi bebas.", false],
	],
	"intro/guide": [
		[1, "", "Cara bermain: terbang, bertempur, memperlengkapi kapal, berdagang, bepergian, dan meniti jalan ke atas.", false],
	],
	"world/setting": [
		[1, "", "Pada milenium keempat, Terran berperang antarplanet melawan [[race/1]]. Bangsa-bangsa lain berbagi galaksi dengan mereka: sebagian bersekutu dengan salah satu pihak, sebagian berdagang dengan keduanya, sebagian nyaris tak dikenal.", false],
		[1, "", "Gim dimulai pada tahun 3587 di [[station/0]], sebuah stasiun Terran, tempat kapal penjelajah tempur SS Ulysses menurunkan [[character/0]]. Setelah diberhentikan dengan hormat dari armada antariksa, ia menerima kapal sendiri dari [[character/11|Laksamana Smith]] dan berniat mencari nafkah sebagai tentara bayaran.", false],
		[1, "Lokasi kejadian", "Seluruh kampanye berlangsung di kuadran pertama, [[quadrant/0]], dekat [[station/0]]. Sisa galaksi terbuka setelah cerita usai.", false],
		[14, "Setelah perang", "Dengan pemimpin pelanggar hukum tewas dan penggerak hiperspasial di kapal, Maxwell menolak tempat di armada. Galaksi kini miliknya untuk dijelajahi, diperdagangkan, dan diperjuangkan bagi siapa pun yang membayar.", false],
	],
	"world/fleet": [
		[1, "", "Armada antariksa Terran adalah militer dunia-dunia Terran. Maxwell bertugas di sana sebelum gim dimulai, dan sebagian besar pekerjaan kampanyenya datang dari perwiranya atau orang-orang di sekitar mereka.", false],
		[1, "", "Pesawat tempur standarnya adalah [[ship/6]]. Perwiranya dalam cerita antara lain [[character/1]], yang menunjukkan kapal baru kepada Maxwell, dan [[character/11|Laksamana Smith]], yang memberikannya.", false],
		[5, "", "Armada juga memiliki agen. Letnan Hammond bekerja menyamar di [[station/2]] atas perintah laksamana.", false],
		[6, "", "Perwira keamanan [[character/7]] memburu pengkhianat di dalam armada.", false],
		[12, "", "Tidak semua komandannya setia: salah satunya diam-diam berurusan dengan Vossk dan para pelanggar hukum di belakang armada.", false],
	],
	"world/outlaws": [
		[9, "", "Para pelanggar hukum menerbangkan kapal Terran yang dimodifikasi dan menyerang konvoi. Ketika mereka menyergap konvoi Grey jauh di wilayah Vossk, menjadi jelas bahwa mereka bekerja sama dengan Vossk.", false],
		[12, "", "Para pelanggar hukum punya pemimpin di dalam armada antariksa itu sendiri, yang menjual rahasia militer curian kepada Vossk dan menutupi serangan terhadap kapal angkut. Mereka bertahan di stasiun mereka sendiri di balik ladang ranjau.", false],
		[1, "", "Para pelanggar hukum juga punya bangsa sendiri di peta galaksi: tempat yang dihuni [[race/9]] adalah stasiun dan planet mereka. Hanya toko mereka yang menjual [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell tiba di [[station/0]] dan disambut Letnan [[character/1]], yang mendapat perintah dari Laksamana Smith untuk menunjukkan kapal barunya, sebuah kapal pengintai [[ship/0]] tua. Ia menjelaskan hanggar: kapal, senjata, dan perlengkapan dibeli di toko, dan kargo yang dikumpulkan di antariksa dijual dari palka.", false],
		[1, "", "Lalu tiba penerbangan uji. Christine memandunya melewati titik jalan, menjelaskan perisai, pergantian senjata, menembak, dan dorongan, lalu melepas beberapa drone latihan untuk ditembak jatuh.", false],
		[2, "Akhir", "Maxwell menghancurkan drone dan kembali ke stasiun. Christine mendoakannya beruntung dan berharap bertemu lagi dengannya dalam keadaan utuh.", false],
	],
	"chapter/2": [
		[2, "", "Wajah yang tak diharapkan dari armada: Komandan [[character/2]], yang tak pernah bisa ditoleransi Maxwell, punya pekerjaan untuknya. Sebuah koridor antariksa dekat stasiun harus dibersihkan dari puing sebelum konvoi berikutnya tiba, dan waktunya hanya dua menit.", false],
		[3, "Akhir", "Koridor bersih tepat waktu dan Vlad membayar, sambil berkomentar bahwa Maxwell memang cocok untuk pekerjaan itu.", false],
	],
	"chapter/3": [
		[3, "", "Seorang klien kecil yang gugup, [[character/3]], ingin segera diantar ke [[station/1]] sebelum kesepakatannya batal. Tempat itu dipenuhi Vossk, tetapi ia membayar mahal dan Maxwell setuju.", false],
		[4, "Akhir", "Di tengah jalan, patroli Vossk menuntut mereka menyerah. Maxwell berhasil mengantar Bolar, dan penumpang itu berjanji merekomendasikannya begitu ia berhenti gemetar.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] membutuhkan pengawalan untuk kapalnya ke [[station/2]], sarang para bajak laut. Maxwell menaikkan tarif karena risikonya dan menduga muatannya adalah kiriman senjata lain untuk para pelanggar hukum.", false],
		[5, "Akhir", "Pesawat tempur Vossk menyerang kapal kargo itu dua kali. Kapal itu mencapai Tortuga, dan Doc menegaskan bahwa isinya bukan urusan Maxwell.", false],
	],
	"chapter/5": [
		[5, "", "Di Tortuga, Maxwell bertemu [[character/1]], yang sedang menyamar di sana. Armada diperintahkan mencegat konvoi senjata Vossk dekat [[station/3]]; jika kiriman itu lolos, akan terjadi pembantaian. Skuadronnya membutuhkan satu pilot berpengalaman lagi.", false],
		[6, "Akhir", "Pengawal tumbang lebih dulu, lalu kapal-kapal kargo. Konvoi dihentikan, dan Christine yakin Laksamana Smith akan puas.", false],
	],
	"chapter/6": [
		[6, "", "Perwira keamanan [[character/7]] punya tugas yang tak boleh gagal: [[character/8]], seorang mata-mata, kabur dengan salah satu kapal rahasia armada. Kapal itu tak boleh jatuh ke tangan musuh dan, bila perlu, harus dihancurkan.", false],
		[7, "Akhir", "Maxwell menemukan Lockwood di sebuah ladang asteroid dan merusak kapalnya sampai ia menyerah. Sebelum ada yang sempat menahannya, [[character/2|Vlad Borsikov]] menembaknya jatuh dan mengingatkan Maxwell bahwa perintahnya adalah menghancurkan kapal. Maxwell mulai curiga bahwa ini tak pernah hanya soal sebuah kapal.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] meminta pengawalan untuk kapal-kapalnya ke [[station/4]]. Maxwell mengenali geng Octopod, yang terkenal penuh barang curian, tetapi menerima pekerjaan itu selama pihak berwenang tidak ikut campur.", false],
		[8, "Akhir", "Yang dimulai sebagai uang mudah berubah menjadi pertempuran melawan pesawat tempur Vossk dan sebuah kapal penjelajah. Setidaknya satu kapal lolos, dan Maxwell mencatat bahwa Vossk makin agresif.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] menemukan kapal penjelajah tempur Vossk yang lumpuh. Armada ingin merebutnya dan menangkap komandannya hidup-hidup, tetapi setiap meriam tetap di lambungnya harus dihancurkan dulu.", false],
		[9, "Akhir", "Selagi skuadron Christine menarik tembakan, Maxwell melumpuhkan meriam-meriam itu, dan kapal itu dinaiki.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]] dari bangsa Grey menyewa Maxwell untuk membawa konvoi empat kapal ke [[station/5]], langsung melintasi wilayah Vossk, dan membayar untuk setiap kapal yang tiba.", false],
		[10, "Akhir", "Para penyerang bukan Vossk melainkan kapal Terran yang dimodifikasi. Maxwell mengusir mereka dan menyimpulkan bahwa para pelanggar hukum bekerja sama dengan Vossk.", false],
	],
	"chapter/10": [
		[10, "", "[[character/11]] membutuhkan setiap pilot yang tersedia: sebuah stasiun milik sekutu Terran, bangsa Nivelian, diserang pasukan Vossk yang kuat. Setelah adu kata yang tajam soal tarif dan loyalitas Maxwell, laksamana mengirimnya.", false],
		[11, "Akhir", "Komandan stasiun [[character/12]] meminta Maxwell berfokus pada kapal penjelajah sementara [[character/1|Christine]] menangani pesawat tempur. Serangan berhasil dipukul mundur, dan keduanya sepakat bahwa para pelanggar hukum adalah bahaya yang tersisa.", false],
	],
	"chapter/11": [
		[11, "", "Seorang kepala klan Vossk, [[character/4]], diam-diam menghubungi Maxwell. Salah satu komandan Vossk bersekongkol dengan seorang perwira Terran dan para pelanggar hukum, dan klan menginginkan kematiannya. Tempat terbaik untuk penyergapan adalah Nebula Yarapu.", false],
		[12, "Akhir", "Maxwell menghancurkan kapal penjelajah sang komandan beserta pengawalnya. Nartok memberitahunya bahwa pengkhianat di pihak Terran adalah kenalan lama Maxwell, dan bahwa Letnan Hammond sudah melacaknya.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] membawa kabar: [[character/2]] adalah pemimpin para pelanggar hukum. Sebagai komandan, ia menutupi serangan terhadap kapal angkut dan menyuruh Lockwood mencuri rahasia militer untuk dijual kepada Vossk. Gengnya membentengi diri di sebuah stasiun pelanggar hukum yang dilindungi ladang ranjau, yang harus dibersihkan Maxwell sebelum serangan.", false],
		[13, "Akhir", "Ladang ranjau dibersihkan dan para pembela stasiun tumbang. Christine menerjang Vlad, yang menembaknya jatuh sebelum Maxwell sempat melindunginya, lalu kabur.", false],
	],
	"chapter/13": [
		[13, "", "[[character/11]] menyampaikan belasungkawa; Maxwell hanya ingin tahu ke mana Vlad pergi. Armada telah menemukan Vlad dan sisa-sisa pelanggar hukumnya, dan skuadronnya membutuhkan bantuan Maxwell untuk menghancurkan mereka.", false],
		[14, "Akhir", "Setelah para pelanggar hukum dihancurkan, Maxwell membiarkan armada mengurus sisanya, mengejar Vlad sendirian, dan membunuhnya. Laksamana menawarinya tempat di armada; Maxwell menolak. Ia menerima penggerak hiperspasial yang membuka setiap kuadran galaksi.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell adalah pilot pemain: mantan pilot armada antariksa Terran yang, setelah diberhentikan dengan hormat, menerima kapal dari [[character/11|Laksamana Smith]] dan memulai hidup sebagai tentara bayaran di [[station/0]].", false],
		[1, "", "Ia sarkastis dan cepat menawar bayarannya, tetapi menuntaskan pekerjaan yang diterimanya.", false],
		[7, "", "Ia memprotes ketika [[character/2|Vlad Borsikov]] menembak jatuh orang yang sudah menyerah.", false],
		[13, "", "Kematian [[character/1|Christine Hammond]] menjadikan bab terakhir urusan pribadi.", false],
		[14, "", "Setelah membunuh Vlad, ia menolak kembali ke armada dan lebih memilih jalannya sendiri di galaksi.", false],
	],
	"character/1": [
		[1, "", "Letnan Christine Hammond dari armada antariksa Terran menyambut Maxwell di [[station/0]], menunjukkan kapalnya, dan menerbangkan penerbangan uji pertamanya bersamanya. Ia meminta dipanggil Christine.", false],
		[5, "", "Ia juga bekerja sebagai agen: di [[station/2]] ia menyamar atas perintah Laksamana Smith, dan ia mengajak Maxwell dalam serangan terhadap konvoi senjata Vossk.", false],
		[8, "", "Ia memimpin skuadron yang merebut kapal penjelajah tempur Vossk yang lumpuh.", false],
		[12, "", "Ia mengungkap bahwa [[character/2|Vlad Borsikov]] berada di balik para pelanggar hukum dan merencanakan serangan ke stasiun mereka.", false],
		[13, "", "Ia menerjang Vlad setelah pertempuran dan ditembak jatuh olehnya. Kematiannya membuat Maxwell memburu Vlad di bab terakhir.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov adalah komandan armada antariksa Terran dan, menurut Maxwell, orang paling brengsek di dalamnya. Ia memberi Maxwell pekerjaan berbayar pertamanya: membersihkan koridor antariksa dari puing dalam waktu terbatas.", false],
		[7, "", "Ia menembak jatuh mata-mata Corsair Lockwood setelah orang itu menyerah, dan bersikeras bahwa perintahnya adalah menghancurkan kapal.", false],
		[12, "", "Dialah pengkhianatnya: pemimpin para pelanggar hukum, yang memakai pangkatnya untuk menutupi serangan terhadap kapal angkut dan menyuruh Lockwood mencuri rahasia militer yang ia jual kepada Vossk.", false],
		[13, "", "Ketika Christine Hammond mengejarnya setelah serangan ke stasiunnya, ia menembaknya jatuh dan kabur.", false],
		[14, "", "Armada menemukannya bersama sisa pelanggar hukumnya, dan Maxwell membunuhnya dalam duel.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon adalah klien gelisah yang harus segera mencapai [[station/1]] untuk menyelamatkan kesepakatan, dan membayar mahal pilot yang mau membawanya melintasi wilayah Vossk.", false],
		[4, "", "Ia selamat dari penyergapan Vossk dan berjanji merekomendasikan Maxwell.", false],
	],
	"character/4": [
		[4, "", "Seorang Vossk berwajah ini memanggil Maxwell dalam perjalanan ke Phoebos dan menuntutnya menyerah atas nama Kekaisaran Vossk.", false],
		[11, "", "Nartok Brek adalah kepala klan [[race/1]]. Ia diam-diam menghubungi Maxwell karena salah satu komandannya sendiri bersekongkol dengan seorang perwira Terran dan para pelanggar hukum, dan meminta agar pengkhianat itu disergap di Nebula Yarapu. Ia meminta janji kehormatan Maxwell sebelum mengatakan apa pun.", false],
		[12, "", "Setelah penyergapan, ia memberi tahu Maxwell bahwa pengkhianat Terran itu adalah kenalan lama Maxwell sendiri.", false],
	],
	"character/5": [
		[4, "", "John Washington, yang dipanggil Doc oleh teman-temannya, membutuhkan pengawalan untuk kapalnya ke [[station/2]]. Ia menawarkan 3.000 kredit dan akhirnya setuju 4.500, dengan syarat tak ada saksi. Maxwell menduga ini kiriman senjata untuk para pelanggar hukum.", false],
		[5, "", "Muatannya tiba. Apa isinya, ia simpan sendiri.", false],
	],
	"character/6": [
		[6, "", "Seorang pilot dari skuadron Christine Hammond yang bertanya lewat radio apakah Maxwell ini pernah bertempur, tanpa sadar bahwa Maxwell bisa mendengarnya.", false],
		[13, "", "Skuadron yang sama tetap tinggal untuk mengamankan stasiun pelanggar hukum selagi Christine dan Maxwell mengejar Vlad.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom adalah perwira keamanan armada antariksa. Ia mengirim Maxwell mengejar mata-mata [[character/8]], dengan perintah bahwa kapal curian itu tak boleh jatuh ke tangan musuh.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood adalah mata-mata yang kabur dengan salah satu kapal rahasia armada antariksa.", false],
		[7, "", "Terpojok di ladang asteroid, ia menyerah, tetapi tetap ditembak jatuh oleh Vlad Borsikov.", false],
		[12, "", "Belakangan terungkap bahwa Vlad sendirilah yang sejak awal menyuruhnya mencuri rahasia militer.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt mengangkut barang untuk geng Octopod, yang terkenal membawa barang curian. Ia bersikeras bahwa semua yang ada di kapal sepenuhnya legal dan membayar Maxwell untuk membawa kapal-kapalnya ke [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor dari bangsa Grey pernah mendengar tentang Maxwell dan menawarinya pekerjaan sulit: empat kapal ke [[station/5]] melintasi wilayah Vossk, dengan bayaran 4.000 kredit untuk setiap kapal yang tiba.", false],
	],
	"character/11": [
		[1, "", "Laksamana Smith dari armada antariksa Terran memberikan kapal kepada Maxwell setelah ia diberhentikan, dan menugaskan Letnan Hammond menunjukkan cara memakainya.", false],
		[10, "", "Ia memanggil Maxwell ketika stasiun Nivelian diserang. Percakapan mereka memanas ketika Maxwell membicarakan tarifnya dan berapa yang mungkin dibayar Vossk.", false],
		[13, "", "Setelah kematian Christine, ia menyampaikan belasungkawa kepada Maxwell dan memberi tahu lokasi para pelanggar hukum Vlad.", false],
		[14, "", "Ia membiarkan Maxwell mengejar Vlad sendirian, menawarinya tempat di armada, dan memberinya penggerak hiperspasial ketika ia menolak.", false],
	],
	"character/12": [
		[11, "", "Botom Krant memimpin stasiun Nivelian yang diserang Vossk. Ia meminta Maxwell berfokus pada kapal penjelajah dan berterima kasih setelah serangan dipukul mundur.", false],
	],
	"race/0": [
		[1, "", "Manusia, yang berperang dengan [[race/1]] pada milenium keempat. Maxwell adalah Terran, dan sebagian besar klien kampanye bertugas di armada antariksa Terran. Terran memiliki lebih banyak planet dan stasiun daripada bangsa lain mana pun.", false],
		[1, "", "Banyak kapal yang dijual adalah rancangan Terran: [[ship/0]], [[ship/6]] beserta versi modifikasinya [[ship/7]], dan kapal meriam [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "Musuh Terran. Toko Vossk hanya menjual pesawat tempur mereka sendiri, [[ship/8]], dan hanya mereka yang menjual senjata Vossk. Pilot yang bekerja untuk Terran dimintai suap di stasiun Vossk, dan sebaliknya.", false],
	],
	"race/2": [
		[1, "", "Salah satu bangsa di galaksi, dengan planet dan stasiun sendiri.", false],
	],
	"race/3": [
		[1, "", "Salah satu bangsa di galaksi, dengan planet dan stasiun sendiri.", false],
	],
	"race/4": [
		[1, "", "Komponen khusus mereka dipakai dalam senjata seperti [[equipment/23]], dan pengebom berat [[ship/3]] adalah milik mereka.", false],
	],
	"race/5": [
		[1, "", "Kapal Grey terkenal dengan lapisan bajanya yang sangat berat. Kapal pengintai [[ship/9]] berasal dari armada mereka dan baru belakangan disesuaikan untuk pilot humanoid, dan rudal [[equipment/4]] dibuat dari komponen Grey. Feknor dari bangsa Grey menyewa Maxwell untuk konvoi yang berbahaya.", false],
	],
	"race/6": [
		[1, "", "Sekutu Terran. Pesawat tempur [[ship/1]] adalah hasil pengembangan Nivelian, dan laser [[equipment/2]] didasarkan pada teknologi senjata Nivelian. Serangan Vossk ke salah satu stasiun mereka menyeret Maxwell sungguh-sungguh ke dalam perang.", false],
	],
	"race/7": [
		[1, "", "Salah satu bangsa di galaksi, dengan planet dan stasiun sendiri.", false],
	],
	"race/8": [
		[1, "", "Salah satu bangsa di galaksi, dengan planet dan stasiun sendiri.", false],
	],
	"race/9": [
		[1, "", "Para pelanggar hukum bukan sebuah bangsa melainkan cara hidup: bajak laut dan penyelundup yang memiliki planet dan stasiun sendiri. Hanya toko mereka yang menjual [[ship/7]], dan [[station/2]] adalah sarang mereka yang paling terkenal.", false],
	],
	"galaxy": [
		[1, "", "Empat kuadran, seratus sistem, dan lima ratus planet dan stasiun. Setiap kuadran lebih sulit daripada yang sebelumnya: pekerjaannya membayar lebih, musuhnya lebih tangguh, dan tokonya menjual perlengkapan yang lebih baik.", false],
		[1, "", "Terbang di dalam satu kuadran memakan kredit sesuai jarak; pindah ke kuadran tetangga atau kuadran seberang dikenai biaya tambahan. Setelah kamu mengunjungi setiap tempat di galaksi, perjalanan menjadi gratis.", false],
	],
	"progress/ranks": [
		[1, "Reputasi", "Reputasi menghitung musuh yang telah kamu hancurkan. Setiap ambang di tabel di bawah menaikkan pangkatmu, yang ditampilkan di layar \"Status\".", false],
		[1, "Level", "Levelmu naik seiring uang yang kamu peroleh dari misi dan pekerjaan. Setiap kali total penghasilanmu melampaui 1,6 kali jumlahnya pada level terakhir, kamu mencapai level berikutnya. Level yang lebih tinggi membuat musuh dalam misimu lebih tangguh.", false],
	],
	"progress/milestones": [
		[1, "", "Saat kamu berlabuh, stasiun menyambutmu dengan pesan pertama kali kreditmu melewati sebuah tonggak atau penjelajahan galaksimu mencapai tanda baru. Pesan-pesan di bawah adalah milik gim itu sendiri.", false],
		[1, "Kekayaan", "Kekayaan lebih dari sekadar angka. Dengan lebih dari 999.999 kredit, kamu bisa berdagang di setiap planet dan stasiun: hanggar terbuka bahkan di tempat yang tidak berdagang, dan di sana kamu bisa membeli, menjual kargo dan jarahan, serta memperlengkapi ulang kapalmu.", false],
		[1, "Penjelajahan", "Setiap tempat yang kamu kunjungi dihitung. Mengunjungi kelima ratusnya membuat setiap perjalanan gratis.", false],
	],
	"progress/loyalty": [
		[1, "", "Loyalitasmu berada di suatu titik antara Terran dan Vossk, ditunjukkan oleh penunjuk di layar \"Status\". Setiap misi untuk klien Terran menggesernya satu langkah ke arah Terran; setiap misi untuk klien Vossk satu langkah ke arah Vossk. Loyalitas tak bisa melewati sepuluh langkah ke arah mana pun.", false],
		[1, "", "Jika kamu bepergian ke tempat Terran saat loyalitasmu condong ke Vossk, atau ke tempat Vossk saat condong ke Terran, kamu dimintai uang suap di luar biaya terbang: 150 kredit untuk setiap langkah. Membayar suap menggeser loyalitasmu satu langkah kembali ke tengah.", false],
	],
	"mode/survival": [
		[1, "", "Bertahan hidup adalah mode terpisah dengan pilot dan tabel skor tertinggi sendiri. Pilih di \"Start Game\". Kapal musuh terus berdatangan, setiap penghancuran memberi poin dan memperbaiki lambungmu, dan warna penanda musuh menunjukkan seberapa kuat ia. Skormu memberimu pangkat dari tabel di bawah.", false],
	],
	"mode/swarm": [
		[1, "", "Kawanan adalah mode yang dibuat untuk remake ini, ada di \"Start Game\". Mode ini dimulai dengan segelintir pesawat tempur dan tumbuh menjadi kerumunan yang mengepung dari segala arah, dengan gelombang setelah menit kelima.", false],
		[1, "", "Setiap penghancuran mengisi bilah level. Setiap level menawarkan tiga kartu peningkatan: senjata baru, versi lebih baik dari senjata yang kamu bawa, laras tambahan, jangkauan atau kecepatan proyektil lebih besar, perisai lebih kuat, perbaikan di setiap penghancuran, atau lambung lain. Menolak kartu justru memperbaiki seperempat lambungmu.", false],
		[1, "", "Senjata, perisai, dan lambungnya adalah yang ada di berkas gimmu. Mencapai pangkat di papan skor Bertahan hidup membuka lambung berikutnya untuk Kawanan.", false],
	],
	"guide/start": [
		[1, "", "Setelah berkas gim diimpor, \"Start Game\" menawarkan kampanye, eksplorasi bebas, Bertahan hidup, dan Kawanan. Kampanye dimulai di [[station/0]] dengan sebuah [[ship/0]] dan 5.000 kredit.", false],
		[1, "Menu stasiun", "Di stasiun, \"Info\" menjelaskan tempat itu, \"Hangar\" membuka toko dan kapalmu, \"Missions\" menampilkan papan pekerjaan, dan \"Map\" memungkinkanmu bepergian. Selama kampanye, papan pekerjaan dan peta tetap terkunci, dan \"Go on\" memulai pengarahan berikutnya. \"Status\" menampilkan level, reputasi, waktu bermain, jumlah musuh yang dihancurkan, dan loyalitasmu, sedangkan \"Menu\" berisi opsi dan penyimpanan.", false],
		[1, "", "Tidak setiap tempat punya hanggar yang terbuka untuk semua: tanpa perdagangan, hanggar hanya terbuka selama kampanye atau ketika kamu punya lebih dari 999.999 kredit.", false],
	],
	"guide/flight": [
		[1, "", "Titik jalan ditandai kuning, sekutu hijau, dan musuh merah. Objek di luar pandanganmu ditampilkan di tepi layar. Sisa kekuatan musuh ditampilkan di bawah penandanya.", false],
		[1, "", "Perisaimu menyerap tabrakan dan tembakan lalu terisi kembali seiring waktu; setelah habis, kerusakan mengenai lambung. Dorongan memberi ledakan kecepatan singkat dan perlu waktu untuk terisi ulang.", false],
		[1, "Kontrol", "Dengan papan ketik, kemudikan dengan tetikus atau tombol panah, atur daya dorong dengan W dan S, dan bergeser ke samping dengan A dan D. Tembak dengan klik atau Spasi, ganti senjata dengan Q, luncurkan rudal dengan F, dan dorong dengan Shift. R mengaktifkan autopilot, T mempercepat waktu di bagian yang aman, E berlabuh di dekat stasiun, dan Esc menjeda. Pengendali membidik dengan stik kanan dan menembak dengan pelatuk kanan. Kontrol sentuh memiliki stik, tuas gas, dan tombol tembak, rudal, dorongan, dan navigasi; ketuk dua kali Tembak untuk menyalakan tembakan otomatis.", false],
		[1, "Autopilot dan waktu", "Autopilot terbang ke titik jalan berikutnya atau ke stasiun. Selama tak ada yang mengancammu, waktu bisa berjalan lebih cepat; musuh, kerusakan, atau tiba di tujuan mengembalikannya ke normal.", false],
	],
	"guide/weapons": [
		[1, "", "Kapal memiliki dudukan untuk lima jenis senjata: laser, meriam plasma, meriam foton, rudal, dan meriam termo. Setiap dudukan memuat satu senjata, dan setiap kapal punya susunan dudukannya sendiri. Generator perisai cocok untuk semua kapal.", false],
		[1, "", "Laser dan meriam plasma menembak cepat pada jarak menengah. Meriam foton menjangkau paling jauh dan menghantam paling keras per tembakan, tetapi lambat diisi ulang. Meriam termo menyemburkan partikel dari jarak dekat dengan laju tembak sangat tinggi. Rudal diluncurkan dengan tombolnya sendiri tanpa mengganti senjata, dan memberi kerusakan berat dengan waktu isi ulang yang lama.", false],
		[1, "", "Perisai berbeda dalam kapasitas dan kecepatan pengisian. Senjata terkuat hanya dijual mulai kuadran kedua, dan senjata Vossk hanya di toko Vossk.", false],
	],
	"guide/hangar": [
		[1, "", "Hanggar punya tiga bagian: \"Ship\" menampilkan kapalmu beserta senjata terpasang dan perisainya, \"Cargo\" menyimpan barang dan perlengkapan cadanganmu, dan \"Shop\" menawarkan stok stasiun.", false],
		[1, "", "Perlengkapan yang dibeli masuk ke palka kargo; pasang dari sana jika kapalmu punya dudukan kosong untuknya. Perlengkapan dan kapal dijual kembali setengah harga.", false],
		[1, "", "Membeli kapal berarti menukar-tambah kapalmu saat ini. Perlengkapan yang cocok dengan kapal baru tetap terpasang dan sisanya pindah ke palka, selama masih ada ruang.", false],
		[1, "", "Toko menjual satu sampai empat senjata atau perisai dan paling banyak tiga kapal, dipilih dari yang diizinkan kuadran dan bangsa tempat itu. Stok toko diperbarui saat kamu kembali setelah terbang ke tempat lain. Selama kampanye, setiap bab punya stok tetapnya sendiri.", false],
	],
	"guide/trade": [
		[1, "", "Barang berasal dari reruntuhan kapal yang hancur dan dikumpulkan ke palkamu setelah misi. Jual di bagian kargo hanggar. Sebagian paling mahal di tempat berteknologi rendah, sebagian di tempat berteknologi tinggi, dan sebagian sama harganya di mana-mana; setiap halaman barang mencantumkan harganya di setiap tingkat teknologi.", false],
		[1, "", "Toko tidak punya barang sendiri. Apa yang kamu jual di sebuah toko tetap ada di stoknya, dan kamu bisa membelinya kembali di sana dengan harga yang sama.", false],
		[1, "", "Perdagangan membutuhkan hanggar: planet dan stasiun tanpa perdagangan hanya membuka hanggarnya bagi pilot yang punya lebih dari 999.999 kredit.", false],
	],
	"guide/travel": [
		[1, "", "Peta menampilkan galaksi beserta kuadran dan sistemnya. Pilih tempat dan bepergianlah ke sana dengan biaya terbang yang tertera, ditambah suap jika loyalitasmu berlawanan dengan bangsanya. Kamu tiba dalam keadaan berlabuh.", false],
		[1, "", "Biaya terbang bertambah dengan jarak. Pindah kuadran menambah 15.000 kredit, dan 30.000 untuk kuadran seberang. Peta menunjukkan seberapa banyak galaksi yang telah kamu jelajahi; setelah semua tempat dikunjungi, perjalanan tidak memakan biaya.", false],
		[1, "", "Galaksi terbuka saat kampanye selesai atau saat kamu melewatinya.", false],
	],
	"guide/jobs": [
		[1, "", "Di luar kampanye, papan pekerjaan setiap stasiun menawarkan beberapa pekerjaan dari klien berbagai bangsa. Masing-masing menunjukkan tingkat kesulitan dan imbalannya; pekerjaan sulit membayar lebih, begitu pula kuadran yang lebih jauh.", false],
		[1, "", "Sesekali, seorang penipu mencurigakan menawarkan pekerjaan yang membayar empat puluh persen lebih tinggi dari biasanya. Pekerjaan yang selesai membayar imbalannya dan menggeser loyalitasmu ke arah bangsa klien.", false],
	],
	"guide/campaign": [
		[1, "", "Kampanye adalah satu alur berisi tiga belas misi. Misi yang berhasil membayar imbalannya; misi yang gagal bisa diulang. Setelah kampanye selesai, penggerak hiperspasial membuka galaksi, dan papan pekerjaan serta peta menjadi tersedia.", false],
		[1, "", "\"Lewati kampanye · Jelajahi\" di menu awal atau di menu stasiun langsung membawa ke eksplorasi bebas. Melewati kampanye tidak memberi imbalan penyelesaian dan menyimpan pilot kampanyemu di slotnya sendiri.", false],
	],
	"guide/saves": [
		[1, "", "Gim menyimpan otomatis setelah setiap misi dan di titik pemeriksaan. Kampanye, eksplorasi, Bertahan hidup, dan Kawanan punya simpanan terpisah. \"Muat / pulihkan\" di menu jeda, atau \"Load\" setelah kekalahan, kembali ke simpanan otomatis terakhir, awal penerbangan, atau stasiun terakhir.", false],
		[1, "", "\"Berkas game\" → \"Transfer simpanan\" memindahkan simpananmu ke perangkat lain yang telah mengimpor berkas gim yang sama.", false],
	],
	"guide/tips": [
		[1, "", "Jual kargo yang kamu kumpulkan dari reruntuhan sebelum membeli perlengkapan; palka cepat penuh di kapal kecil.", true],
		[1, "", "Periksa dudukan kapal sebelum membeli senjata untuknya: senjata tanpa dudukan yang cocok tetap di palka.", true],
		[1, "", "Simpan barang sampai kamu berlabuh di tempat yang tingkat teknologinya menguntungkan barang itu.", true],
		[1, "", "Hanya terbang untuk satu pihak membuat kunjungan ke stasiun pihak lain menjadi mahal.", true],
		[1, "", "Kunjungi tempat baru ketika kamu memang sedang bepergian: menjelajahi seluruh galaksi membuat setiap perjalanan gratis.", true],
	],
}
