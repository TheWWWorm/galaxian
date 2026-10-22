extends RefCounted
## The reference's own writing in Vietnamese. Same blocks, chapter gates and
## links as prose/en.gd; see there for the format. The game has no Vietnamese
## text, so names and the game's own menu labels stay as the game shows them.

const PAGES := {
	"home": {"title": "Tra cứu"},
	"world/setting": {"title": "Thiên hà chìm trong chiến tranh"},
	"world/fleet": {"title": "Hạm đội không gian Terran"},
	"world/outlaws": {"title": "Kẻ ngoài vòng pháp luật và cướp biển"},
	"chapter/1": {"title": "Con tàu mới"},
	"chapter/2": {"title": "Rác vũ trụ"},
	"chapter/3": {"title": "Chuyến bay tới Phoebos"},
	"chapter/4": {"title": "Hàng của Doc"},
	"chapter/5": {"title": "Đoàn tàu vũ khí"},
	"chapter/6": {"title": "Gián điệp bỏ trốn"},
	"chapter/7": {"title": "Hàng nhạy cảm"},
	"chapter/8": {"title": "Đổ bộ lên gã khổng lồ"},
	"chapter/9": {"title": "Bốn con tàu tới Opos"},
	"chapter/10": {"title": "Mặt trận Nivelian"},
	"chapter/11": {"title": "Phục kích trong tinh vân"},
	"chapter/12": {"title": "Trạm của bọn ngoài vòng pháp luật"},
	"chapter/13": {"title": "Báo thù"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Phi công đánh thuê"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Trung úy hạm đội không gian"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Chỉ huy hạm đội không gian"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Hành khách vội vã"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Tộc trưởng Vossk", "early_title": "Phi công Vossk"},
	"character/5": {"title": "John \"Doc\" Washington", "subtitle": "Thương nhân"},
	"character/6": {"title": "Phi công phi đội", "subtitle": "Hạm đội không gian"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Sĩ quan an ninh"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Gián điệp đang lẩn trốn"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Thương nhân Octopod"},
	"character/10": {"title": "Feknor", "subtitle": "Người Grey"},
	"character/11": {"title": "Đô đốc Smith", "subtitle": "Hạm đội không gian Terran"},
	"character/12": {"title": "Botom Krant", "subtitle": "Chỉ huy trạm Nivelian"},
	"progress/ranks": {"title": "Danh tiếng và cấp độ"},
	"progress/milestones": {"title": "Cột mốc"},
	"progress/loyalty": {"title": "Lòng trung thành và hối lộ"},
	"mode/survival": {"title": "Sinh tồn", "subtitle": "Chế độ chơi"},
	"mode/swarm": {"title": "Bầy đàn", "subtitle": "Chế độ chơi của bản làm lại"},
	"guide/start": {"title": "Bắt đầu"},
	"guide/flight": {"title": "Bay và chiến đấu"},
	"guide/weapons": {"title": "Vũ khí và khiên"},
	"guide/hangar": {"title": "Nhà chứa"},
	"guide/trade": {"title": "Buôn bán và chiến lợi phẩm"},
	"guide/travel": {"title": "Di chuyển và bản đồ"},
	"guide/jobs": {"title": "Bảng công việc"},
	"guide/campaign": {"title": "Chiến dịch và khám phá tự do"},
	"guide/saves": {"title": "Lưu và tải"},
	"guide/tips": {"title": "Mẹo"},
}

const BLOCKS := {
	"home": [
		[1, "", "Mục tra cứu này mô tả bản Galaxy on Fire của riêng bạn: mọi hành tinh và trạm trong thiên hà, tàu, vũ khí và hàng hóa trong các cửa hàng, công việc trên các bảng, nhân vật trong câu chuyện cùng các quy tắc buôn bán, di chuyển và danh tiếng. Tên, mô tả và hội thoại lấy từ tệp game bạn đã nhập; các con số theo quy tắc mà bản làm lại này sử dụng.", false],
		[1, "", "Các trang cốt truyện mở rộng theo chiến dịch của bạn. Những chương bạn chưa tới và những người bạn chưa gặp sẽ không có trong mục tra cứu, và kết cục của một chương chỉ xuất hiện sau khi bạn đã bay qua nó.", false],
	],
	"intro/world": [
		[1, "", "Bối cảnh của game: cuộc chiến giữa người Terran và Vossk, hạm đội không gian mà Keith Maxwell vừa rời đi, và những kẻ ngoài vòng pháp luật săn mồi cả hai phe.", false],
	],
	"intro/story": [
		[1, "", "Chiến dịch là một mạch duy nhất gồm mười ba chương. Mỗi chương bắt đầu bằng một buổi chỉ thị tại trạm và tiếp tục bằng một chuyến bay đầy những cuộc gọi vô tuyến. Các chương dưới đây kéo dài tới nơi phi công của bạn đã đến.", false],
	],
	"intro/characters": [
		[1, "", "Những người trò chuyện với Keith Maxwell trong các buổi chỉ thị và qua vô tuyến. Mỗi chân dung đều lấy từ hình ảnh của chính game.", false],
	],
	"intro/races": [
		[1, "", "Mười dân tộc sống trên các hành tinh và trạm của thiên hà. Cư dân của một nơi quyết định cửa hàng ở đó được bán tàu nào, và với người Terran và Vossk, liệu lòng trung thành của bạn có khiến bạn phải trả tiền hối lộ khi tới đó hay không.", false],
	],
	"intro/galaxy": [
		[1, "", "Thiên hà được chia thành bốn góc phần tư, mỗi góc gồm hai mươi lăm hệ sao, và mỗi hệ sao có năm hành tinh hoặc trạm. Bản đồ dưới đây hiển thị tất cả; việc di chuyển giữa chúng mở ra khi chiến dịch kết thúc, hoặc ngay lập tức nếu bạn bỏ qua nó.", false],
	],
	"intro/stations": [
		[1, "", "Toàn bộ năm trăm hành tinh và trạm. Trình độ công nghệ của một nơi quyết định giá hàng hóa và mức giảm giá tàu; chỉ những nơi có buôn bán mới có nhà chứa mở cho mọi người.", false],
	],
	"intro/ships": [
		[1, "", "Các con tàu bạn có thể mua. Thân tàu, khoang hàng và giá gắn vũ khí làm nên khác biệt; cửa hàng của hầu hết các dân tộc bán tất cả trừ tiêm kích Vossk, thứ chỉ người Vossk bán.", false],
	],
	"intro/equipment": [
		[1, "", "Vũ khí và máy tạo khiên. Một con tàu chỉ mang được vũ khí nếu có giá gắn cho loại vũ khí đó, và mỗi loại chỉ mang một vũ khí cùng lúc.", false],
	],
	"intro/goods": [
		[1, "", "Hàng hóa tìm thấy trong xác tàu bị phá hủy. Mỗi loại hàng có quy tắc riêng về việc trình độ công nghệ của trạm thay đổi giá của nó ra sao.", false],
	],
	"intro/jobs": [
		[1, "", "Các loại công việc trên bảng công việc khi thiên hà đã mở. Phần thưởng tùy thuộc vào công việc và góc phần tư bạn đang ở.", false],
	],
	"intro/progress": [
		[1, "", "Cách game đánh giá phi công của bạn: danh tiếng từ số kẻ địch hạ được, cấp độ từ thu nhập, lòng trung thành giữa Terran và Vossk, và những thông điệp ghi nhận sự giàu có cùng hành trình khám phá của bạn.", false],
	],
	"intro/modes": [
		[1, "", "Những cách chơi khác ngoài chiến dịch và khám phá tự do.", false],
	],
	"intro/guide": [
		[1, "", "Cách chơi: bay, chiến đấu, trang bị, buôn bán, di chuyển và vươn lên.", false],
	],
	"world/setting": [
		[1, "", "Vào thiên niên kỷ thứ tư, người Terran đang tiến hành một cuộc chiến liên hành tinh chống lại [[race/1]]. Các dân tộc khác cùng chia sẻ thiên hà với họ: có dân tộc liên minh với một phe, có dân tộc buôn bán với cả hai, có dân tộc gần như chưa ai biết.", false],
		[1, "", "Game bắt đầu vào năm 3587 tại [[station/0]], một trạm Terran, nơi tuần dương hạm SS Ulysses đưa [[character/0]] tới. Sau khi giải ngũ trong danh dự khỏi hạm đội không gian, anh được [[character/11|Đô đốc Smith]] tặng một con tàu riêng và định kiếm sống bằng nghề lính đánh thuê.", false],
		[1, "Nơi diễn ra", "Toàn bộ chiến dịch diễn ra ở góc phần tư thứ nhất, [[quadrant/0]], gần [[station/0]]. Phần còn lại của thiên hà mở ra khi câu chuyện kết thúc.", false],
		[14, "Sau chiến tranh", "Kẻ cầm đầu bọn ngoài vòng pháp luật đã chết, trên tàu có động cơ siêu không gian, và Maxwell từ chối một vị trí trong hạm đội. Thiên hà là của anh để khám phá, buôn bán và chiến đấu cho bất kỳ ai trả tiền.", false],
	],
	"world/fleet": [
		[1, "", "Hạm đội không gian Terran là quân đội của các thế giới Terran. Maxwell từng phục vụ trong đó trước khi game bắt đầu, và phần lớn công việc trong chiến dịch của anh đến từ các sĩ quan của hạm đội hoặc người thân cận với họ.", false],
		[1, "", "Tiêm kích tiêu chuẩn của hạm đội là [[ship/6]]. Các sĩ quan trong câu chuyện gồm [[character/1]], người cho Maxwell xem con tàu mới, và [[character/11|Đô đốc Smith]], người đã tặng nó cho anh.", false],
		[5, "", "Hạm đội cũng có điệp viên. Trung úy Hammond hoạt động bí mật trên [[station/2]] theo lệnh của đô đốc.", false],
		[6, "", "Sĩ quan an ninh [[character/7]] truy lùng những kẻ phản bội trong hạm đội.", false],
		[12, "", "Không phải chỉ huy nào cũng trung thành: một trong số họ đã sau lưng hạm đội giao dịch với người Vossk và bọn ngoài vòng pháp luật.", false],
	],
	"world/outlaws": [
		[9, "", "Bọn ngoài vòng pháp luật lái những con tàu Terran đã được cải tạo và tấn công các đoàn tàu. Khi chúng phục kích một đoàn tàu Grey sâu trong lãnh thổ Vossk, rõ ràng chúng đang hợp tác với người Vossk.", false],
		[12, "", "Bọn ngoài vòng pháp luật có kẻ cầm đầu ngay trong hạm đội không gian, kẻ đã bán bí mật quân sự bị đánh cắp cho người Vossk và che đậy các vụ tấn công tàu vận tải. Chúng cố thủ trong một trạm riêng sau một bãi mìn.", false],
		[1, "", "Bọn ngoài vòng pháp luật cũng có dân tộc riêng trên bản đồ thiên hà: những nơi có cư dân [[race/9]] là trạm và hành tinh của chúng. Chỉ cửa hàng của chúng bán [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell tới [[station/0]] và được Trung úy [[character/1]] đón tiếp; cô có lệnh của Đô đốc Smith cho anh xem con tàu mới, một chiếc tàu trinh sát [[ship/0]] cũ. Cô giải thích về nhà chứa: tàu, vũ khí và trang bị được mua trong cửa hàng, còn hàng hóa thu được ngoài không gian được bán từ khoang hàng.", false],
		[1, "", "Tiếp theo là chuyến bay thử. Christine dẫn anh qua các điểm dẫn đường, giải thích khiên, đổi vũ khí, khai hỏa và tăng tốc, rồi cuối cùng thả vài máy bay không người lái huấn luyện để bắn hạ.", false],
		[2, "Kết cục", "Maxwell tiêu diệt các máy bay không người lái và quay về trạm. Christine chúc anh may mắn và mong gặp lại anh lành lặn.", false],
	],
	"chapter/2": [
		[2, "", "Một gương mặt không mong đợi từ hạm đội: chỉ huy [[character/2]], người Maxwell chưa bao giờ ưa nổi, có việc cho anh. Một hành lang không gian gần trạm phải được dọn sạch xác tàu trước khi đoàn tàu tiếp theo tới, và chỉ có hai phút để làm việc đó.", false],
		[3, "Kết cục", "Hành lang được dọn kịp lúc và Vlad trả tiền, kèm lời nhận xét rằng Maxwell sinh ra để làm việc này.", false],
	],
	"chapter/3": [
		[3, "", "Một khách hàng nhỏ bé hay lo, [[character/3]], muốn được đưa ngay tới [[station/1]] trước khi một thương vụ của ông đổ bể. Nơi đó đầy người Vossk, nhưng ông trả hậu và Maxwell nhận lời.", false],
		[4, "Kết cục", "Trên đường đi, một đội tuần tra Vossk yêu cầu họ đầu hàng. Maxwell đưa Bolar tới nơi, và hành khách hứa sẽ giới thiệu anh ngay khi hết run.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] cần hộ tống tàu của ông tới [[station/2]], sào huyệt của cướp biển. Maxwell nâng giá vì rủi ro và nghi ngờ hàng hóa lại là một chuyến vũ khí cho bọn ngoài vòng pháp luật.", false],
		[5, "Kết cục", "Tiêm kích Vossk tấn công tàu chở hàng hai lần. Nó tới được Tortuga, và Doc nói rõ rằng thứ nó chở không phải việc của Maxwell.", false],
	],
	"chapter/5": [
		[5, "", "Trên Tortuga, Maxwell tình cờ gặp [[character/1]], người đang hoạt động bí mật ở đó. Hạm đội được lệnh chặn một đoàn tàu vũ khí Vossk gần [[station/3]]; nếu chuyến hàng lọt qua, sẽ có một cuộc thảm sát. Phi đội của cô cần thêm một phi công giàu kinh nghiệm.", false],
		[6, "Kết cục", "Đội hộ tống bị hạ trước, rồi đến các tàu chở hàng. Đoàn tàu bị chặn đứng, và Christine tin rằng Đô đốc Smith sẽ hài lòng.", false],
	],
	"chapter/6": [
		[6, "", "Sĩ quan an ninh [[character/7]] có một nhiệm vụ không được phép thất bại: [[character/8]], một gián điệp, đã bỏ trốn cùng một trong những con tàu bí mật của hạm đội. Nó không được rơi vào tay kẻ thù và, nếu cần, phải bị phá hủy.", false],
		[7, "Kết cục", "Maxwell tìm thấy Lockwood trong một vành đai tiểu hành tinh và bắn hỏng tàu của hắn cho tới khi hắn đầu hàng. Trước khi ai kịp bắt hắn, [[character/2|Vlad Borsikov]] bắn hạ hắn và nhắc Maxwell rằng mệnh lệnh là phá hủy con tàu. Maxwell bắt đầu nghi rằng chuyện này chưa bao giờ chỉ là một con tàu.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] nhờ hộ tống các tàu của ông tới [[station/4]]. Maxwell nhận ra băng Octopod, vốn nổi tiếng chở đầy hàng ăn cắp, nhưng vẫn nhận việc miễn là nhà chức trách không dính vào.", false],
		[8, "Kết cục", "Thứ tưởng là tiền dễ kiếm biến thành trận chiến với tiêm kích Vossk và một tuần dương hạm. Ít nhất một con tàu lọt qua, và Maxwell nhận thấy người Vossk ngày càng hung hăng.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] đã định vị một tuần dương hạm Vossk bị tê liệt. Hạm đội muốn chiếm nó và bắt sống chỉ huy của nó, nhưng trước hết mọi khẩu pháo cố định trên thân tàu phải bị phá hủy.", false],
		[9, "Kết cục", "Trong khi phi đội của Christine thu hút hỏa lực, Maxwell hạ các khẩu pháo, và con tàu bị đổ bộ.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]] của người Grey thuê Maxwell đưa một đoàn bốn tàu tới [[station/5]], băng thẳng qua lãnh thổ Vossk, và trả tiền cho mỗi con tàu tới nơi.", false],
		[10, "Kết cục", "Kẻ tấn công không phải người Vossk mà là những con tàu Terran đã được cải tạo. Maxwell đẩy lùi chúng và kết luận rằng bọn ngoài vòng pháp luật đang hợp tác với người Vossk.", false],
	],
	"chapter/10": [
		[10, "", "[[character/11]] cần mọi phi công sẵn có: một trạm của đồng minh người Terran, người Nivelian, đang bị lực lượng Vossk hùng hậu tấn công. Sau một cuộc đôi co gay gắt về giá cả và lòng trung thành của Maxwell, đô đốc phái anh đi.", false],
		[11, "Kết cục", "Chỉ huy trạm [[character/12]] đề nghị Maxwell tập trung vào các tuần dương hạm trong khi [[character/1|Christine]] lo các tiêm kích. Cuộc tấn công bị đẩy lùi, và cả hai đồng ý rằng bọn ngoài vòng pháp luật là mối nguy còn lại.", false],
	],
	"chapter/11": [
		[11, "", "Một tộc trưởng Vossk, [[character/4]], bí mật liên lạc với Maxwell. Một trong các chỉ huy Vossk đang âm mưu với một sĩ quan Terran và bọn ngoài vòng pháp luật, và gia tộc muốn hắn chết. Nơi tốt nhất để phục kích là Tinh vân Yarapu.", false],
		[12, "Kết cục", "Maxwell phá hủy tuần dương hạm của tên chỉ huy và đội hộ tống. Nartok cho anh biết kẻ phản bội bên phía Terran là người quen cũ của anh, và Trung úy Hammond đã lần theo dấu hắn.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] mang tin tới: [[character/2]] là kẻ cầm đầu bọn ngoài vòng pháp luật. Với tư cách chỉ huy, hắn đã che đậy các vụ tấn công tàu vận tải và sai Lockwood đánh cắp bí mật quân sự để bán cho người Vossk. Băng của hắn cố thủ trong một trạm ngoài vòng pháp luật được bảo vệ bởi bãi mìn, thứ Maxwell phải dọn sạch trước cuộc tấn công.", false],
		[13, "Kết cục", "Bãi mìn được dọn sạch và lực lượng phòng thủ của trạm gục ngã. Christine lao vào Vlad, kẻ bắn hạ cô trước khi Maxwell kịp yểm trợ, rồi tẩu thoát.", false],
	],
	"chapter/13": [
		[13, "", "[[character/11]] bày tỏ lời chia buồn; Maxwell chỉ muốn biết Vlad đã đi đâu. Hạm đội đã tìm ra Vlad cùng tàn dư bọn ngoài vòng pháp luật, và các phi đội cần Maxwell giúp đập tan chúng.", false],
		[14, "Kết cục", "Khi bọn ngoài vòng pháp luật đã tan rã, Maxwell để hạm đội lo phần việc của mình, một mình truy đuổi Vlad và giết hắn. Đô đốc mời anh một vị trí trong hạm đội; Maxwell từ chối. Anh nhận được động cơ siêu không gian, mở ra mọi góc phần tư của thiên hà.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell là phi công của người chơi: một cựu phi công hạm đội không gian Terran, sau khi giải ngũ trong danh dự đã nhận một con tàu từ [[character/11|Đô đốc Smith]] và bắt đầu cuộc đời lính đánh thuê tại [[station/0]].", false],
		[1, "", "Anh hay mỉa mai và nhanh nhảu mặc cả thù lao, nhưng luôn hoàn thành những việc đã nhận.", false],
		[7, "", "Anh phản đối khi [[character/2|Vlad Borsikov]] bắn hạ một người đã đầu hàng.", false],
		[13, "", "Cái chết của [[character/1|Christine Hammond]] biến chương cuối thành chuyện riêng của anh.", false],
		[14, "", "Sau khi giết Vlad, anh từ chối quay lại hạm đội và thích tự chọn con đường của mình trong thiên hà.", false],
	],
	"character/1": [
		[1, "", "Trung úy Christine Hammond của hạm đội không gian Terran đón Maxwell tại [[station/0]], cho anh xem tàu và bay chuyến bay thử đầu tiên cùng anh. Cô bảo anh cứ gọi cô là Christine.", false],
		[5, "", "Cô cũng là một điệp viên: trên [[station/2]] cô hoạt động bí mật theo lệnh Đô đốc Smith, và cô kéo Maxwell vào cuộc tấn công đoàn tàu vũ khí Vossk.", false],
		[8, "", "Cô chỉ huy phi đội chiếm một tuần dương hạm Vossk bị tê liệt.", false],
		[12, "", "Cô phát hiện [[character/2|Vlad Borsikov]] đứng sau bọn ngoài vòng pháp luật và lên kế hoạch tấn công trạm của chúng.", false],
		[13, "", "Cô lao vào Vlad sau trận chiến và bị hắn bắn hạ. Cái chết của cô khiến Maxwell truy đuổi Vlad ở chương cuối.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov là một chỉ huy của hạm đội không gian Terran và, theo lời Maxwell, là gã tồi tệ nhất trong đó. Hắn giao cho Maxwell công việc có lương đầu tiên: dọn xác tàu khỏi một hành lang không gian trong thời gian giới hạn.", false],
		[7, "", "Hắn bắn hạ gián điệp Corsair Lockwood sau khi người này đã đầu hàng, và khăng khăng rằng mệnh lệnh là phá hủy con tàu.", false],
		[12, "", "Hắn chính là kẻ phản bội: kẻ cầm đầu bọn ngoài vòng pháp luật, dùng cấp bậc để che đậy các vụ tấn công tàu vận tải và sai Lockwood đánh cắp bí mật quân sự rồi bán cho người Vossk.", false],
		[13, "", "Khi Christine Hammond đuổi theo hắn sau cuộc tấn công trạm, hắn bắn hạ cô và tẩu thoát.", false],
		[14, "", "Hạm đội tìm thấy hắn cùng tàn dư bọn ngoài vòng pháp luật, và Maxwell giết hắn trong một trận đấu tay đôi.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon là một khách hàng bồn chồn cần tới [[station/1]] ngay để cứu một thương vụ, và trả hậu cho phi công dám đưa ông băng qua không gian Vossk.", false],
		[4, "", "Ông sống sót qua trận phục kích của người Vossk và hứa sẽ giới thiệu Maxwell.", false],
	],
	"character/4": [
		[4, "", "Một người Vossk mang gương mặt này gọi Maxwell trên đường tới Phoebos và đòi anh đầu hàng nhân danh Đế chế Vossk.", false],
		[11, "", "Nartok Brek là một tộc trưởng của [[race/1]]. Ông bí mật liên lạc với Maxwell vì một chỉ huy dưới quyền đang âm mưu với một sĩ quan Terran và bọn ngoài vòng pháp luật, và nhờ phục kích kẻ phản bội trong Tinh vân Yarapu. Ông đòi Maxwell hứa danh dự trước khi nói bất cứ điều gì.", false],
		[12, "", "Sau trận phục kích, ông cho Maxwell biết kẻ phản bội người Terran là người quen cũ của anh.", false],
	],
	"character/5": [
		[4, "", "John Washington, được bạn bè gọi là Doc, cần hộ tống tàu của ông tới [[station/2]]. Ông đề nghị 3.000 tín dụng và chấp nhận 4.500, với điều kiện không có nhân chứng. Maxwell nghi đó là một chuyến vũ khí cho bọn ngoài vòng pháp luật.", false],
		[5, "", "Hàng của ông tới nơi. Đó là gì, ông giữ cho riêng mình.", false],
	],
	"character/6": [
		[6, "", "Một phi công trong phi đội của Christine Hammond, người hỏi qua vô tuyến liệu gã Maxwell này đã từng chiến đấu chưa, mà không nhận ra anh đang nghe thấy.", false],
		[13, "", "Cũng phi đội đó ở lại bảo vệ trạm của bọn ngoài vòng pháp luật trong khi Christine và Maxwell truy đuổi Vlad.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom là sĩ quan an ninh của hạm đội không gian. Ông phái Maxwell truy đuổi gián điệp [[character/8]], với mệnh lệnh không để con tàu bị đánh cắp rơi vào tay kẻ thù.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood là một gián điệp đã bỏ trốn cùng một trong những con tàu bí mật của hạm đội không gian.", false],
		[7, "", "Bị dồn vào đường cùng trong vành đai tiểu hành tinh, hắn đầu hàng, nhưng vẫn bị Vlad Borsikov bắn hạ.", false],
		[12, "", "Về sau mới lộ ra chính Vlad là người đã giao cho hắn đánh cắp bí mật quân sự ngay từ đầu.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt chở hàng cho băng Octopod, vốn nổi tiếng vận chuyển hàng ăn cắp. Ông khăng khăng mọi thứ trên tàu đều hoàn toàn hợp pháp và trả tiền cho Maxwell để đưa các tàu của ông tới [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor của người Grey đã nghe danh Maxwell và đề nghị anh một công việc khó: đưa bốn con tàu tới [[station/5]] băng qua lãnh thổ Vossk, 4.000 tín dụng cho mỗi tàu tới nơi.", false],
	],
	"character/11": [
		[1, "", "Đô đốc Smith của hạm đội không gian Terran đã tặng Maxwell con tàu sau khi anh giải ngũ, và giao cho Trung úy Hammond hướng dẫn anh cách sử dụng.", false],
		[10, "", "Ông gọi Maxwell khi trạm Nivelian bị tấn công. Cuộc trò chuyện trở nên gay gắt khi Maxwell nói về giá của mình và về số tiền người Vossk có thể trả.", false],
		[13, "", "Sau cái chết của Christine, ông chia buồn với Maxwell và cho anh biết nơi ẩn náu của bọn ngoài vòng pháp luật của Vlad.", false],
		[14, "", "Ông để Maxwell một mình truy đuổi Vlad, mời anh một vị trí trong hạm đội và tặng anh động cơ siêu không gian khi anh từ chối.", false],
	],
	"character/12": [
		[11, "", "Botom Krant chỉ huy trạm Nivelian bị người Vossk tấn công. Ông đề nghị Maxwell tập trung vào các tuần dương hạm và cảm ơn anh khi cuộc tấn công bị đẩy lùi.", false],
	],
	"race/0": [
		[1, "", "Loài người, đang chiến tranh với [[race/1]] vào thiên niên kỷ thứ tư. Maxwell là người Terran, và hầu hết khách hàng trong chiến dịch phục vụ hạm đội không gian Terran. Người Terran sở hữu nhiều hành tinh và trạm hơn bất kỳ dân tộc nào khác.", false],
		[1, "", "Nhiều con tàu được bán là thiết kế của Terran: [[ship/0]], [[ship/6]] cùng phiên bản cải tạo [[ship/7]], và pháo hạm [[ship/4]].", false],
	],
	"race/1": [
		[1, "", "Kẻ thù của người Terran. Cửa hàng Vossk chỉ bán tiêm kích của chính họ, [[ship/8]], và chỉ họ bán vũ khí Vossk. Phi công làm việc cho người Terran bị đòi hối lộ tại các trạm Vossk, và ngược lại.", false],
	],
	"race/2": [
		[1, "", "Một trong các dân tộc của thiên hà, có hành tinh và trạm riêng.", false],
	],
	"race/3": [
		[1, "", "Một trong các dân tộc của thiên hà, có hành tinh và trạm riêng.", false],
	],
	"race/4": [
		[1, "", "Linh kiện đặc biệt của họ được dùng trong các vũ khí như [[equipment/23]], và máy bay ném bom hạng nặng [[ship/3]] là của họ.", false],
	],
	"race/5": [
		[1, "", "Tàu Grey nổi tiếng với lớp giáp cực kỳ dày. Tàu trinh sát [[ship/9]] xuất xứ từ hạm đội của họ và mới được cải tạo cho phi công dạng người gần đây, còn tên lửa [[equipment/4]] được chế tạo từ linh kiện Grey. Feknor của người Grey thuê Maxwell cho một đoàn tàu nguy hiểm.", false],
	],
	"race/6": [
		[1, "", "Đồng minh của người Terran. Tiêm kích [[ship/1]] là sản phẩm phát triển của Nivelian, và laser [[equipment/2]] dựa trên công nghệ vũ khí Nivelian. Cuộc tấn công của Vossk vào một trạm của họ kéo Maxwell thực sự vào cuộc chiến.", false],
	],
	"race/7": [
		[1, "", "Một trong các dân tộc của thiên hà, có hành tinh và trạm riêng.", false],
	],
	"race/8": [
		[1, "", "Một trong các dân tộc của thiên hà, có hành tinh và trạm riêng.", false],
	],
	"race/9": [
		[1, "", "Bọn ngoài vòng pháp luật không phải một dân tộc mà là một lối sống: cướp biển và kẻ buôn lậu có hành tinh và trạm riêng. Chỉ cửa hàng của chúng bán [[ship/7]], và [[station/2]] là sào huyệt nổi tiếng nhất của chúng.", false],
	],
	"galaxy": [
		[1, "", "Bốn góc phần tư, một trăm hệ sao và năm trăm hành tinh và trạm. Mỗi góc phần tư khó hơn góc trước: công việc trả nhiều hơn, kẻ địch cứng hơn và cửa hàng bán trang bị tốt hơn.", false],
		[1, "", "Bay trong một góc phần tư tốn tín dụng theo khoảng cách; chuyển sang góc phần tư kế bên hoặc đối diện tốn thêm phí. Khi bạn đã ghé thăm mọi nơi trong thiên hà, di chuyển là miễn phí.", false],
	],
	"progress/ranks": [
		[1, "Danh tiếng", "Danh tiếng đếm số kẻ địch bạn đã tiêu diệt. Mỗi ngưỡng trong bảng dưới đây nâng cấp bậc của bạn, hiển thị trên màn hình \"Status\".", false],
		[1, "Cấp độ", "Cấp độ của bạn tăng theo số tiền kiếm được từ nhiệm vụ và công việc. Mỗi khi tổng thu nhập vượt quá 1,6 lần mức ở cấp trước, bạn lên cấp tiếp theo. Cấp độ cao hơn khiến kẻ địch trong nhiệm vụ của bạn cứng hơn.", false],
	],
	"progress/milestones": [
		[1, "", "Khi bạn cập trạm, trạm chào đón bạn bằng một thông điệp vào lần đầu tín dụng của bạn vượt một cột mốc hoặc hành trình khám phá thiên hà đạt mức mới. Các thông điệp dưới đây là của chính game.", false],
		[1, "Giàu có", "Giàu có không chỉ là một con số. Với hơn 999.999 tín dụng, bạn có thể buôn bán ở mọi hành tinh và trạm: nhà chứa mở cả ở nơi không có buôn bán, và ở đó bạn có thể mua, bán hàng hóa và chiến lợi phẩm, và trang bị lại tàu.", false],
		[1, "Khám phá", "Mỗi nơi bạn ghé thăm đều được tính. Ghé thăm đủ năm trăm nơi khiến mọi chuyến đi đều miễn phí.", false],
	],
	"progress/loyalty": [
		[1, "", "Lòng trung thành của bạn nằm đâu đó giữa Terran và Vossk, được chỉ bởi con trỏ trên màn hình \"Status\". Mỗi nhiệm vụ cho khách hàng Terran đẩy nó một bước về phía Terran; mỗi nhiệm vụ cho khách hàng Vossk đẩy một bước về phía Vossk. Nó không thể vượt quá mười bước về bất kỳ phía nào.", false],
		[1, "", "Khi bạn tới một nơi của Terran trong lúc lòng trung thành nghiêng về Vossk, hoặc tới một nơi của Vossk khi nó nghiêng về Terran, bạn bị đòi tiền hối lộ ngoài chi phí bay: 150 tín dụng cho mỗi bước. Trả hối lộ đưa lòng trung thành lùi một bước về giữa.", false],
	],
	"mode/survival": [
		[1, "", "Sinh tồn là một chế độ riêng với phi công và bảng điểm cao riêng. Chọn nó trong \"Start Game\". Tàu địch liên tục kéo tới, mỗi lần hạ địch cho điểm và sửa thân tàu, và màu khung đánh dấu kẻ địch cho biết nó mạnh đến đâu. Điểm số mang lại cho bạn một cấp bậc trong bảng dưới đây.", false],
	],
	"mode/swarm": [
		[1, "", "Bầy đàn là chế độ được viết cho bản làm lại này, nằm trong \"Start Game\". Nó mở đầu với một nhúm tiêm kích và lớn dần thành một đám đông khép lại từ mọi phía, với các đợt tràn tới sau phút thứ năm.", false],
		[1, "", "Mỗi lần hạ địch làm đầy thanh cấp độ. Mỗi cấp mang tới ba thẻ nâng cấp: một vũ khí mới, phiên bản tốt hơn của vũ khí đang mang, thêm một nòng, tầm bắn hoặc tốc độ đạn lớn hơn, khiên mạnh hơn, sửa chữa sau mỗi lần hạ địch, hoặc một thân tàu khác. Từ chối một thẻ sẽ sửa một phần tư thân tàu thay vào đó.", false],
		[1, "", "Vũ khí, khiên và thân tàu là những thứ trong tệp game của bạn. Đạt một cấp bậc trên bảng điểm Sinh tồn mở khóa thân tàu tiếp theo cho Bầy đàn.", false],
	],
	"guide/start": [
		[1, "", "Sau khi nhập tệp game, \"Start Game\" mang tới chiến dịch, khám phá tự do, Sinh tồn và Bầy đàn. Chiến dịch bắt đầu tại [[station/0]] với một chiếc [[ship/0]] và 5.000 tín dụng.", false],
		[1, "Menu trạm", "Tại trạm, \"Info\" mô tả nơi đó, \"Hangar\" mở cửa hàng và tàu của bạn, \"Missions\" hiển thị bảng công việc và \"Map\" cho phép bạn di chuyển. Trong chiến dịch, bảng công việc và bản đồ bị khóa, và \"Go on\" bắt đầu buổi chỉ thị tiếp theo. \"Status\" hiển thị cấp độ, danh tiếng, thời gian chơi, số địch đã hạ và lòng trung thành, còn \"Menu\" chứa các tùy chọn và chức năng lưu.", false],
		[1, "", "Không phải nơi nào cũng có nhà chứa mở cho mọi người: không có buôn bán thì nhà chứa chỉ mở trong chiến dịch hoặc khi bạn có hơn 999.999 tín dụng.", false],
	],
	"guide/flight": [
		[1, "", "Điểm dẫn đường được đánh dấu màu vàng, đồng minh màu xanh lá và kẻ địch màu đỏ. Vật thể ngoài tầm nhìn được hiển thị ở mép màn hình. Sức mạnh còn lại của kẻ địch hiển thị bên dưới dấu của nó.", false],
		[1, "", "Khiên hấp thụ va chạm và đòn bắn trúng rồi hồi lại theo thời gian; khi cạn, sát thương đi vào thân tàu. Tăng tốc cho một cú bứt tốc ngắn và cần thời gian để nạp lại.", false],
		[1, "Điều khiển", "Với bàn phím, lái bằng chuột hoặc phím mũi tên, chỉnh lực đẩy bằng W và S và dạt ngang bằng A và D. Bắn bằng cú nhấp hoặc phím Cách, đổi vũ khí bằng Q, phóng tên lửa bằng F và tăng tốc bằng Shift. R bật lái tự động, T tăng tốc thời gian ở đoạn an toàn, E cập trạm khi ở gần và Esc tạm dừng. Tay cầm ngắm bằng cần phải và bắn bằng cò phải. Điều khiển cảm ứng có cần lái, cần ga và các nút bắn, tên lửa, tăng tốc và điều hướng; chạm hai lần vào nút Bắn để bật bắn tự động.", false],
		[1, "Lái tự động và thời gian", "Lái tự động bay tới điểm dẫn đường tiếp theo hoặc tới trạm. Khi không có gì đe dọa bạn, thời gian có thể chạy nhanh hơn; kẻ địch, sát thương hoặc việc tới đích sẽ đưa nó về bình thường.", false],
	],
	"guide/weapons": [
		[1, "", "Tàu có giá gắn cho năm loại vũ khí: laser, pháo plasma, pháo photon, tên lửa và pháo nhiệt. Mỗi giá gắn một vũ khí, và mỗi tàu có bộ giá gắn riêng. Máy tạo khiên lắp được cho mọi tàu.", false],
		[1, "", "Laser và pháo plasma bắn nhanh ở tầm trung. Pháo photon bắn xa nhất và mạnh nhất mỗi phát nhưng nạp chậm. Pháo nhiệt phun hạt ở cự ly gần với tốc độ bắn rất cao. Tên lửa được phóng bằng nút riêng, không cần đổi vũ khí, gây sát thương nặng với thời gian nạp lâu.", false],
		[1, "", "Các loại khiên khác nhau về dung lượng và tốc độ hồi. Vũ khí mạnh nhất chỉ được bán từ góc phần tư thứ hai trở đi, còn vũ khí Vossk chỉ có ở cửa hàng Vossk.", false],
	],
	"guide/hangar": [
		[1, "", "Nhà chứa có ba phần: \"Ship\" hiển thị tàu của bạn cùng vũ khí đã lắp và khiên, \"Cargo\" chứa hàng hóa và trang bị dự phòng, còn \"Shop\" bày hàng của trạm.", false],
		[1, "", "Trang bị đã mua được đưa vào khoang hàng; hãy lắp từ đó nếu tàu còn giá gắn trống cho nó. Trang bị và tàu được bán lại với nửa giá.", false],
		[1, "", "Mua tàu nghĩa là đổi tàu hiện tại. Trang bị hợp với tàu mới vẫn được lắp, phần còn lại chuyển vào khoang hàng nếu còn chỗ.", false],
		[1, "", "Cửa hàng bán từ một tới bốn vũ khí hoặc khiên và tối đa ba con tàu, chọn trong số những gì góc phần tư và dân tộc của nơi đó cho phép. Hàng của cửa hàng được làm mới khi bạn quay lại sau khi bay tới nơi khác. Trong chiến dịch, mỗi chương có lượng hàng cố định riêng.", false],
	],
	"guide/trade": [
		[1, "", "Hàng hóa đến từ xác tàu bị phá hủy và được thu vào khoang hàng sau nhiệm vụ. Hãy bán chúng trong phần hàng hóa của nhà chứa. Có loại được giá nhất ở nơi công nghệ thấp, có loại ở nơi công nghệ cao, có loại giá như nhau ở mọi nơi; trang của mỗi loại hàng liệt kê giá ở mọi trình độ công nghệ.", false],
		[1, "", "Cửa hàng không có hàng hóa của riêng mình. Thứ bạn bán ở một cửa hàng sẽ nằm lại trong kho của nó, và bạn có thể mua lại ở đó với cùng giá.", false],
		[1, "", "Buôn bán cần có nhà chứa: hành tinh và trạm không có buôn bán chỉ mở nhà chứa cho phi công có hơn 999.999 tín dụng.", false],
	],
	"guide/travel": [
		[1, "", "Bản đồ hiển thị thiên hà cùng các góc phần tư và hệ sao. Chọn một nơi và bay tới đó với chi phí hiển thị, cộng tiền hối lộ nếu lòng trung thành của bạn chống lại dân tộc ở đó. Bạn tới nơi trong trạng thái đã cập trạm.", false],
		[1, "", "Chi phí bay tăng theo khoảng cách. Đổi góc phần tư cộng thêm 15.000 tín dụng, và 30.000 cho góc phần tư đối diện. Bản đồ cho biết bạn đã khám phá bao nhiêu phần thiên hà; khi đã ghé thăm mọi nơi, di chuyển không tốn gì.", false],
		[1, "", "Thiên hà mở ra khi chiến dịch hoàn tất hoặc khi bạn bỏ qua nó.", false],
	],
	"guide/jobs": [
		[1, "", "Ngoài chiến dịch, bảng công việc ở mỗi trạm đưa ra vài công việc từ khách hàng thuộc các dân tộc khác nhau. Mỗi việc hiển thị độ khó và phần thưởng; việc khó trả nhiều hơn, các góc phần tư xa hơn cũng vậy.", false],
		[1, "", "Thỉnh thoảng một tay lừa đảo mờ ám đưa ra công việc trả cao hơn bốn mươi phần trăm so với thường lệ. Công việc hoàn thành trả phần thưởng và đẩy lòng trung thành của bạn về phía dân tộc của khách hàng.", false],
	],
	"guide/campaign": [
		[1, "", "Chiến dịch là một mạch gồm mười ba nhiệm vụ. Nhiệm vụ hoàn thành trả phần thưởng; nhiệm vụ thất bại có thể chơi lại. Khi hoàn tất, động cơ siêu không gian mở ra thiên hà, và bảng công việc cùng bản đồ trở nên khả dụng.", false],
		[1, "", "\"Bỏ qua chiến dịch · Khám phá\" ở menu bắt đầu hoặc menu trạm đưa bạn thẳng vào khám phá tự do. Bỏ qua không mang lại phần thưởng hoàn thành và giữ phi công chiến dịch trong ô lưu riêng.", false],
	],
	"guide/saves": [
		[1, "", "Game tự động lưu sau mỗi nhiệm vụ và tại các điểm kiểm tra. Chiến dịch, khám phá, Sinh tồn và Bầy đàn có bản lưu riêng. \"Tải / khôi phục\" trong menu tạm dừng, hoặc \"Load\" sau khi thất bại, đưa bạn về bản tự lưu gần nhất, đầu chuyến bay hoặc trạm gần nhất.", false],
		[1, "", "\"Tệp game\" → \"Chuyển bản lưu\" chuyển bản lưu của bạn sang thiết bị khác đã nhập cùng tệp game.", false],
	],
	"guide/tips": [
		[1, "", "Bán hàng thu từ xác tàu trước khi mua trang bị; trên tàu nhỏ, khoang hàng đầy rất nhanh.", true],
		[1, "", "Kiểm tra giá gắn của tàu trước khi mua vũ khí cho nó: vũ khí không có giá gắn phù hợp sẽ nằm trong khoang hàng.", true],
		[1, "", "Giữ hàng cho tới khi cập trạm ở nơi trình độ công nghệ có lợi cho chúng.", true],
		[1, "", "Chỉ bay cho một phe khiến việc ghé trạm của phe kia trở nên đắt đỏ.", true],
		[1, "", "Ghé những nơi mới khi đằng nào cũng phải di chuyển: khám phá cả thiên hà khiến mọi chuyến đi đều miễn phí.", true],
	],
}
