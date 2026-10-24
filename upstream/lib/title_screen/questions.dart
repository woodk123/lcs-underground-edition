import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/common_display/print_creature_info.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/gender.dart';
import 'package:lcs_new_age/creature/portrait.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/items/armor_upgrade.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

class _Question {
  _Question(this.question, this.answers);
  final String question;
  final List<_Option> answers;
}

class _Option {
  _Option(
    this.option,
    this.description, {
    required this.bonuses,
    this.onChoose,
  });
  final String option;
  final String description;
  final CreationBonuses bonuses;
  final void Function()? onChoose;

  void apply(Creature founder) {
    bonuses.apply(founder);
    onChoose?.call();
  }
}

enum Recruits { gang, none }

Future<void> characterCreationQuestions(Creature founder, bool choose) async {
  bool gay = false;
  Recruits recruits = Recruits.none;
  String makeOutWith = switch (founder.gender) {
    Gender.male => "another boy",
    Gender.female => "another girl",
    _ => "my friend",
  };

  List<_Question> questions = [
    _Question("In the moments after I was born in 2004...", [
      _Option(
        "American torture of prisoners in Iraq was revealed on national TV.",
        "+2 Agility, June 30th",
        bonuses: CreationBonuses(
          attributes: const {Attribute.agility: 2},
          birthDate: DateTime(2004, 6, 30),
        ),
      ),
      _Option(
        "Ronald Reagan died.",
        "+2 Strength, June 5th",
        bonuses: CreationBonuses(
          attributes: const {Attribute.strength: 2},
          birthDate: DateTime(2004, 6, 5),
        ),
      ),
      _Option(
        "Firefox was released, challenging Microsoft's dominance over web browsers.",
        "+2 Intelligence, November 9th",
        bonuses: CreationBonuses(
          attributes: const {Attribute.intelligence: 2},
          birthDate: DateTime(2004, 11, 9),
        ),
      ),
      _Option(
        "Kenyan democracy activist Wangarĩ Maathai received the Nobel Peace Prize.",
        "+2 Charisma, October 8th",
        bonuses: CreationBonuses(
          attributes: const {Attribute.charisma: 2},
          birthDate: DateTime(2004, 10, 8),
        ),
      ),
      _Option(
        "Massachusetts became the first State to legalize same-sex marriage.",
        "+2 Heart, May 17th",
        bonuses: CreationBonuses(
          attributes: const {Attribute.heart: 2},
          birthDate: DateTime(2004, 5, 17),
        ),
      ),
    ]),
    _Question("As a kid, when I was bad...", [
      _Option(
        "my parents threw away my toys.  I started to hide what I cared about.",
        "+1 Stealth, +1 Agility",
        bonuses: const CreationBonuses(
          attributes: {Attribute.agility: 1},
          skills: {Skill.stealth: 1},
        ),
      ),
      _Option(
        "my father beat me.  I learned to take a punch earlier than most.",
        "+1 Martial Arts, +1 Strength",
        bonuses: const CreationBonuses(
          attributes: {Attribute.strength: 1},
          skills: {Skill.martialArts: 1},
        ),
      ),
      _Option(
        "I was locked in my room, where I studied quietly by myself, alone.",
        "+1 Computers, +1 Intelligence",
        bonuses: const CreationBonuses(
          attributes: {Attribute.intelligence: 1},
          skills: {Skill.computers: 1},
        ),
      ),
      _Option(
        "I was never punished.  I was good at lying.  Their innocent little angel.",
        "+1 Disguise, +1 Charisma",
        bonuses: const CreationBonuses(
          attributes: {Attribute.charisma: 1},
          skills: {Skill.disguise: 1},
        ),
      ),
      _Option(
        "I was grounded from electronics.  I spent a lot of time drawing.",
        "+1 Art, +1 Heart",
        bonuses: const CreationBonuses(
          attributes: {Attribute.heart: 1},
          skills: {Skill.art: 1},
        ),
      ),
    ]),
    _Question("In elementary school...", [
      _Option(
        "I was mischevious, and always up to something.",
        "+1 Disguise, +1 Agility",
        bonuses: const CreationBonuses(
          attributes: {Attribute.agility: 1},
          skills: {Skill.disguise: 1},
        ),
      ),
      _Option(
        "I was unruly and often fought with other children.",
        "+1 Martial Arts, +1 Strength",
        bonuses: const CreationBonuses(
          attributes: {Attribute.strength: 1},
          skills: {Skill.martialArts: 1},
        ),
      ),
      _Option(
        "I was the head of the class, and I worked very hard.",
        "+1 Writing, +1 Intelligence",
        bonuses: const CreationBonuses(
          attributes: {Attribute.intelligence: 1},
          skills: {Skill.writing: 1},
        ),
      ),
      _Option(
        "I was the class clown.  I even had some friends.",
        "+1 Persuasion, +1 Charisma",
        bonuses: const CreationBonuses(
          attributes: {Attribute.charisma: 1},
          skills: {Skill.persuasion: 1},
        ),
      ),
      _Option(
        "I was a daydreamer.  What is, what was, what could be.",
        "+1 Art, +1 Heart",
        bonuses: const CreationBonuses(
          attributes: {Attribute.heart: 1},
          skills: {Skill.art: 1},
        ),
      ),
    ]),
    _Question("When I turned 10, my parents divorced.", [
      _Option(
        "Acrimoniously.  I once tripped over the paperwork!",
        "+1 Law, +1 Agility",
        bonuses: const CreationBonuses(
          attributes: {Attribute.agility: 1},
          skills: {Skill.law: 1},
        ),
      ),
      _Option(
        "Violently.",
        "+1 Martial Arts, +1 Strength",
        bonuses: const CreationBonuses(
          attributes: {Attribute.strength: 1},
          skills: {Skill.martialArts: 1},
        ),
      ),
      _Option(
        "My studies suffered, but I continued working.",
        "+1 Computers, +1 Intelligence",
        bonuses: const CreationBonuses(
          attributes: {Attribute.intelligence: 1},
          skills: {Skill.computers: 1},
        ),
      ),
      _Option(
        "This was when I began to understand that words were weapons.",
        "+1 Psychology, +1 Charisma",
        bonuses: const CreationBonuses(
          attributes: {Attribute.charisma: 1},
          skills: {Skill.psychology: 1},
        ),
      ),
      _Option(
        "I kept a journal online.  It still hurts to read the old entries.",
        "+1 Writing, +1 Heart",
        bonuses: const CreationBonuses(
          attributes: {Attribute.heart: 1},
          skills: {Skill.writing: 1},
        ),
      ),
    ]),
    _Question("In middle school...", [
      _Option(
        "I broke into lockers and was into punk rock.",
        "+2 Security, +1 Music, +1 Agility, Punk Jacket",
        onChoose: () {
          founder.giveArmor(
            Clothing.fromType(
              clothingTypes["CLOTHING_PUNK_JACKET"]!,
              armorUpgrades["ARMOR_LEATHER"]!,
            ),
          );
        },
        bonuses: const CreationBonuses(
          attributes: {Attribute.agility: 1},
          skills: {Skill.security: 2, Skill.music: 1},
        ),
      ),
      _Option(
        "I was obsessed with Japanese swords and started lifting weights.",
        "+2 Martial Arts, +1 Strength, Katana and Wakizashi",
        onChoose: () {
          founder.giveWeaponAndAmmo(
            "WEAPON_DAISHO",
            0,
            lootPile: founder.base?.loot,
          );
        },
        bonuses: const CreationBonuses(
          attributes: {Attribute.strength: 1},
          skills: {Skill.martialArts: 2},
        ),
      ),
      _Option(
        "I created my own chess engine.  I had no friends.",
        "+2 Computers, +1 Intelligence",
        bonuses: const CreationBonuses(
          attributes: {Attribute.intelligence: 1},
          skills: {Skill.computers: 2},
        ),
      ),
      _Option(
        "I joined the drama club, but they never had enough roles for me.",
        "+2 Disguise, +1 Charisma",
        bonuses: const CreationBonuses(
          attributes: {Attribute.charisma: 1},
          skills: {Skill.disguise: 2},
        ),
      ),
      _Option(
        "I tried starting a band.  I had to play all the instruments myself.",
        "+2 Music, +1 Heart",
        bonuses: const CreationBonuses(
          attributes: {Attribute.heart: 1},
          skills: {Skill.music: 2},
        ),
      ),
    ]),
    _Question("Things were getting really bad...", [
      _Option(
        "when I stole my first car.  I got a few blocks before I totaled it.",
        "+2 Security, +1 Driving",
        bonuses: const CreationBonuses(
          skills: {Skill.security: 2, Skill.driving: 1},
        ),
      ),
      _Option(
        "and I went to live with my dad.  I learned gun safety the hard way.",
        "+2 Firearms, +1 First Aid",
        bonuses: const CreationBonuses(
          skills: {Skill.firearms: 2, Skill.firstAid: 1},
        ),
      ),
      _Option(
        "and I tried being a teacher's assistant.  It just made me a target.",
        "+2 Teaching, +1 Science",
        bonuses: const CreationBonuses(
          skills: {Skill.teaching: 2, Skill.science: 1},
        ),
      ),
      _Option(
        "so I ran for class president.  The campaign was a disaster.",
        "+2 Persuasion, +1 Writing",
        bonuses: const CreationBonuses(
          skills: {Skill.persuasion: 2, Skill.writing: 1},
        ),
      ),
      _Option(
        "and I went completely goth.  I had no friends and made my own clothes.",
        "+2 Tailoring, +1 Disguise, Black Formalwear",
        onChoose: () {
          if (founder.gender != Gender.male) {
            founder.giveClothingType(
              "CLOTHING_BLACKDRESS",
              lootPile: founder.base?.loot,
            );
          } else {
            founder.giveClothingType(
              "CLOTHING_BLACKSUIT",
              lootPile: founder.base?.loot,
            );
          }
        },
        bonuses: const CreationBonuses(
          skills: {Skill.tailoring: 2, Skill.disguise: 1},
        ),
      ),
    ]),
    _Question("Well, I knew it had reached a crescendo when...", [
      _Option(
        "I stole a cop car when I was only 14.  I went to juvie for 6 months.",
        "+1 Driving, +1 Security, +1 Street Smarts",
        bonuses: const CreationBonuses(
          skills: {Skill.driving: 1, Skill.security: 1, Skill.streetSmarts: 1},
        ),
      ),
      _Option(
        "my step mom shot her ex-husband, my dad, with a shotgun.  She got off.",
        "+1 Firearms, +1 Dodge, +1 Law",
        bonuses: const CreationBonuses(
          skills: {Skill.firearms: 1, Skill.dodge: 1, Skill.law: 1},
        ),
      ),
      _Option(
        "I got caught hacking my grades.  But they made it so fucking easy!",
        "+3 Computers",
        bonuses: const CreationBonuses(skills: {Skill.computers: 3}),
      ),
      _Option(
        "I resorted to controlling people.  I built my own clique of outcasts.",
        "+2 Persuasion, +1 Street Smarts",
        bonuses: const CreationBonuses(
          skills: {Skill.persuasion: 2, Skill.streetSmarts: 1},
        ),
      ),
      _Option(
        "I got caught making out with $makeOutWith.  So God hated me for that?",
        "+2 Seduction, +1 Religion",
        onChoose: () {
          gay = true;
        },
        bonuses: const CreationBonuses(
          skills: {Skill.seduction: 2, Skill.religion: 1},
        ),
      ),
    ]),
    _Question("I was only 15 when I ran away, and...", [
      _Option(
        "I started robbing houses:  rich people only.  I was fed up with their crap.",
        "+2 Security, +1 Stealth, +1 Agility",
        bonuses: const CreationBonuses(
          attributes: {Attribute.agility: 1},
          skills: {Skill.security: 2, Skill.stealth: 1},
        ),
      ),
      _Option(
        "I hung out with thugs and beat the shit out of people.",
        "+2 Martial Arts, +1 Street Smarts, +1 Strength",
        bonuses: const CreationBonuses(
          attributes: {Attribute.strength: 1},
          skills: {Skill.martialArts: 2, Skill.streetSmarts: 1},
        ),
      ),
      _Option(
        "I learned what it took to survive.  When to move on, where to hide.",
        "+2 Street Smarts, +1 Stealth, +1 Intelligence",
        bonuses: const CreationBonuses(
          attributes: {Attribute.intelligence: 1},
          skills: {Skill.streetSmarts: 2, Skill.stealth: 1},
        ),
      ),
      _Option(
        "I volunteered for a left-wing candidate.  "
            "${forceGenderBinary(Gender.nonbinary).heSheCap} didn't even come close.",
        "+2 Persuasion, +1 Law, +1 Charisma",
        bonuses: const CreationBonuses(
          attributes: {Attribute.charisma: 1},
          skills: {Skill.persuasion: 2, Skill.law: 1},
        ),
      ),
      _Option(
        "I let people pay me for sex.  I needed the money to survive.",
        "+2 Seduction, +1 Street Smarts, +1 Heart",
        bonuses: const CreationBonuses(
          attributes: {Attribute.heart: 1},
          skills: {Skill.seduction: 2, Skill.streetSmarts: 1},
        ),
      ),
    ]),
    _Question("Life went on.  On my 18th birthday...", [
      _Option(
        "I stole a sports car.  The owner must have been pissed!",
        "+1 Driving, Sports Car",
        onChoose: () {
          Vehicle v = Vehicle(vehicleTypes["SPORTSCAR"]!.idName)..heat = 1;
          v.location = founder.base;
          vehiclePool.add(v);
          founder.preferredCarId = v.id;
        },
        bonuses: const CreationBonuses(skills: {Skill.driving: 1}),
      ),
      _Option(
        "I bought myself an assault rifle.  An AK-102.  Fully automatic.",
        "+1 Firearms, AK-102",
        onChoose: () {
          founder.giveWeaponAndAmmo("WEAPON_AK102", 9);
        },
        bonuses: const CreationBonuses(skills: {Skill.firearms: 1}),
      ),
      _Option(
        "I celebrated.  I'd saved a thousand bucks!",
        "+1 Business, \$1000",
        onChoose: () {
          ledger.forceSetFunds(1000);
        },
        bonuses: const CreationBonuses(skills: {Skill.business: 1}),
      ),
      _Option(
        "I started wearing a security uniform to explore major buildings downtown.",
        "+1 Disguise, Security Uniform, Downtown Maps",
        onChoose: () {
          founder.giveClothingType(
            "CLOTHING_SECURITYUNIFORM",
            lootPile: founder.base?.loot,
          );
          Iterable<Site> downtownSites =
              founder.base?.city.districts[1].sites.where(
                (s) => s.type != SiteType.oubliette,
              ) ??
              [];
          for (Site site in downtownSites) {
            site.mapped = true;
          }
        },
        bonuses: const CreationBonuses(skills: {Skill.disguise: 1}),
      ),
      _Option(
        "I went to a party and met a cool law student.  We've been dating since.",
        "+1 Seduction, Sleeper Lawyer",
        onChoose: () {
          Creature lawyer = Creature.fromId(
            CreatureTypeIds.lawyer,
            align: Alignment.liberal,
          );
          // Cap strength and agility at 3, and wisdom at 1...
          int spare = 0;
          if (lawyer.rawAttributes[Attribute.strength]! > 3) {
            spare += lawyer.rawAttributes[Attribute.strength]! - 3;
            lawyer.rawAttributes[Attribute.strength] = 3;
          }
          if (lawyer.rawAttributes[Attribute.agility]! > 3) {
            spare += lawyer.rawAttributes[Attribute.agility]! - 3;
            lawyer.rawAttributes[Attribute.agility] = 3;
          }
          if (lawyer.rawAttributes[Attribute.wisdom]! > 1) {
            spare += lawyer.rawAttributes[Attribute.wisdom]! - 1;
            lawyer.rawAttributes[Attribute.wisdom] = 1;
          }
          // ...and move the excess to intelligence, charisma, and heart
          while (spare > 0) {
            lawyer.adjustAttribute(
              [
                Attribute.intelligence,
                Attribute.charisma,
                Attribute.heart,
              ].random,
              1,
            );
            spare--;
          }
          // Force competence in law and persuasion
          while (lawyer.skill(Skill.law) < lawyer.skillCap(Skill.law) - 1) {
            lawyer.adjustSkill(Skill.law, 1);
          }
          while (lawyer.skill(Skill.persuasion) <
              lawyer.skillCap(Skill.persuasion) - 1) {
            lawyer.adjustSkill(Skill.persuasion, 1);
          }
          // Finally, add juice to boost stats even further
          lawyer.juice = 100;
          lawyer.birthDate = gameState.date.subtract(
            Duration(days: 365 * 25 + lcsRandom(365)),
          );
          if (gay) {
            lawyer.genderAssignedAtBirth = lawyer.gender = founder.gender;
          } else {
            if (founder.gender == Gender.male) {
              lawyer.genderAssignedAtBirth = lawyer.gender = Gender.female;
            } else if (founder.gender == Gender.female) {
              lawyer.genderAssignedAtBirth = lawyer.gender = Gender.male;
            }
          }
          lawyer.sleeperAgent = true;
          lawyer.seduced = true;
          lawyer.hireId = founder.id;
          lawyer.workLocation = findSiteInSameCity(
            founder.base?.city,
            SiteType.courthouse,
          );
          lawyer.location = lawyer.workLocation;
          lawyer.nameCreature();
          // The generic builder cast a face before this reward set age/gender.
          lawyer.portraitId = null;
          lawyer.portraitAssignedAge = null;
          ensurePortraitId(lawyer);
          pool.add(lawyer);
        },
        bonuses: const CreationBonuses(skills: {Skill.seduction: 1}),
      ),
    ]),
    _Question("For the last year or so, I've been...", [
      _Option(
        "stealing from Corporations.  I know they're hiding the truth.",
        "+3 Agility, +1 Intelligence, +2 Security Stealth Computers and Disguise",
        onChoose: () {
          founder.type = creatureTypes[CreatureTypeIds.thief]!;
          if (founder.clothing.type.idName == "CLOTHING_CLOTHES") {
            founder.giveClothingType(
              "CLOTHING_BLACKCLOTHES",
              lootPile: founder.base?.loot,
            );
          }
        },
        bonuses: const CreationBonuses(
          attributes: {Attribute.agility: 3, Attribute.intelligence: 1},
          skills: {
            Skill.security: 2,
            Skill.stealth: 2,
            Skill.computers: 2,
            Skill.disguise: 2,
          },
        ),
      ),
      _Option(
        "a violent gang leader.  Nothing can change me, or stand in my way.",
        "+3 Agility and Strength, +3 Firearms and Martial Arts, +1 First Aid, 4 Gang Members",
        onChoose: () {
          founder.type = creatureTypes[CreatureTypeIds.gangMember]!;
          recruits = Recruits.gang;
          if (founder.clothing.type.idName == "CLOTHING_CLOTHES") {
            founder.giveClothingType("CLOTHING_STREETWEAR");
          }
        },
        bonuses: const CreationBonuses(
          attributes: {Attribute.agility: 3, Attribute.strength: 3},
          skills: {Skill.firearms: 3, Skill.martialArts: 3, Skill.firstAid: 1},
        ),
      ),
      _Option(
        "taking college courses.  I'm starting to understand what needs to be done.",
        "+4 Int, +2 Science Computers Writing and Teaching, +1 Business and Law",
        onChoose: () {
          founder.type = creatureTypes[CreatureTypeIds.collegeStudent]!;
        },
        bonuses: const CreationBonuses(
          attributes: {Attribute.intelligence: 4},
          skills: {
            Skill.science: 2,
            Skill.computers: 2,
            Skill.writing: 2,
            Skill.teaching: 2,
            Skill.business: 1,
            Skill.law: 1,
          },
        ),
      ),
      _Option(
        "writing my manifesto and refining my image.  I'm ready to change the world.",
        "+3 Charisma, +1 Intelligence, +2 Persuasion, +1 Law and Writing, +50 juice",
        onChoose: () {
          founder.type = creatureTypes[CreatureTypeIds.politicalActivist]!;
        },
        bonuses: const CreationBonuses(
          attributes: {Attribute.charisma: 3, Attribute.intelligence: 1},
          skills: {Skill.persuasion: 2, Skill.law: 1, Skill.writing: 1},
          juice: 50,
        ),
      ),
      _Option(
        "surviving alone, just like everyone else.  But we can't go on like this.",
        "+4 Heart, +1 Intelligence Strength Agility and Charisma",
        onChoose: () {
          founder.type = creatureTypes[CreatureTypeIds.highschoolDropout]!;
        },
        bonuses: const CreationBonuses(
          attributes: {
            Attribute.heart: 4,
            Attribute.intelligence: 1,
            Attribute.strength: 1,
            Attribute.agility: 1,
            Attribute.charisma: 1,
          },
        ),
      ),
    ]),
  ];

  var questionNumber = 0;
  for (_Question question in questions) {
    questionNumber++;
    int? highlight;
    if (!choose) {
      highlight = lcsRandom(question.answers.length);
    }
    erase();
    mvaddstrc(0, 0, white, "Insight into a Revolution: My Traumatic Childhood");
    makeDelimiter();
    mvaddstrc(9, 0, white, question.question);
    int y = 11;
    for (int i = 0; i < question.answers.length; i++) {
      if (!choose && i != highlight) continue;
      _Option option = question.answers[i];
      String letter = letterAPlus(i);
      if (choose) {
        addOptionText(y++, 0, letter, "$letter - ${option.option}");
      } else {
        mvaddstrc(y++, 4, lightGray, option.option);
      }
      mvaddstrc(y++, 4, darkGray, option.description);
    }

    printCreatureInfo(founder);

    console.creation = CreationContext(
      stage: CreationStage.background,
      title: 'The founder’s background',
      subtitle: choose
          ? 'Choose the experiences that shaped your founder'
          : 'The background chosen by fate',
      prompt: question.question,
      step: questionNumber,
      totalSteps: questions.length,
      founder: founder,
      pendingBonuses: choose ? null : question.answers[highlight!].bonuses,
      choices: choose
          ? [
              for (var i = 0; i < question.answers.length; i++)
                CreationChoice(
                  key: letterAPlus(i),
                  label: question.answers[i].option,
                  description: question.answers[i].description,
                  bonuses: question.answers[i].bonuses,
                ),
            ]
          : const [],
      body: choose
          ? const []
          : [
              question.answers[highlight!].option,
              question.answers[highlight].description,
            ],
    );

    while (true) {
      int choice;
      if (choose) {
        choice = await getKey();
      } else {
        await getKey();
        choice = highlight! + Key.a;
      }
      if (choice >= Key.a && choice <= Key.e) {
        question.answers[choice - Key.a].apply(founder);
        break;
      }
    }
  }

  switch (recruits) {
    case Recruits.gang:
      for (int i = 0; i < 4; i++) {
        Creature recruit = Creature.fromId(
          CreatureTypeIds.gangMember,
          align: Alignment.liberal,
        );
        if (recruit.weapon.type.idName == "WEAPON_AK102" ||
            recruit.weapon.type.idName == "WEAPON_MP5" ||
            recruit.equippedWeapon == null) {
          recruit.giveWeaponAndAmmo("WEAPON_9MM_HANDGUN", 4);
        }
        while (recruit.rawAttributes[Attribute.wisdom]! > 1) {
          recruit.adjustAttribute(Attribute.wisdom, -1);
          recruit.adjustAttribute(
            [Attribute.heart, Attribute.agility, Attribute.strength].random,
            1,
          );
        }
        recruit.nameCreature();
        recruit.location = founder.base;
        recruit.base = founder.base;
        recruit.hireId = founder.id;
        recruit.squad = founder.squad;
        pool.add(recruit);
      }
    case Recruits.none:
      break;
  }
}
