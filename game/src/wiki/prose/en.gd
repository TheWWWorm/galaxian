extends RefCounted
## The reference's own writing in English. A block is [from, heading, text,
## list item]: "from" is the chapter a save must have been offered before the
## block appears (14 means the campaign is complete). [[key]] links a page and
## shows its title from the player's game; [[key|words]] links the words.
## Imported text never appears here.

const PAGES := {
	"home": {"title": "Reference"},
	"world/setting": {"title": "The galaxy at war", "category": "world"},
	"world/fleet": {"title": "The Terran space fleet", "category": "world"},
	"world/outlaws": {"title": "Outlaws and pirates", "category": "world", "from": 9},
	"chapter/1": {"title": "A new ship"},
	"chapter/2": {"title": "Space junk"},
	"chapter/3": {"title": "Passage to Phoebos"},
	"chapter/4": {"title": "Doc's cargo"},
	"chapter/5": {"title": "The weapons convoy"},
	"chapter/6": {"title": "The runaway spy"},
	"chapter/7": {"title": "Sensitive goods"},
	"chapter/8": {"title": "Boarding the giant"},
	"chapter/9": {"title": "Four ships to Opos"},
	"chapter/10": {"title": "The Nivelian front"},
	"chapter/11": {"title": "Ambush in the nebula"},
	"chapter/12": {"title": "The outlaw station"},
	"chapter/13": {"title": "Vengeance"},
	"character/0": {"title": "Keith T. Maxwell", "subtitle": "Mercenary pilot"},
	"character/1": {"title": "Christine Hammond", "subtitle": "Space fleet lieutenant"},
	"character/2": {"title": "Vlad Borsikov", "subtitle": "Space fleet commander"},
	"character/3": {"title": "Bolar Nobloon", "subtitle": "Passenger in a hurry"},
	"character/4": {"title": "Nartok Brek", "subtitle": "Vossk clan head", "early_title": "Vossk pilot", "named_from": 11},
	"character/5": {"title": "John \"Doc\" Washington", "subtitle": "Trader"},
	"character/6": {"title": "Squadron pilot", "subtitle": "Space fleet"},
	"character/7": {"title": "Brent Snocom", "subtitle": "Security officer"},
	"character/8": {"title": "Corsair Lockwood", "subtitle": "Spy on the run"},
	"character/9": {"title": "Mkkt Bkkt", "subtitle": "Octopod trader"},
	"character/10": {"title": "Feknor", "subtitle": "Of the Grey"},
	"character/11": {"title": "Admiral Smith", "subtitle": "Terran space fleet"},
	"character/12": {"title": "Botom Krant", "subtitle": "Nivelian station commander"},
	"progress/ranks": {"title": "Reputation and level", "category": "progress"},
	"progress/milestones": {"title": "Milestones", "category": "progress"},
	"progress/loyalty": {"title": "Loyalty and bribes", "category": "progress"},
	"mode/survival": {"title": "Survival", "category": "modes", "subtitle": "Game mode"},
	"mode/swarm": {"title": "Swarm", "category": "modes", "subtitle": "Remake game mode"},
	"guide/start": {"title": "Getting started", "category": "guide"},
	"guide/flight": {"title": "Flying and fighting", "category": "guide"},
	"guide/weapons": {"title": "Weapons and shields", "category": "guide"},
	"guide/hangar": {"title": "The hangar", "category": "guide"},
	"guide/trade": {"title": "Trading and loot", "category": "guide"},
	"guide/travel": {"title": "Travel and the map", "category": "guide"},
	"guide/jobs": {"title": "The job board", "category": "guide"},
	"guide/campaign": {"title": "Campaign and free exploration", "category": "guide"},
	"guide/saves": {"title": "Saving and loading", "category": "guide"},
	"guide/tips": {"title": "Tips", "category": "guide"},
}

