extends RefCounted
## The reference's own writing in Simplified Chinese. Same blocks, chapter
## gates and links as prose/en.gd; see there for the format. The game has no
## Chinese text, so names and the game's own menu labels stay as the game
## shows them.

const PAGES := {
	"home": {"title": "资料库"},
	"world/setting": {"title": "战火中的银河"},
	"world/fleet": {"title": "Terran 太空舰队"},
	"world/outlaws": {"title": "亡命之徒与海盗"},
	"chapter/1": {"title": "新飞船"},
	"chapter/2": {"title": "太空垃圾"},
	"chapter/3": {"title": "前往 Phoebos"},
	"chapter/4": {"title": "Doc 的货物"},
	"chapter/5": {"title": "武器车队"},
	"chapter/6": {"title": "出逃的间谍"},
	"chapter/7": {"title": "敏感货物"},
	"chapter/8": {"title": "登上巨舰"},
	"chapter/9": {"title": "四艘船前往 Opos"},
	"chapter/10": {"title": "Nivelian 前线"},
	"chapter/11": {"title": "星云伏击"},
	"chapter/12": {"title": "亡命之徒的空间站"},
	"chapter/13": {"title": "复仇"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "雇佣兵飞行员"},
	"character/1": {"title": "Christine Hammond", "subtitle": "太空舰队中尉"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "太空舰队指挥官"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "匆忙的乘客"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Vossk 氏族首领", "early_title": "Vossk 飞行员"},
	"character/5": {"title": "John “Doc” Washington", "subtitle": "商人"},
	"character/6": {"title": "中队飞行员", "subtitle": "太空舰队"},
	"character/7": {"title": "Brent Snocom", "subtitle": "安全官"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "在逃间谍"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Octopod 商人"},
	"character/10": {"title": "Feknor", "subtitle": "Grey 族"},
	"character/11": {"title": "Smith 上将", "subtitle": "Terran 太空舰队"},
	"character/12": {"title": "Botom Krant", "subtitle": "Nivelian 空间站指挥官"},
	"progress/ranks": {"title": "声望与等级"},
	"progress/milestones": {"title": "里程碑"},
	"progress/loyalty": {"title": "忠诚与贿赂"},
	"mode/survival": {"title": "生存", "subtitle": "游戏模式"},
	"mode/swarm": {"title": "虫群", "subtitle": "重制版游戏模式"},
	"guide/start": {"title": "入门"},
	"guide/flight": {"title": "飞行与战斗"},
	"guide/weapons": {"title": "武器与护盾"},
	"guide/hangar": {"title": "机库"},
	"guide/trade": {"title": "贸易与战利品"},
	"guide/travel": {"title": "旅行与地图"},
	"guide/jobs": {"title": "任务板"},
	"guide/campaign": {"title": "战役与自由探索"},
	"guide/saves": {"title": "保存与读取"},
	"guide/tips": {"title": "提示"},
}

const BLOCKS := {
	"home": [
		[1, "", "本资料库介绍你自己的 Galaxy on Fire：银河中的每颗行星和每座空间站，商店里的飞船、武器和货物，任务板上的工作，故事中的人物，以及贸易、旅行和声望的规则。名称、描述和对话来自你导入的游戏文件；数值遵循本重制版采用的规则。", false],
		[1, "", "故事页面会随你的战役进度增加。尚未到达的章节和尚未结识的人物不会出现在资料库中，章节的结局也要在你飞完该章后才会显示。", false],
	],
	"intro/world": [
		[1, "", "游戏的背景：Terran 与 Vossk 之间的战争，Keith Maxwell 刚刚离开的太空舰队，以及劫掠双方的亡命之徒。", false],
	],
	"intro/story": [
		[1, "", "战役是一条由十三章组成的单线流程。每章都从空间站上的简报开始，随后在充满无线电通话的飞行中展开。下方的章节一直列到你的飞行员目前到达的位置。", false],
	],
	"intro/characters": [
		[1, "", "在简报和无线电中与 Keith Maxwell 交谈的人物。每幅肖像都取自游戏本身的美术。", false],
	],
	"intro/races": [
		[1, "", "银河的行星和空间站上居住着十个种族。一个地点的居民决定其商店可以出售哪些飞船；对 Terran 和 Vossk 来说，还决定你的忠诚度是否会让你在前往时付出贿赂。", false],
	],
	"intro/galaxy": [
		[1, "", "银河分为四个象限，每个象限有二十五个星系，每个星系有五颗行星或空间站。下方地图显示了全部；战役结束后即可在它们之间旅行，如果跳过战役则立刻开放。", false],
	],
	"intro/stations": [
		[1, "", "全部五百颗行星和空间站。一个地点的科技等级决定其货物价格和飞船折扣；只有开展贸易的地点才有对所有人开放的机库。", false],
	],
	"intro/ships": [
		[1, "", "你可以购买的飞船。它们的区别在于船体、货舱和武器挂点；大多数种族的商店出售除 Vossk 战斗机以外的所有飞船，而 Vossk 战斗机只有 Vossk 出售。", false],
	],
	"intro/equipment": [
		[1, "", "武器和护盾发生器。飞船只有拥有对应类型的挂点才能携带该武器，并且每种武器同时只能装一件。", false],
	],
	"intro/goods": [
		[1, "", "从被摧毁飞船的残骸中找到的货物。每种货物都有自己的规则，决定空间站的科技等级如何影响其价格。", false],
	],
	"intro/jobs": [
		[1, "", "银河开放后任务板上提供的工作类型。报酬取决于任务本身以及你所在的象限。", false],
	],
	"intro/progress": [
		[1, "", "游戏如何衡量你的飞行员：击毁敌人带来声望，收入带来等级，忠诚度介于 Terran 与 Vossk 之间，还有记录你的财富和探索的消息。", false],
	],
	"intro/modes": [
		[1, "", "战役和自由探索之外的其他玩法。", false],
	],
	"intro/guide": [
		[1, "", "玩法指南：飞行、战斗、改装、贸易、旅行和逐步成长。", false],
	],
	"world/setting": [
		[1, "", "在第四个千年，Terran 正与 [[race/1]] 进行一场星际战争。其他种族与他们共享银河：有的与一方结盟，有的同双方做生意，有的则鲜为人知。", false],
		[1, "", "游戏始于 3587 年的 Terran 空间站 [[station/0]]，战列巡洋舰 SS Ulysses 在这里放下了 [[character/0]]。他从太空舰队光荣退役后，从 [[character/11|Smith 上将]] 那里得到了一艘自己的飞船，打算以雇佣兵为生。", false],
		[1, "故事发生地", "整个战役都发生在第一象限 [[quadrant/0]]，[[station/0]] 附近。故事结束后，银河的其余部分才会开放。", false],
		[14, "战后", "亡命之徒的首领已死，船上装了超空间引擎，Maxwell 谢绝了舰队中的职位。银河归他所有：探索、贸易，并为出钱的人而战。", false],
	],
	"world/fleet": [
		[1, "", "Terran 太空舰队是 Terran 世界的军队。Maxwell 在游戏开始前曾在其中服役，他在战役中的大部分工作都来自舰队军官或他们身边的人。", false],
		[1, "", "舰队的标准战斗机是 [[ship/6]]。故事中的军官包括向 Maxwell 展示新飞船的 [[character/1]]，以及把飞船交给他的 [[character/11|Smith 上将]]。", false],
		[5, "", "舰队也派有特工。Hammond 中尉奉上将之命在 [[station/2]] 卧底。", false],
		[6, "", "安全官 [[character/7]] 负责追查舰队内部的叛徒。", false],
		[12, "", "并非所有指挥官都忠诚：其中一人背着舰队与 Vossk 和亡命之徒勾结。", false],
	],
	"world/outlaws": [
		[9, "", "亡命之徒驾驶改装过的 Terran 飞船袭击车队。当他们在 Vossk 领地深处伏击一支 Grey 车队时，他们与 Vossk 勾结一事已昭然若揭。", false],
		[12, "", "亡命之徒在太空舰队内部有一名首领，他把窃取的军事机密卖给 Vossk，并掩盖了对运输船的袭击。他们据守在雷区后方的自家空间站。", false],
		[1, "", "亡命之徒在银河地图上也有自己的“种族”：居民标为 [[race/9]] 的地点就是他们的空间站和行星。只有他们的商店出售 [[ship/7]]。", false],
	],
	"chapter/1": [
		[1, "", "Maxwell 抵达 [[station/0]]，由 [[character/1]] 中尉迎接；她奉 Smith 上将之命向他展示新飞船，一艘老旧的 [[ship/0]] 侦察舰。她讲解了机库：飞船、武器和装备在商店购买，在太空中收集的货物则从货舱出售。", false],
		[1, "", "接着是试飞。Christine 带他穿过导航点，讲解护盾、切换武器、射击和加速，最后放出几架训练无人机让他击落。", false],
		[2, "结局", "Maxwell 摧毁了无人机并返回空间站。Christine 祝他好运，希望下次见到他时他还完好无损。", false],
	],
	"chapter/2": [
		[2, "", "舰队里一张不受欢迎的面孔：Maxwell 一向无法忍受的指挥官 [[character/2]] 给了他一份工作。必须在下一支车队到达前清理空间站附近一条太空走廊中的残骸，而时间只有两分钟。", false],
		[3, "结局", "走廊及时清理完毕，Vlad 付了钱，还说 Maxwell 天生就是干这行的。", false],
	],
	"chapter/3": [
		[3, "", "一位紧张的小个子客户 [[character/3]] 要立即被送往 [[station/1]]，以免一笔生意泡汤。那里遍地都是 Vossk，但他出价很高，Maxwell 答应了。", false],
		[4, "结局", "途中一支 Vossk 巡逻队要求他们投降。Maxwell 把 Bolar 送到了目的地，这位乘客答应等他不再发抖就推荐 Maxwell。", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] 需要有人护送他的飞船前往海盗巢穴 [[station/2]]。Maxwell 因风险抬高了报酬，并怀疑货物又是一批给亡命之徒的武器。", false],
		[5, "结局", "Vossk 战斗机两次袭击货船。货船抵达 Tortuga，Doc 明确表示船上运的是什么与 Maxwell 无关。", false],
	],
	"chapter/5": [
		[5, "", "在 Tortuga，Maxwell 遇到了正在那里卧底的 [[character/1]]。舰队奉命在 [[station/3]] 附近拦截一支 Vossk 武器车队；如果这批货送到，将会发生一场屠杀。她的中队还需要一名经验丰富的飞行员。", false],
		[6, "结局", "护航舰先被击落，接着是货船。车队被截停，Christine 认为 Smith 上将会很满意。", false],
	],
	"chapter/6": [
		[6, "", "安全官 [[character/7]] 有一项不容有失的任务：间谍 [[character/8]] 驾驶舰队的一艘秘密飞船逃走了。那艘船绝不能落入敌手，必要时必须将其摧毁。", false],
		[7, "结局", "Maxwell 在一片小行星带中找到 Lockwood，并打坏他的飞船直到他投降。还没等人把他带走，[[character/2|Vlad Borsikov]] 就将他击落，并提醒 Maxwell 命令是摧毁飞船。Maxwell 开始怀疑这件事从来不只是关于一艘船。", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] 请人护送他的船队前往 [[station/4]]。Maxwell 认出了以满载赃物闻名的 Octopod 帮，但只要官方不插手，他就接下这份活。", false],
		[8, "结局", "本以为是轻松钱，结果却变成了与 Vossk 战斗机和一艘巡洋舰的战斗。至少有一艘船冲了过去，Maxwell 注意到 Vossk 越来越咄咄逼人。", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] 找到了一艘失去动力的 Vossk 战列巡洋舰。舰队想俘获它并活捉其指挥官，但必须先摧毁舰体上的每一门固定炮台。", false],
		[9, "结局", "Christine 的中队吸引火力，Maxwell 摧毁炮台，随后这艘舰被登舰占领。", false],
	],
	"chapter/9": [
		[9, "", "Grey 族的 [[character/10]] 雇用 Maxwell 将一支四艘船的车队直接穿过 Vossk 领地护送到 [[station/5]]，每抵达一艘船就付一份钱。", false],
		[10, "结局", "来袭者并非 Vossk，而是改装过的 Terran 飞船。Maxwell 击退了他们，并断定亡命之徒正与 Vossk 合作。", false],
	],
	"chapter/10": [
		[10, "", "[[character/11]] 需要所有能出动的飞行员：Terran 的盟友 Nivelian 的一座空间站正遭到强大 Vossk 部队的攻击。在就 Maxwell 的价码和立场激烈交锋之后，上将派他出战。", false],
		[11, "结局", "空间站指挥官 [[character/12]] 请 Maxwell 专心对付巡洋舰，由 [[character/1|Christine]] 对付战斗机。进攻被击退，两人都认为剩下的威胁是亡命之徒。", false],
	],
	"chapter/11": [
		[11, "", "一位 Vossk 氏族首领 [[character/4]] 秘密联系 Maxwell。一名 Vossk 指挥官正与一名 Terran 军官和亡命之徒密谋，氏族要他的命。最佳的伏击地点是 Yarapu 星云。", false],
		[12, "结局", "Maxwell 摧毁了那名指挥官的巡洋舰及其护航。Nartok 告诉他，Terran 一方的叛徒是 Maxwell 的老相识，而 Hammond 中尉已经在追查此人。", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] 带来消息：[[character/2]] 就是亡命之徒的首领。他以指挥官身份掩盖了对运输船的袭击，并让 Lockwood 窃取军事机密卖给 Vossk。他的团伙固守在一座由雷区保护的亡命之徒空间站中，Maxwell 必须在进攻前清除雷区。", false],
		[13, "结局", "雷区被清除，空间站的守军相继倒下。Christine 冲向 Vlad，却在 Maxwell 来得及掩护之前被他击落，Vlad 随即逃走。", false],
	],
	"chapter/13": [
		[13, "", "[[character/11]] 表示慰问；Maxwell 只想知道 Vlad 去了哪里。舰队已找到 Vlad 和他残余的亡命之徒，各中队需要 Maxwell 帮忙将其击溃。", false],
		[14, "结局", "亡命之徒被击溃后，Maxwell 把剩下的交给舰队，独自追击 Vlad 并将其击杀。上将邀请他加入舰队；Maxwell 拒绝了。他得到一台超空间引擎，银河的每个象限都向他敞开。", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell 是玩家的飞行员：一名前 Terran 太空舰队飞行员，光荣退役后从 [[character/11|Smith 上将]] 那里得到一艘飞船，在 [[station/0]] 开始了雇佣兵生涯。", false],
		[1, "", "他说话尖刻，谈报酬时总要讨价还价，但接下的活一定会完成。", false],
		[7, "", "当 [[character/2|Vlad Borsikov]] 击落一名已经投降的人时，他提出了抗议。", false],
		[13, "", "[[character/1|Christine Hammond]] 之死让最后一章成了他的私事。", false],
		[14, "", "杀死 Vlad 后，他拒绝重返舰队，宁愿在银河中走自己的路。", false],
	],
	"character/1": [
		[1, "", "Terran 太空舰队的 Christine Hammond 中尉在 [[station/0]] 迎接 Maxwell，向他展示飞船，并陪他完成第一次试飞。她让他直接叫她 Christine。", false],
		[5, "", "她也是一名特工：奉 Smith 上将之命在 [[station/2]] 卧底，并拉 Maxwell 参加了对 Vossk 武器车队的打击。", false],
		[8, "", "她率领中队俘获了一艘失去动力的 Vossk 战列巡洋舰。", false],
		[12, "", "她揭露出 [[character/2|Vlad Borsikov]] 是亡命之徒的幕后主使，并策划了对其空间站的进攻。", false],
		[13, "", "战斗结束后她冲向 Vlad，被他击落。她的死让 Maxwell 在最后一章追杀 Vlad。", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov 是 Terran 太空舰队的一名指挥官，用 Maxwell 的话说，是舰队里最差劲的家伙。他给了 Maxwell 第一份有报酬的工作：限时清理一条太空走廊中的残骸。", false],
		[7, "", "间谍 Corsair Lockwood 投降后，他仍将其击落，并坚称命令是摧毁飞船。", false],
		[12, "", "他就是叛徒：亡命之徒的首领，利用职权掩盖对运输船的袭击，并让 Lockwood 窃取军事机密卖给 Vossk。", false],
		[13, "", "在其空间站遭到进攻后，Christine Hammond 追击他，被他击落，他随即逃走。", false],
		[14, "", "舰队找到了他和他残余的亡命之徒，Maxwell 在一场决斗中杀死了他。", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon 是一位坐立不安的客户，必须立刻赶到 [[station/1]] 挽救一笔生意，并愿意重金酬谢肯带他穿越 Vossk 空域的飞行员。", false],
		[4, "", "他在 Vossk 的伏击中幸存，并答应推荐 Maxwell。", false],
	],
	"character/4": [
		[4, "", "一个长着这张脸的 Vossk 在前往 Phoebos 的途中呼叫 Maxwell，以 Vossk 帝国的名义要求他投降。", false],
		[11, "", "Nartok Brek 是 [[race/1]] 的一位氏族首领。由于他手下的一名指挥官与一名 Terran 军官和亡命之徒密谋，他秘密联系 Maxwell，请他在 Yarapu 星云伏击这名叛徒。在开口之前，他要求 Maxwell 以名誉担保。", false],
		[12, "", "伏击之后，他告诉 Maxwell，那名 Terran 叛徒正是 Maxwell 的旧识。", false],
	],
	"character/5": [
		[4, "", "John Washington，朋友们叫他 Doc，需要有人护送他的飞船前往 [[station/2]]。他开价 3,000 信用点，最后以不留目击者为条件同意了 4,500。Maxwell 怀疑这是给亡命之徒的一批武器。", false],
		[5, "", "他的货物送到了。至于运的是什么，他守口如瓶。", false],
	],
	"character/6": [
		[6, "", "Christine Hammond 中队的一名飞行员，在无线电里问这个 Maxwell 到底有没有实战经验，却没意识到 Maxwell 听得见。", false],
		[13, "", "Christine 和 Maxwell 追击 Vlad 时，同一个中队留下来控制亡命之徒的空间站。", false],
	],
	"character/7": [
		[6, "", "Brent Snocom 是太空舰队的安全官。他派 Maxwell 追捕间谍 [[character/8]]，命令是被盗的飞船绝不能落入敌手。", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood 是一名驾驶太空舰队秘密飞船出逃的间谍。", false],
		[7, "", "他在小行星带中走投无路而投降，但仍被 Vlad Borsikov 击落。", false],
		[12, "", "后来才查明，当初正是 Vlad 派他去窃取军事机密的。", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt 为以运送赃物闻名的 Octopod 帮跑货运。他坚称船上的一切完全合法，并付钱让 Maxwell 把他的船队送到 [[station/4]]。", false],
	],
	"character/10": [
		[9, "", "Grey 族的 Feknor 听说过 Maxwell，给了他一份艰难的工作：穿越 Vossk 领地把四艘船送到 [[station/5]]，每抵达一艘付 4,000 信用点。", false],
	],
	"character/11": [
		[1, "", "Terran 太空舰队的 Smith 上将在 Maxwell 退役后把飞船交给了他，并让 Hammond 中尉教他如何使用。", false],
		[10, "", "Nivelian 空间站遇袭时，他召来了 Maxwell。当 Maxwell 谈起自己的价码以及 Vossk 可能出的价钱时，谈话变得针锋相对。", false],
		[13, "", "Christine 死后，他向 Maxwell 表示慰问，并告诉他 Vlad 一伙亡命之徒的所在。", false],
		[14, "", "他让 Maxwell 独自追击 Vlad，邀请他加入舰队，在被拒绝后送给他一台超空间引擎。", false],
	],
	"character/12": [
		[11, "", "Botom Krant 指挥遭到 Vossk 攻击的 Nivelian 空间站。他请 Maxwell 专心对付巡洋舰，并在击退进攻后向他道谢。", false],
	],
	"race/0": [
		[1, "", "人类，在第四个千年与 [[race/1]] 交战。Maxwell 是 Terran，战役中的大多数客户都在 Terran 太空舰队服役。Terran 拥有的行星和空间站比其他任何种族都多。", false],
		[1, "", "出售的飞船中有许多是 Terran 设计：[[ship/0]]、[[ship/6]] 及其改装型 [[ship/7]]，还有炮艇 [[ship/4]]。", false],
	],
	"race/1": [
		[1, "", "Terran 的敌人。Vossk 商店只出售他们自己的战斗机 [[ship/8]]，也只有他们出售 Vossk 武器。为 Terran 效力的飞行员在 Vossk 空间站会被索要贿赂，反之亦然。", false],
	],
	"race/2": [
		[1, "", "银河中的一个种族，拥有自己的行星和空间站。", false],
	],
	"race/3": [
		[1, "", "银河中的一个种族，拥有自己的行星和空间站。", false],
	],
	"race/4": [
		[1, "", "他们的特殊组件用于 [[equipment/23]] 等武器中，重型轰炸机 [[ship/3]] 也出自他们之手。", false],
	],
	"race/5": [
		[1, "", "Grey 飞船以极其厚重的装甲著称。侦察舰 [[ship/9]] 来自他们的舰队，最近才改装为可供类人飞行员驾驶，导弹 [[equipment/4]] 也采用 Grey 组件制造。Grey 族的 Feknor 雇用 Maxwell 执行一次危险的护航。", false],
	],
	"race/6": [
		[1, "", "Terran 的盟友。战斗机 [[ship/1]] 是 Nivelian 研发的，激光 [[equipment/2]] 也基于 Nivelian 的武器技术。Vossk 对他们一座空间站的攻击让 Maxwell 真正卷入了战争。", false],
	],
	"race/7": [
		[1, "", "银河中的一个种族，拥有自己的行星和空间站。", false],
	],
	"race/8": [
		[1, "", "银河中的一个种族，拥有自己的行星和空间站。", false],
	],
	"race/9": [
		[1, "", "亡命之徒不是一个种族，而是一种活法：拥有自己行星和空间站的海盗与走私者。只有他们的商店出售 [[ship/7]]，[[station/2]] 是他们最有名的巢穴。", false],
	],
	"galaxy": [
		[1, "", "四个象限、一百个星系、五百颗行星和空间站。每个象限都比前一个更难：任务报酬更高，敌人更强，商店出售的装备也更好。", false],
		[1, "", "在同一象限内飞行按距离收取信用点；进入相邻象限或对面象限需额外付费。访问过银河中的每个地点后，旅行便免费。", false],
	],
	"progress/ranks": [
		[1, "声望", "声望统计你摧毁的敌人数量。下表中的每个门槛都会提升你的军衔，显示在“Status”界面上。", false],
		[1, "等级", "你的等级随着从任务和工作中赚到的钱而提升。每当总收入超过上一等级时的 1.6 倍，你就会升到下一级。等级越高，任务中的敌人越强。", false],
	],
	"progress/milestones": [
		[1, "", "停靠时，当你的信用点首次越过某个里程碑，或你对银河的探索达到新的程度，空间站会用一条消息迎接你。下方的消息来自游戏本身。", false],
		[1, "财富", "财富不只是一个数字。拥有超过 999,999 信用点时，你可以在每颗行星和每座空间站进行贸易：即使是没有贸易的地方，机库也会开放，你可以在那里购买、出售货物和战利品，并改装飞船。", false],
		[1, "探索", "每访问一个地点都会计入。访问全部五百个地点后，每次旅行都免费。", false],
	],
	"progress/loyalty": [
		[1, "", "你的忠诚度位于 Terran 和 Vossk 之间，由“Status”界面上的指针显示。为 Terran 客户执行一次任务，忠诚度向 Terran 移动一格；为 Vossk 客户执行一次任务，则向 Vossk 移动一格。任何一侧都不能超过十格。", false],
		[1, "", "当你的忠诚度偏向 Vossk 时前往 Terran 地点，或偏向 Terran 时前往 Vossk 地点，除了飞行费用，还会被索要贿赂：每格 150 信用点。支付贿赂会让忠诚度向中间回移一格。", false],
	],
	"mode/survival": [
		[1, "", "生存是一个独立的模式，有自己的飞行员和高分榜。在“Start Game”中选择。敌舰源源不断，每次击毁都能得分并修复船体，敌人标记框的颜色表示其强弱。你的得分会让你获得下表中的军衔。", false],
	],
	"mode/swarm": [
		[1, "", "虫群是为本重制版编写的模式，位于“Start Game”中。开局只有寥寥几架战斗机，随后壮大成从四面八方合围的大群，第五分钟之后还会出现敌潮。", false],
		[1, "", "每次击毁都会填充等级条。每升一级会提供三张强化卡：新武器、现有武器的强化版、额外炮口、更远射程或更快弹速、更强的护盾、每次击毁时修复，或换一种船体。拒绝选卡则改为修复四分之一船体。", false],
		[1, "", "武器、护盾和船体都来自你的游戏文件。在生存模式排行中达到某个军衔，就会为虫群解锁下一种船体。", false],
	],
	"guide/start": [
		[1, "", "导入游戏文件后，“Start Game”提供战役、自由探索、生存和虫群。战役从 [[station/0]] 开始，你拥有一艘 [[ship/0]] 和 5,000 信用点。", false],
		[1, "空间站菜单", "在空间站中，“Info”介绍当地，“Hangar”打开商店和你的飞船，“Missions”显示任务板，“Map”用于旅行。战役期间任务板和地图保持锁定，“Go on”开始下一段简报。“Status”显示等级、声望、游戏时间、击毁数和忠诚度，“Menu”包含选项和存档。", false],
		[1, "", "并非每个地点都有对所有人开放的机库：没有贸易的地方，机库只在战役期间或你拥有超过 999,999 信用点时开放。", false],
	],
	"guide/flight": [
		[1, "", "导航点标为黄色，友军为绿色，敌人为红色。视野外的物体显示在屏幕边缘。敌人剩余的强度显示在其标记下方。", false],
		[1, "", "护盾会吸收碰撞和命中，并随时间恢复；护盾耗尽后，伤害会作用于船体。加速可带来短暂的速度爆发，之后需要时间充能。", false],
		[1, "操作", "使用键盘时，用鼠标或方向键转向，用 W 和 S 调节推力，用 A 和 D 横移。单击或按空格键射击，按 Q 切换武器，按 F 发射导弹，按 Shift 加速。R 开启自动驾驶，T 在安全路段加速时间，E 在空间站附近停靠，Esc 暂停。手柄用右摇杆瞄准、右扳机射击。触屏操作有摇杆、油门以及射击、导弹、加速和导航按钮；双击射击键可开启自动射击。", false],
		[1, "自动驾驶与时间", "自动驾驶会飞往下一个导航点或空间站。在没有威胁时，时间可以加速；遇到敌人、受到伤害或抵达目的地时会恢复正常。", false],
	],
	"guide/weapons": [
		[1, "", "飞船有五类武器挂点：激光、等离子炮、光子炮、导弹和热能炮。每个挂点装一件武器，每艘飞船都有自己的一套挂点。护盾发生器可装在任何飞船上。", false],
		[1, "", "激光和等离子炮在中距离快速射击。光子炮射程最远、单发威力最大，但装填缓慢。热能炮在近距离以极高射速喷射粒子。导弹用专门的按键发射，无需切换武器，伤害很高但装填时间长。", false],
		[1, "", "护盾在容量和恢复速度上各不相同。最强的武器只在第二象限及更远处出售，Vossk 武器只在 Vossk 商店出售。", false],
	],
	"guide/hangar": [
		[1, "", "机库分为三部分：“Ship”显示你的飞船及其已装备的武器和护盾，“Cargo”存放你的货物和备用装备，“Shop”提供空间站的库存。", false],
		[1, "", "购买的装备会放进货舱；如果飞船有空闲挂点，可以从货舱安装。装备和飞船以半价回售。", false],
		[1, "", "购买飞船会以旧换新。适合新飞船的装备保持安装，其余装备在有空间的情况下移入货舱。", false],
		[1, "", "商店出售一到四件武器或护盾以及最多三艘飞船，从当地象限和种族允许的范围中选取。你去别处飞一趟再回来时，商店库存会刷新。战役期间每章都有各自固定的库存。", false],
	],
	"guide/trade": [
		[1, "", "货物来自被摧毁飞船的残骸，任务结束后收入你的货舱。在机库的货物区出售。有的在科技低的地方最值钱，有的在科技高的地方最值钱，有的到处同价；每种货物的页面都列出了它在各科技等级的价格。", false],
		[1, "", "商店没有自己的货物。你在商店卖出的东西会留在它的库存中，你可以在那里以同样的价格买回。", false],
		[1, "", "贸易需要机库：没有贸易的行星和空间站只向拥有超过 999,999 信用点的飞行员开放机库。", false],
	],
	"guide/travel": [
		[1, "", "地图显示银河及其象限和星系。选择一个地点，支付显示的飞行费用即可前往；如果你的忠诚度与当地种族对立，还要加上贿赂。抵达时你已停靠完毕。", false],
		[1, "", "飞行费用随距离增加。跨象限需额外支付 15,000 信用点，前往对面象限则为 30,000。地图会显示你已探索了银河的多少；访问过所有地点后，旅行不再花钱。", false],
		[1, "", "战役完成或跳过战役后，银河即会开放。", false],
	],
	"guide/jobs": [
		[1, "", "战役之外，每座空间站的任务板会提供几个来自不同种族客户的工作。每个工作都标明难度和报酬；难度越高报酬越多，越远的象限也越多。", false],
		[1, "", "偶尔会有可疑的骗子提供比平常多付百分之四十的工作。完成工作会获得报酬，并使你的忠诚度向客户所属种族移动。", false],
	],
	"guide/campaign": [
		[1, "", "战役由十三个任务依次组成。完成任务获得报酬；失败的任务可以重来。战役完成后，超空间引擎会开放银河，任务板和地图也随之可用。", false],
		[1, "", "开始菜单或空间站菜单中的“跳过战役 · 探索”会直接进入自由探索。跳过不会获得完成奖励，你的战役飞行员会保留在自己的存档位中。", false],
	],
	"guide/saves": [
		[1, "", "游戏会在每次任务后和检查点自动保存。战役、探索、生存和虫群各有独立存档。暂停菜单中的“读取 / 恢复”或失败后的“Load”会回到最近的自动存档、飞行开始处或最近的空间站。", false],
		[1, "", "“游戏文件”→“转移存档”可将你的存档转移到另一台导入了同一游戏文件的设备上。", false],
	],
	"guide/tips": [
		[1, "", "购买装备前先卖掉从残骸中收集的货物；小飞船的货舱很快就会装满。", true],
		[1, "", "为飞船购买武器前先检查挂点：没有对应挂点的武器只能留在货舱里。", true],
		[1, "", "把货物留到停靠在科技等级对其有利的地方再卖。", true],
		[1, "", "只为一方效力会让访问另一方的空间站变得昂贵。", true],
		[1, "", "反正要旅行，不如顺路去新地方：探索整个银河后，每次旅行都免费。", true],
	],
}