const BLOCKS := {
	"home": [
		[1, "", "This reference describes your own copy of Galaxy on Fire: every planet and station of the galaxy, the ships, weapons and goods in its shops, the jobs on its boards, the people of its story and the rules behind trading, travel and reputation. Names, descriptions and dialogue come from the game file you imported; the figures follow the rules this remake plays by.", false],
		[1, "", "The story pages grow with your campaign. Chapters you have not reached and people you have not met stay out of the reference, and a chapter's outcome appears once you have flown it.", false],
	],
	"intro/world": [
		[1, "", "The setting of the game: the war between the Terrans and the Vossk, the space fleet Keith Maxwell has just left and the outlaws who prey on both sides.", false],
	],
	"intro/story": [
		[1, "", "The campaign is a single line of thirteen chapters. Each begins with a briefing at a station and continues in a flight with radio calls. The chapters below go as far as your pilot has come.", false],
	],
	"intro/characters": [
		[1, "", "The people who speak to Keith Maxwell in briefings and over the radio. Each portrait comes from the game's own art.", false],
	],
	"intro/races": [
		[1, "", "Ten peoples live on the planets and stations of the galaxy. A place's inhabitants decide which ships its shop may sell and, for Terrans and Vossk, whether your loyalty costs you a bribe when you travel there.", false],
	],
	"intro/galaxy": [
		[1, "", "The galaxy is divided into four quadrants of twenty-five systems each, and every system holds five planets or stations. The map below shows all of them; travel between them opens once the campaign is over, or straight away if you skip it.", false],
	],
	"intro/stations": [
		[1, "", "All five hundred planets and stations. A place's technology level sets its cargo prices and its ship discounts; only places with trade have a hangar open to everyone.", false],
	],
	"intro/ships": [
		[1, "", "The ships you can buy. Hull, cargo hold and weapon mounts are what set them apart; the shops of most races sell all but the Vossk fighter, which only the Vossk sell.", false],
	],
	"intro/equipment": [
		[1, "", "Weapons and shield generators. A ship can only carry a weapon if it has a mount for that kind of weapon, and only one weapon of each kind at a time.", false],
	],
	"intro/goods": [
		[1, "", "Cargo found in the wreckage of destroyed ships. Each kind of goods follows its own rule for how a station's technology level changes its price.", false],
	],
	"intro/jobs": [
		[1, "", "The kinds of work offered on the job board once the galaxy is open. Rewards depend on the job and on the quadrant you are in.", false],
	],
	"intro/progress": [
		[1, "", "How the game measures your pilot: reputation from kills, level from earnings, loyalty between the Terrans and the Vossk, and the messages that mark your wealth and exploration.", false],
	],
	"intro/modes": [
		[1, "", "Ways to play besides the campaign and free exploration.", false],
	],
	"intro/guide": [
		[1, "", "How to play: flying, fighting, outfitting, trading, travelling and working your way up.", false],
	],
	"world/setting": [
		[1, "", "In the fourth millennium the Terrans are fighting an interplanetary war against the [[race/1]]. Other peoples share the galaxy with them: some allied with one side, some trading with both, some barely known.", false],
		[1, "", "The game begins in the year 3587 at [[station/0]], a Terran station, where the battle cruiser SS Ulysses delivers [[character/0]]. After an honourable discharge from the space fleet he has been given a ship of his own by [[character/11|Admiral Smith]] and means to earn his living as a mercenary.", false],
		[1, "Where it happens", "The whole campaign takes place in the first quadrant, [[quadrant/0]], close to [[station/0]]. The rest of the galaxy opens once the story is over.", false],
		[14, "After the war", "With the outlaw ringleader dead and a hyperspace drive on board, Maxwell turns down a place in the fleet. The galaxy is his to explore, trade in and fight for whoever pays.", false],
	],
	"world/fleet": [
		[1, "", "The Terran space fleet is the military of the Terran worlds. Maxwell served in it before the game begins, and most of his campaign work comes from its officers or from people around them.", false],
		[1, "", "Its standard fighter is the [[ship/6]]. Its officers in the story include [[character/1]], who shows Maxwell his new ship, and [[character/11|Admiral Smith]], who gave it to him.", false],
		[5, "", "The fleet also runs agents. Lieutenant Hammond works undercover on [[station/2]] on the admiral's orders.", false],
		[6, "", "Security officer [[character/7]] hunts traitors inside the fleet.", false],
		[12, "", "Not all of its commanders are loyal: one of them has been dealing with the Vossk and the outlaws behind the fleet's back.", false],
	],
	"world/outlaws": [
		[9, "", "Outlaws fly modified Terran ships and attack convoys. When they ambush a Grey convoy deep in Vossk territory, it becomes clear that they are working with the Vossk.", false],
		[12, "", "The outlaws have a leader inside the space fleet itself, who sold stolen military secrets to the Vossk and covered the attacks on the transports. They hold out in a station of their own behind a minefield.", false],
		[1, "", "Outlaws also have a people of their own on the galaxy map: places listed as [[race/9]] are their stations and planets. Their shops are the only ones that sell the [[ship/7]].", false],
	],
	"chapter/1": [
		[1, "", "Maxwell arrives at [[station/0]] and is met by Lieutenant [[character/1]], who has orders from Admiral Smith to show him his new ship, an old [[ship/0]] scout. She explains the hangar: ships, weapons and equipment are bought in the shop, and cargo collected in space is sold from the hold.", false],
		[1, "", "Then comes a test flight. Christine leads him through the waypoints, explains shields, weapon switching, firing and the boost, and finally sets up a few training drones to shoot down.", false],
		[2, "Outcome", "Maxwell destroys the drones and returns to the station. Christine wishes him luck and hopes to see him again in one piece.", false],
	],
	"chapter/2": [
		[2, "", "An unwelcome face from the fleet: commander [[character/2]], whom Maxwell has never been able to stand, has a job for him. A space corridor near the station must be cleared of wreckage before the next convoy arrives, and there are only two minutes to do it.", false],
		[3, "Outcome", "The corridor is cleared in time and Vlad pays up, with a remark that Maxwell was made for the job.", false],
	],
	"chapter/3": [
		[3, "", "A nervous little client, [[character/3]], wants to be taken to [[station/1]] at once, before a deal of his falls through. The place is crawling with Vossk, but he offers good money and Maxwell accepts.", false],
		[4, "Outcome", "On the way a Vossk patrol demands their surrender. Maxwell gets Bolar through, and the passenger promises to recommend him once he has stopped shaking.", false],
	],
	"chapter/4": [
		[4, "", "[[character/5]] needs an escort for his ship to [[station/2]], the pirates' hideout. Maxwell bargains the fee up for the risk and suspects the cargo is another weapons delivery for the outlaws.", false],
		[5, "Outcome", "Vossk fighters go after the freighter twice. It reaches Tortuga, and Doc makes it clear that what it carried is none of Maxwell's business.", false],
	],
	"chapter/5": [
		[5, "", "On Tortuga Maxwell runs into [[character/1]], who is there undercover. The fleet has been ordered to intercept a Vossk weapons convoy near [[station/3]]; if the delivery gets through, there will be a massacre. Her flight needs another experienced pilot.", false],
		[6, "Outcome", "The escort falls first, then the freighters. The convoy is stopped, and Christine expects Admiral Smith to be pleased.", false],
	],
	"chapter/6": [
		[6, "", "Security officer [[character/7]] has a job that cannot go wrong: [[character/8]], a spy, has fled with one of the fleet's secret ships. It must not fall into enemy hands, and if need be it is to be destroyed.", false],
		[7, "Outcome", "Maxwell finds Lockwood in an asteroid field and damages his ship until he surrenders. Before anyone can take him in, [[character/2|Vlad Borsikov]] shoots him down and reminds Maxwell that the orders were to destroy the ship. Maxwell begins to suspect that this was never only about a ship.", false],
	],
	"chapter/7": [
		[7, "", "[[character/9]] asks for an escort for his ships to [[station/4]]. Maxwell recognises the Octopod band, known for being stuffed with stolen goods, but takes the job as long as the authorities stay out of it.", false],
		[8, "Outcome", "What starts as easy money turns into a fight with Vossk fighters and a cruiser. At least one ship gets through, and Maxwell notes that the Vossk are growing more aggressive.", false],
	],
	"chapter/8": [
		[8, "", "[[character/1]] has located a disabled Vossk battle cruiser. The fleet wants to capture it and take its commander alive, but first every fixed cannon on its hull must be destroyed.", false],
		[9, "Outcome", "While Christine's squadron draws the fire, Maxwell takes out the cannons, and the ship is boarded.", false],
	],
	"chapter/9": [
		[9, "", "[[character/10]] of the Grey hires Maxwell to bring a convoy of four ships to [[station/5]], straight across Vossk territory, and pays for every ship that arrives.", false],
		[10, "Outcome", "The attackers are not Vossk but modified Terran ships. Maxwell drives them off and concludes that the outlaws are working with the Vossk.", false],
	],
	"chapter/10": [
		[10, "", "[[character/11]] needs every available pilot: a station of the Terrans' allies, the Nivelians, is under attack by strong Vossk forces. After a sharp exchange about Maxwell's prices and loyalties, the admiral sends him in.", false],
		[11, "Outcome", "Station commander [[character/12]] asks Maxwell to concentrate on the cruisers while [[character/1|Christine]] takes the fighters. The attack is beaten off, and the two of them agree that the outlaws are the danger that remains.", false],
	],
	"chapter/11": [
		[11, "", "A Vossk clan head, [[character/4]], contacts Maxwell in secret. One of the Vossk commanders is conspiring with a Terran officer and the outlaws, and the clan wants him dead. The best place for an ambush is the Yarapu Nebula.", false],
		[12, "Outcome", "Maxwell destroys the commander's cruiser and its escort. Nartok tells him that the traitor on the Terran side is an old acquaintance of Maxwell's, and that Lieutenant Hammond is already on his trail.", false],
	],
	"chapter/12": [
		[12, "", "[[character/1]] brings the news: [[character/2]] is the ringleader of the outlaws. As a commander he covered up the attacks on the transports and had Lockwood steal military secrets to sell to the Vossk. His band has barricaded itself in an outlaw station protected by a minefield, which Maxwell must clear before the attack.", false],
		[13, "Outcome", "The minefield is cleared and the station's defenders fall. Christine charges ahead at Vlad, who shoots her down before Maxwell can cover her, and escapes.", false],
	],
	"chapter/13": [
		[13, "", "[[character/11]] offers his sympathy; Maxwell wants only to know where Vlad has gone. The fleet has found Vlad and the last of his outlaws, and its squadrons need Maxwell's help to break them.", false],
		[14, "Outcome", "Once the outlaws are broken, Maxwell leaves the fleet to its work and goes after Vlad alone, and kills him. The admiral offers him a place in the fleet; Maxwell declines. He receives a hyperspace drive, which opens every quadrant of the galaxy.", false],
	],
	"character/0": [
		[1, "", "Keith T. Maxwell is the player's pilot: a former pilot of the Terran space fleet who, after an honourable discharge, receives a ship from [[character/11|Admiral Smith]] and starts a life as a mercenary at [[station/0]].", false],
		[1, "", "He is sarcastic and quick to bargain over his fees, but he finishes the jobs he takes.", false],
		[7, "", "He objects when [[character/2|Vlad Borsikov]] shoots a man who had surrendered.", false],
		[13, "", "The death of [[character/1|Christine Hammond]] turns the last chapter into a personal matter.", false],
		[14, "", "After killing Vlad he declines a return to the fleet and prefers to choose his own way through the galaxy.", false],
	],
	"character/1": [
		[1, "", "Lieutenant Christine Hammond of the Terran space fleet welcomes Maxwell at [[station/0]], shows him his ship and flies his first test flight with him. She asks him to call her Christine.", false],
		[5, "", "She also works as an agent: on [[station/2]] she is undercover on Admiral Smith's orders, and she brings Maxwell into the strike on the Vossk weapons convoy.", false],
		[8, "", "She leads the squadron that captures a disabled Vossk battle cruiser.", false],
		[12, "", "She uncovers that [[character/2|Vlad Borsikov]] is behind the outlaws and plans the attack on their station.", false],
		[13, "", "She charges at Vlad after the battle and is shot down by him. Her death sends Maxwell after Vlad in the last chapter.", false],
	],
	"character/2": [
		[2, "", "Vlad Borsikov is a commander of the Terran space fleet and, in Maxwell's words, the lousiest guy in it. He gives Maxwell his first paid job: clearing a space corridor of wreckage against the clock.", false],
		[7, "", "He shoots down the spy Corsair Lockwood after Lockwood has surrendered, and insists that the orders were to destroy the ship.", false],
		[12, "", "He is the traitor: the ringleader of the outlaws, who used his rank to cover the attacks on the transports and had Lockwood steal military secrets that he sold to the Vossk.", false],
		[13, "", "When Christine Hammond goes after him after the attack on his station, he shoots her down and escapes.", false],
		[14, "", "The fleet finds him with the last of his outlaws, and Maxwell kills him in a duel.", false],
	],
	"character/3": [
		[3, "", "Bolar Nobloon is a jittery client who needs to reach [[station/1]] at once to save a deal, and pays well for a pilot willing to take him through Vossk space.", false],
		[4, "", "He survives the Vossk ambush and promises to recommend Maxwell.", false],
	],
	"character/4": [
		[4, "", "A Vossk with this face hails Maxwell on the way to Phoebos and demands surrender in the name of the Vossk Empire.", false],
		[11, "", "Nartok Brek is a clan head of the [[race/1]]. He contacts Maxwell in secret because one of his own commanders is conspiring with a Terran officer and the outlaws, and asks for the traitor to be ambushed in the Yarapu Nebula. He asks for Maxwell's word of honour before he says anything.", false],
		[12, "", "After the ambush he tells Maxwell that the Terran traitor is someone Maxwell already knows.", false],
	],
	"character/5": [
		[4, "", "John Washington, called Doc by his friends, needs an escort for his ship to [[station/2]]. He offers 3,000 credits and settles for 4,500, on condition that there are no witnesses. Maxwell suspects a weapons delivery for the outlaws.", false],
		[5, "", "His cargo arrives. He keeps what it was to himself.", false],
	],
	"character/6": [
		[6, "", "A pilot of Christine Hammond's squadron, who asks over the radio whether this Maxwell is battle-tried at all, without noticing that he can hear it.", false],
		[13, "", "The same squadron stays behind to secure the outlaw station while Christine and Maxwell go after Vlad.", false],
	],
	"character/7": [
		[6, "", "Brent Snocom is the security officer of the space fleet. He sends Maxwell after the spy [[character/8]], with orders that the stolen ship must not fall into enemy hands.", false],
	],
	"character/8": [
		[6, "", "Corsair Lockwood is a spy who fled with one of the space fleet's secret ships.", false],
		[7, "", "Cornered in an asteroid field, he surrenders, and is shot down by Vlad Borsikov anyway.", false],
		[12, "", "It later turns out that Vlad had commissioned him to steal military secrets in the first place.", false],
	],
	"character/9": [
		[7, "", "Mkkt Bkkt runs freight for the Octopod band, known for carrying stolen goods. He insists that everything on board is entirely legal and pays Maxwell to bring his ships to [[station/4]].", false],
	],
	"character/10": [
		[9, "", "Feknor of the Grey has heard of Maxwell and offers him a difficult job: four ships to [[station/5]] across Vossk territory, at 4,000 credits for every ship that arrives.", false],
	],
	"character/11": [
		[1, "", "Admiral Smith of the Terran space fleet gave Maxwell his ship after his discharge, and has Lieutenant Hammond show him how to use it.", false],
		[10, "", "He calls Maxwell in when the Nivelian station is attacked. Their conversation turns sharp when Maxwell talks about his prices and what the Vossk might pay.", false],
		[13, "", "After Christine's death he offers Maxwell his sympathy and the location of Vlad's outlaws.", false],
		[14, "", "He lets Maxwell go after Vlad alone, offers him a place in the fleet, and gives him a hyperspace drive when he declines.", false],
	],
	"character/12": [
		[11, "", "Botom Krant commands the Nivelian station attacked by the Vossk. He asks Maxwell to concentrate on the cruisers and thanks him once the attack is beaten off.", false],
	],
	"race/0": [
		[1, "", "Humans, at war with the [[race/1]] in the fourth millennium. Maxwell is a Terran, and most of the campaign's clients serve the Terran space fleet. Terrans hold more planets and stations than any other people.", false],
		[1, "", "Many of the ships for sale are Terran designs: the [[ship/0]], the [[ship/6]] and its modified [[ship/7]], and the [[ship/4]] gunship.", false],
	],
	"race/1": [
		[1, "", "The Terrans' enemy. Vossk shops sell only their own fighter, the [[ship/8]], and they are the only ones to sell the Vossk weapons. A pilot who works for the Terrans is asked for bribes at Vossk stations, and the other way round.", false],
	],
	"race/2": [
		[1, "", "One of the peoples of the galaxy, with planets and stations of their own.", false],
	],
	"race/3": [
		[1, "", "One of the peoples of the galaxy, with planets and stations of their own.", false],
	],
	"race/4": [
		[1, "", "Their special components go into weapons such as the [[equipment/23]], and the heavy [[ship/3]] bomber is theirs.", false],
	],
	"race/5": [
		[1, "", "Grey ships are known for their enormously heavy armour. The [[ship/9]] scout comes from their fleet and was only recently modified for humanoid pilots, and the [[equipment/4]] missile is built from Grey components. Feknor of the Grey hires Maxwell for a dangerous convoy.", false],
	],
	"race/6": [
		[1, "", "Allies of the Terrans. The [[ship/1]] fighter is a Nivelian development, and the [[equipment/2]] laser is based on Nivelian weapon technology. The Vossk attack on one of their stations brings Maxwell into the war in earnest.", false],
	],
	"race/7": [
		[1, "", "One of the peoples of the galaxy, with planets and stations of their own.", false],
	],
	"race/8": [
		[1, "", "One of the peoples of the galaxy, with planets and stations of their own.", false],
	],
	"race/9": [
		[1, "", "The outlaws are not a people but a way of life: pirates and smugglers who keep planets and stations of their own. Their shops are the only ones to sell the [[ship/7]], and [[station/2]] is their best-known hideout.", false],
	],
	"galaxy": [
		[1, "", "Four quadrants, a hundred systems and five hundred planets and stations. Each quadrant is harder than the one before: its jobs pay more, its enemies are tougher and its shops sell better equipment.", false],
		[1, "", "Flying within a quadrant costs credits by distance; crossing into the neighbouring quadrant or the opposite one costs extra. Once you have visited every place in the galaxy, travel is free.", false],
	],
	"progress/ranks": [
		[1, "Reputation", "Reputation counts the enemies you have destroyed. Every threshold in the table below raises your rank, shown on the Status screen.", false],
		[1, "Level", "Your level grows with the money you earn from missions and jobs. Whenever your total earnings exceed 1.6 times what they were at your last level, you reach the next one. Higher levels make the enemies in your missions tougher.", false],
	],
	"progress/milestones": [
		[1, "", "When you dock, the station greets you with a message the first time your credits pass a milestone or your exploration of the galaxy reaches a new mark. The messages below are the game's own.", false],
		[1, "Wealth", "Wealth is more than a number. With more than 999,999 credits you can trade at every planet and station: the hangar opens even where there is no trade, and you can buy, sell your cargo and loot, and refit your ship there.", false],
		[1, "Exploration", "Every place you visit counts. Visiting all five hundred makes every journey free.", false],
	],
	"progress/loyalty": [
		[1, "", "Your loyalty stands somewhere between the Terrans and the Vossk, shown by the pointer on the Status screen. Every mission you fly for a Terran client moves it one step towards the Terrans; every mission for a Vossk client moves it one step towards the Vossk. It cannot go beyond ten steps either way.", false],
		[1, "", "When you travel to a Terran place while your loyalty leans towards the Vossk, or to a Vossk place while it leans towards the Terrans, you are asked for bribe money on top of the flight costs: 150 credits for each step. Paying a bribe moves your loyalty one step back towards the middle.", false],
	],
	"mode/survival": [
		[1, "", "Survival is a separate mode with its own pilot and high score table. Choose it under Start Game. Enemy ships keep coming, each kill earns points and repairs your hull, and the colour of an enemy's brackets shows how strong it is. Your score earns a rank from the table below.", false],
	],
	"mode/swarm": [
		[1, "", "Swarm is a mode written for this remake, found under Start Game. It opens with a handful of fighters and grows into a crowd that closes in from every side, with surges after the fifth minute.", false],
		[1, "", "Every kill fills the level bar. Each level offers three upgrade cards: a new weapon, a better version of one you carry, an extra muzzle, more range or projectile speed, a stronger shield, repairs on every kill, or a different hull. Declining a card repairs a quarter of your hull instead.", false],
		[1, "", "The weapons, shields and hulls are the ones from your game file. Reaching a rank on the Survival score ladder unlocks the next hull for Swarm.", false],
	],
	"guide/start": [
		[1, "", "After the game file is imported, Start Game offers the campaign, free exploration, Survival and Swarm. The campaign starts at [[station/0]] with an [[ship/0]] and 5,000 credits.", false],
		[1, "The station menu", "At a station, Info describes the place, Hangar opens the shop and your ship, Missions shows the job board and Map lets you travel. During the campaign the job board and the map stay locked, and Go on starts the next briefing. Status shows your level, reputation, playing time, kills and loyalty, and Menu holds the options and saving.", false],
		[1, "", "Not every place has a hangar open to everyone: without trade, the hangar only opens during the campaign or once you have more than 999,999 credits.", false],
	],
	"guide/flight": [
		[1, "", "Waypoints are marked yellow, allies green and enemies red. Objects outside your view are shown at the edge of the screen. A hostile's remaining strength is shown below its marker.", false],
		[1, "", "Your shield absorbs collisions and hits and recharges over time; once it is gone, damage goes to the hull. Boost gives a short burst of speed and needs time to recharge.", false],
		[1, "Controls", "On a keyboard, steer with the mouse or arrow keys, set the throttle with W and S and strafe with A and D. Fire with a click or Space, switch weapons with Q, fire missiles with F and boost with Shift. R engages the autopilot, T speeds up time on safe stretches, E docks near a station and Esc pauses. A controller aims with the right stick and fires with the right trigger. Touch controls have a stick, a throttle and buttons for fire, missiles, boost and navigation; a double tap on Fire turns on autofire.", false],
		[1, "Autopilot and time", "The autopilot flies to the next waypoint or the station. While nothing threatens you, time can run faster; enemies, damage or arriving at a destination bring it back to normal.", false],
	],
	"guide/weapons": [
		[1, "", "Ships have mounts for five kinds of weapon: lasers, plasma guns, photon cannons, missiles and thermo guns. Each mount holds one weapon, and each ship has its own set of mounts. A shield generator fits every ship.", false],
		[1, "", "Lasers and plasma guns fire quickly at medium range. Photon cannons reach furthest and hit hardest per shot but recharge slowly. Thermo guns spray particles at close range with a very high rate of fire. Missiles are launched with their own button, without switching weapons, and do heavy damage with a long reload.", false],
		[1, "", "Shields differ in capacity and in how fast they recharge. The strongest weapons are only sold in the second quadrant and beyond, and the Vossk weapons only at Vossk shops.", false],
	],
	"guide/hangar": [
		[1, "", "The hangar has three parts: Ship shows your ship with its mounted weapons and shield, Cargo holds your goods and spare equipment, and Shop offers the station's stock.", false],
		[1, "", "Bought equipment goes into the cargo hold; install it from there if your ship has a free mount for it. Equipment and ships sell back for half their price.", false],
		[1, "", "Buying a ship trades in your current one. Equipment that fits the new ship stays mounted and the rest moves to the hold, as long as there is room for it.", false],
		[1, "", "Shops sell between one and four weapons or shields and up to three ships, chosen from what the place's quadrant and people allow. A shop's stock is renewed when you come back after flying elsewhere. During the campaign each chapter has its own fixed stock.", false],
	],
	"guide/trade": [
		[1, "", "Goods come from the wreckage of destroyed ships and are collected into your hold after the mission. Sell them in the hangar's cargo section. Some fetch most where technology is low, some where it is high, and some the same price everywhere; each goods page lists its price at every technology level.", false],
		[1, "", "Shops do not stock goods of their own. What you sell at a shop stays in its stock, and you can buy it back there at the same price.", false],
		[1, "", "Trade needs a hangar: planets and stations without trade only open theirs to pilots with more than 999,999 credits.", false],
	],
	"guide/travel": [
		[1, "", "The map shows the galaxy, its quadrants and systems. Choose a place and travel there for the flight costs shown, plus bribe money if your loyalty is against its people. You arrive docked.", false],
		[1, "", "Flight costs grow with distance. Changing quadrant adds 15,000 credits to the fare, and 30,000 for the opposite quadrant. The map shows how much of the galaxy you have explored; with every place visited, travel costs nothing.", false],
		[1, "", "The galaxy opens when the campaign is complete or when you skip it.", false],
	],
	"guide/jobs": [
		[1, "", "Outside the campaign, every station's job board offers a few jobs from clients of different peoples. Each shows its difficulty and reward; difficult jobs pay more, and so do the quadrants further out.", false],
		[1, "", "Now and then a shady crook offers a job paying forty percent more than usual. A finished job pays its reward and moves your loyalty towards the client's people.", false],
	],
	"guide/campaign": [
		[1, "", "The campaign is one line of thirteen missions. A finished mission pays its reward; a failed one can be tried again. When it is complete, the hyperspace drive opens the galaxy and the job board and map become available.", false],
		[1, "", "Skip campaign · Explore, on the start menu or in the station menu, enters free exploration straight away. Skipping gives no completion rewards and keeps your campaign pilot in its own slot.", false],
	],
	"guide/saves": [
		[1, "", "The game saves automatically after each mission and at checkpoints. Campaign, exploration, Survival and Swarm keep separate saves. Load / recover in the pause menu, or Load after a defeat, returns to the last autosave, the start of the flight or the last station.", false],
		[1, "", "Game files → Transfer saves moves your saves to another device that has imported the same game file.", false],
	],
	"guide/tips": [
		[1, "", "Sell the cargo you collect from wrecks before buying equipment; the hold fills quickly on small ships.", true],
		[1, "", "Check a ship's mounts before buying weapons for it: a weapon without a matching mount stays in the hold.", true],
		[1, "", "Hold on to goods until you dock where the technology level favours them.", true],
		[1, "", "Flying only for one side makes the other side's stations expensive to visit.", true],
		[1, "", "Visit new places when you travel anyway: exploring the whole galaxy makes every journey free.", true],
	],
}
