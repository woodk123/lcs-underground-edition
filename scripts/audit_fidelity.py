"""Verify retained upstream game/data against its pinned Git base.

Requires Python 3 and the original base commit in upstream/.git. No game files
are written. The JSON report contains every original file's SHA-256, with only
CRLF versus LF normalized for text; binary assets are compared byte-for-byte.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


BASE = "a1a2112dabf4a8d1a25e36a7a747ef99c9318b87"
TEXT_SUFFIXES = {".dart", ".xml", ".csv", ".txt", ".md", ".json", ".svg"}

# These exact contents were reviewed. A change even within an allowed source
# path fails until the reviewer updates this pin and its documented rationale.
REVIEWED = {'lib/basemode/activate_regulars.dart': ('63c63b37463138bc52efb00514c7b7686836f668c5b7ed0709a75470f2b0b89d',
                                         'Presentation: exact actor/confirmation/navigation identities and '
                                         'private read-only category preview branch. Preview changes local '
                                         'menu category only; original immediate keys, defaults, assignments '
                                         'and bulk handlers retained.'),
 'lib/basemode/activate_sleepers.dart': ('92258bce2517ded9f834fdfca0a31e541145b3c4d00986797db17c85f07b684e',
                                         'Presentation: exact sleeper/confirmation/navigation identities and '
                                         'private read-only category preview branch. Original monthly '
                                         'effects, return-to-service, defaults and bulk handlers retained.'),
 'lib/basemode/base_actions.dart': ('08b6793ef48b1e87395415b72e63cc69a78dcbcd86f3ef4c5110e96adbd16d5b',
                                    'Presentation: exact uppercase Drive, actor intent and scoped '
                                    'recipient/reorder choices; only the base vehicle list declares a safe '
                                    'section exit. Original vehicle/order effects retained.'),
 'lib/basemode/base_mode.dart': ('9bfc5d40ac2b4116a0d37456df38679c074079054e75b6f0b3008469a2aa6f7c',
                                 'HQ marker and exact source-authored W/F/C capability snapshot; failed-save '
                                 'guard prevents exit/day advancement; calendar-day helper retained. No '
                                 'duplicated HQ eligibility rules.'),
 'lib/basemode/liberal_agenda.dart': ('bb56803702909c30ea96292cc0966514b891aa849f88c180756e37569aeb0d60',
                                      'Presentation: actual government, chamber counts, laws, source-printed '
                                      'poll statements/percentages and controls captured alongside original '
                                      'printers. Only ongoing Agenda declares safe navigation; disband '
                                      'confirmation and forced victory/defeat score readers retain original '
                                      'sequencing and rules.'),
 'lib/basemode/media_overview.dart': ('0fd7fb419fd6aae8ebce3ee08615f711a7ddcb4a9a8dc716c2ea21649c3a1c91',
                                      'Presentation: source-computed media statistics, complete article rows '
                                      'and exact paged controls captured at the audited archive await. '
                                      'Original generation, unread state and opinion effects retained.'),
 'lib/basemode/plan_site_visit.dart': ('42c37cd1300cf67d6b9f685e4a6e075b84868cf11657f3ac7c5c3caeb05d947b',
                                       'Presentation: current visible place IDs/categories, '
                                       'pagination/planning marker, and reserved U+E000 section exit '
                                       'preserving a queued visit. Original manual Back/Cancel, eligibility, '
                                       'travel costs and visit assignment retained.'),
 'lib/basemode/review_mode.dart': ('918897947da74d33c3ec675649e39134e75f878783025c7aafbb017d0b043c9d',
                                   'Presentation: exact current organisation/squad allocation snapshots and '
                                   'ready action identity, person IDs and audited safe exits. Manual finance '
                                   'entry opts into its read-only navigation; original '
                                   'squad/membership/review mutation handlers retained.'),
 'lib/common_actions/equipment.dart': ('7ee6e9c5c05dd158e20c59149187176a1f5bd25b7b246d1f850941127cff963f',
                                       'Presentation: full roster, explicit unequip intent, scoped '
                                       'recipients/strip/quantity prompts; base equipment and location lists '
                                       'opt into safe section exits, tactical/recipient readers remain '
                                       'untagged. Original mutations retained.'),
 'lib/common_display/common_display.dart': ('030ec5df9ffcdd7709cc1ad6a4f3ef91b9ee733f8d7db8050be116d654cc28e7',
                                            'Optional navigationSection and onAwait(page,pageCount) '
                                            'callback, both absent by default; supplied by the audited media '
                                            'archive after final actions are authored. Original generic '
                                            'pagination, choices and back effects retained. Presentation: '
                                            'complete showMessage text scoped to its unchanged awaited '
                                            'input, safe clear/restore after acknowledgement and erase. '
                                            'Original buffer, delimiters, colors, input, simulation and RNG '
                                            'preserved by eight tests.'),
 'lib/common_display/print_party.dart': ('ec105490b1a70bc0590b7f0b2183b3d4fb0332d7edec75928c083c578d72b642',
                                         'Presentation metadata only: annotate the already displayed squad '
                                         'member with its existing ID; original print/selection behavior '
                                         'retained.'),
 'lib/daily/activities/clothing_creation.dart': ('45d292a7b627b5061d278d8415c68d8a9326d9062eebf3b3af021461a255268a',
                                                 'Confirmed crafting bug fix: calculate the existing cloth '
                                                 'discount before affordability, but consume cloth only '
                                                 'after the unchanged funds check and payment. Unaffordable '
                                                 'jobs preserve inventory; successful cost, item selection, '
                                                 'RNG, XP, output and activity behavior retained. Four '
                                                 'pre-fix failures and exact successful-outcome/RNG '
                                                 'regression cases recorded in engine reports.'),
 'lib/daily/activities/flag_creation.dart': ('0997279db74a26e28291e0014faf87ca7c02fb0f343df88cde291868456c786c',
                                             'Confirmed crafting bug fix: calculate the existing cloth '
                                             'discount before affordability, but consume cloth only after '
                                             'the unchanged funds check and payment. Unaffordable jobs '
                                             'preserve inventory; successful cost, item selection, RNG, XP, '
                                             'output and activity behavior retained. Four pre-fix failures '
                                             'and exact successful-outcome/RNG regression cases recorded in '
                                             'engine reports.'),
 'lib/daily/advance_day.dart': ('b1a3d816811b2846aafe262d96c3caba48d2789665756b146a04be6309b6d7b6',
                                'Failed autosave aborts before daily simulation; calendar helper prevents '
                                'DST date repeats/skips; all daily activities retained.'),
 'lib/engine/changelog.dart': ('340ff6d8a347e6dfb8c8d822274f82949e77e78572364a837ce6a10ca98208ba',
                               'UI only: journal palette/font, complete selectable markdown, '
                               'viewport-bounded reader/header and close affordance; restores the previous '
                               'live focus node, with retained classic fallback. Changelog content and '
                               'original callers unchanged.'),
 'lib/engine/console.dart': ('9f244e253a47792318b14561a2b953756352816a74a14879a91dfb3d10d30cf1',
                             'Presentation bridge: exact action identity/intent/coordinates, scoped choices, '
                             'articles, revisions/text context and bounded input. Per-await '
                             'ConsoleNavigation is cleared on consume/erase/scoped prompts; no simulation '
                             'rules. Read-only CreationContext cleared on erase, retained across name-reader '
                             'key awaits; no new navigation capability or simulation rule. Presentation: '
                             'complete showMessage text scoped to its unchanged awaited input, safe '
                             'clear/restore after acknowledgement and erase. Original buffer, delimiters, '
                             'colors, input, simulation and RNG preserved by eight tests.'),
 'lib/engine/console_widget.dart': ('408c0cd8cbb2f7947d4594e72abc15ad35cd287314cedb9726b4d92641c6f814',
                                    'Retained classic rendering/input; repaint lifecycle, disposal and '
                                    'layout fixes; no simulation rules.'),
 'lib/engine/engine.dart': ('258a8c17b0d9de2631e83e9e9a2a72f7bbe399963ea51ec428f76daf70d8fd70',
                            'Capture exact semantic/modal actions, actual ammo arrows and text context; '
                            'declare per-await safe section navigation and reserved U+E000 menuExit. '
                            'Original readers and simulation loop retained.'),
 'lib/gamestate/time.dart': ('33a344d7bfb55bc0ba1e0224653934cd709298f37a902f1baf04c76df032b7ee',
                             'Calendar-day helper constructs the next date, preserving UTC; month labels '
                             'unchanged.'),
 'lib/main.dart': ('5decaecb4916e31932c3e5a68556f20e240bd0df8e317bcd4f6e7aa0930ada6d',
                   'Start the original launchGame loop inside the modern themed/accessible Flutter shell. '
                   'Share reading scale with app overlays; original game launch retained.'),
 'lib/monthly/lcs_monthly.dart': ('aa54e9d8b6d21ad565a9e5ff97520c0ffc8e9a57387e292ead50dd0c16c0fb18',
                                  'Read-only funding report projection: missing legacy ledger categories '
                                  'display as zero/are omitted, labels and page rows captured with original '
                                  'net/fence valuations. Manual Review call opts into safe navigation; '
                                  'automatic month-end remains required and original reset '
                                  'sequence/formulas/save maps are unchanged.'),
 'lib/newspaper/display_news.dart': ('b23994998dabfa3a3b8491874fa9c8cc9461a846856ea701128785eeea2bfacf',
                                     'Presentation-only article snapshot before original dismissal loop; '
                                     'full generated story and effects retained.'),
 'lib/saveload/save_load.dart': ('48cf887e8f2e74164e28912a08feef2cfe5724434a8aa76adba9fefd7ddca2ef',
                                 'Legacy clothing migration; validate/version-check before commit/import '
                                 'overwrite; rollback active state and isolate RNG during previews; truthful '
                                 'save/export/import errors.'),
 'lib/sitemode/sitemode.dart': ('608833943d07f75e23246cf016f363311ea3a06e53c161f0f35c9845bbae4104',
                                'Presentation: semantic tactical commands with original availability, '
                                'tactical/full-map markers, clean map buffer, exact flee directions; '
                                'combat/movement resolution retained.'),
 'lib/title_screen/high_scores.dart': ('b39a559ff48d2915926d60fd4d9ae17a8854c49ce10f9ab971e47d268b0806aa',
                                       'Bookkeeping: persist completed campaign totals once; active saves '
                                       'remain included only in the display; score formula/endings '
                                       'unchanged.'),
 'lib/title_screen/new_game.dart': ('3051992638fa2851b557f8d322dbef15f3fa2a1492b8e52225ceac22fdafa51f',
                                    'Presentation-only creation context for original setup/identity '
                                    'settings, complete political briefing and final name prompt. Original '
                                    'option cycling, world/founder initialization, RNG, callbacks and name '
                                    'reader unchanged; context cleared after name completion.'),
 'lib/title_screen/questions.dart': ('0e1a4422d0806e0b306689c55e197f6cfdea8c68046e833c27a71b0a5bd8c96d',
                                     'Presentation-only current question number, full original '
                                     'option/description text and already selected fate outcome. Original '
                                     'ten-question order, RNG draws, callbacks, per-answer effects and '
                                     'post-background recruits unchanged.'),
 'lib/title_screen/title_screen.dart': ('6ff5a87a458c6d4f409982e05d27ea39109c6e516c3f8dbb5d832fedf987ac0d',
                                        'Title marker enables modern rendering; title commands/new-game path '
                                        'retained.'),
 'lib/utils/lcsrandom.dart': ('7c223adf2e485cc40ee08cfc9d9b0805cefea41bd8cb1cf0dba82ca1bd5fa689',
                              'Temporarily isolate RNG during synchronous save validation/previews, then '
                              'restore the original Random object; gameplay roll functions unchanged.')}
ADDED_SOURCE = {'lib/engine/agenda_context.dart': '94812174b65557ae23e77402d0c118fc358048e9df432f47c00820c9dd5bc6d9',
 'lib/engine/creation_context.dart': 'b36622fc37fb4152557bb86e89f33d41e8208027d63af0af347a5d6048bc4097',
 'lib/engine/ledger_context.dart': 'bdffba4251d7d884a8781d09c8d9ef9a079af13f8f80ac12305b8c7ec7063ede',
 'lib/engine/media_context.dart': '05d4ea25e32a2904d0773b93a2225e60b74f5443f23168d4ac2d4b6c77715982',
 'lib/engine/organisation_context.dart': '1c15285f4c97ba92046f8b7a2546b81e51db32245e41a2f48b975f38aa67f35a',
 'lib/modern/activity_calculations.dart': 'e89abbe0c30bf33e4a470179dec662aa69eea97c8095ecf100a9450eaf8134fe',
 'lib/modern/article_view.dart': 'd2b3b6ace5a00d12eeefb1faa9e448e76bab8f731d99975b50581c35f8238e06',
 'lib/modern/city_planning_view.dart': '7e4b05b5ef4c240a56cdd2031dba983491cd69b11476f4f63413bce331e0f704',
 'lib/modern/city_scene.dart': '4d3a8f44932ffbf5cf0f7110d269e0dfe85d681b243d16d38ecae4ecba1152b5',
 'lib/modern/crew_dossier.dart': '507c225a031cd44e50271e1577402b8c37ddca60133aea1c0ecab96891eca23d',
 'lib/modern/crew_portrait.dart': '71ec74644eec65aa4cedc07172e87723aae98d215ea9c645af9445e8f226c94d',
 'lib/modern/direct_content.dart': 'fb40303a7b855f4a0146753aef93c5ae0fef7e640df70b9708c4c84fe6b4b98d',
 'lib/modern/full_site_map.dart': '22dfea5a5f17f915ed52381243c317ffdd6b9b14154eb57bcfdf7ae9fa3f04c0',
 'lib/modern/headquarters_view.dart': '71be6a05fd732d602771e0330b640ac8a3632fbba094544ef6a2b8c3a9feb3af',
 'lib/modern/journal_agenda.dart': '54a8e9f084df9b9aa1b04bb6687886906f6ecf90dfe5320cbe42543e293464e0',
 'lib/modern/journal_city_plan.dart': '28b53a9101c6ec8b6c3ec606d5ed1cf4a23436a49c824225098197680788e886',
 'lib/modern/journal_creation.dart': '13d47502701d7c22a8c13547b70f5c6ae2edcab798af21c443b518f116718b48',
 'lib/modern/journal_ledger.dart': 'c45376bb87c9b7519d934ad1507633ddbdb3428f00cb0281ededb941865e9d88',
 'lib/modern/journal_legislation.dart': '39ac6c9fc086b223d5f37530391e17c6e62d3a2509ed872f5ac14391e5c6fed9',
 'lib/modern/journal_media.dart': '656df3ba14089d0042c806e8d307e72dacd01aa328d11bdbc7c82dc25f610769',
 'lib/modern/journal_order_icon.dart': '5f985bd42666f5b0d1321b7906e32afb6891b3ed898f9433071a9e62c65a63fd',
 'lib/modern/journal_theme.dart': 'f49104051be629f9ca3bd857264123276823da2d3b106bc52c28f22508cd2842',
 'lib/modern/journal_title.dart': 'ab1c44f41cbaf824dc9c58b26660f9180b6f74c61e5ba5405035523432a5cef6',
 'lib/modern/mechanics_help.dart': 'bed913b10c1dec6cb764dd7c44537a0872a4ef561794e6aaf1d87bbc1b5ff702',
 'lib/modern/modern_app.dart': '53f8a472503aea25c86b8fafcc0a0209e478d7aa35f56f09fccf6720ca8a96e2',
 'lib/modern/organisation_controller.dart': '3d9c28bf4eabc9718a698dd3cde37e4274d318ee0062ac7678efe1d1a9dfe343',
 'lib/modern/organisation_journal.dart': '16b67543a62480010227cabd28215aa98d5aa5be9b4697fbf99ae2084d13e8be',
 'lib/modern/skill_help.dart': '59c280fb98fe110d7468f92172a7049ff79dcd4aef1725c6ebb4b4aa681ec0ae',
 'lib/modern/tactical_map.dart': '9770fb0c5a3d55425a4dfd411fc74179b26634e856254c597e7871db7a136c9e'}

GENERATED = {
    "lib/basemode/activities.g.dart": "5689165c1061439bc8acb5c23f4d0236db3ff5c3f01be72175a0621b20fb1123",
    "lib/creature/body.g.dart": "8b76c52507a0d59c16e90a04d8c081fb72a5ccd9917b7f7c56bfc94a88c51d2b",
    "lib/creature/creature.g.dart": "e2a0a8129e4972c3d14dca19dc881811ab17a78bfdaa391e3da65979bf2208ac",
    "lib/creature/name.g.dart": "c95e8d809942e562631692ec131cc15ce0fcedc74719a88eba9ea167c2058bbd",
    "lib/creature/unique_creatures.g.dart": "780a965b908e58fa1fbd3d622ee0864cd33298437187740060c6b1013197c00e",
    "lib/daily/dating.g.dart": "f31ec702e29bf8872cb684febe2a7786a2f3d6fd4965ae82ae6eed7da4b55c23",
    "lib/daily/hostages/tend_hostage.g.dart": "ce742ffc2d3ecba180e5f00acf322d9002012c3cab5a8524dfe8f17ed7f530b8",
    "lib/daily/recruitment.g.dart": "1b9ed302342cb870f1695cacac840ae7cbe15d5f34ee9c3efb34afe563cfebcc",
    "lib/gamestate/crime_squad.g.dart": "d0e2813bf2f96793a8424c7a6a765f159c4801372ea3849d03cb30c186638818",
    "lib/gamestate/game_state.g.dart": "265f261cb555a6cc760fc4ad318839d84c8696d7c04aa90b8fe21d985bf0d42f",
    "lib/gamestate/ledger.g.dart": "d8ba502147b0201b7b098f05ca87c3c8aa4086155d9309aaca37e605985f17b3",
    "lib/gamestate/squad.g.dart": "0019753abbbf2b923220c0989d3b7ef9d630a4f698c11b6f1aa311bfadebcec2",
    "lib/gamestate/stats.g.dart": "731d08326a056cb7790934e64b949898fd3592d6590e8d34b987bd95630acc29",
    "lib/items/ammo.g.dart": "46981af70bb2a1d6e60f847c1286b949a75aebf414f1914031803c277efcef52",
    "lib/items/attack.g.dart": "765e223ae2e6da4b4e5177f1d429c5559404e6ea39b7966aa2a1f313cb8cdd30",
    "lib/items/clothing.g.dart": "72802bdb57beddf36782951837376a32ad5ae02fb14e59bef33593c9beaadf64",
    "lib/items/flag.g.dart": "0a2f1984af24713c7f0897015cadca542ed5928df2c4fd6c3c9ce5cad7972ef3",
    "lib/items/item.g.dart": "5804a9c856fb895f8d8ebb9303985ff7be7200ae196d92603547ee2322cdca4e",
    "lib/items/loot.g.dart": "590019df428b8f748946f642af5596ee3ec9256382977bbf00f61aa5e59fe7fa",
    "lib/items/money.g.dart": "a107f837c66c606a753ecf26da27775f947349ea3cdefcb35dd6fc5c33d3f3d6",
    "lib/items/weapon.g.dart": "9c740fb89a5d71e3664955aaaef25f41341fd3ad2a4f4b4d6ff217942bfc7738",
    "lib/location/city.g.dart": "9d5bb672eddb85778555222fc60eadea6ef4a701ef787d6141ce9295a9bc85c6",
    "lib/location/compound.g.dart": "e2f69c39bc8b062a689ed5b53df8c49a7daac7a1e53bb7301bc6c05505c9f580",
    "lib/location/district.g.dart": "295899fa3d2c5baec6fd395b4ed57c98d3b6f8c05781a770224d51d3da617000",
    "lib/location/siege.g.dart": "59a9d418559604e122e93dd56e0bac6bf1dc8e303d18b1b36f703307c9f71058",
    "lib/location/site.g.dart": "a8f2d5e37b15102056202a3ba447246ff56df0c3497e526474971a12a4592f5c",
    "lib/newspaper/news_story.g.dart": "71a531c2e5be503afb9578aef5d6c5c4639016a36922d7316c352367a4f02fa0",
    "lib/politics/politics.g.dart": "39fd2fc15b5a7bcde454f49d686ed6e32b10650a0f38f36ab1e6aad67ee7381e",
    "lib/saveload/save_load.g.dart": "1d072d3b2b21e106daa692d52fac976fda31da2a77a7d2ef51676a63c5a455d3",
    "lib/sitemode/sitemap.g.dart": "8db74d0f96f5418ffb3dca97d567f4e20570c5e8547392f549a1801f9f509f1e",
    "lib/vehicles/vehicle.g.dart": "9412f912bbf51e2e9f430a9802001fc926d0cbe5405a79ff3952d8f19865b933",
}
ADDED_ASSETS = {'assets/modern/app_mark.svg',
 'assets/modern/building_sprites_v2.png',
 'assets/modern/city_panorama.png',
 'assets/modern/crew_portraits_v1.png',
 'assets/modern/journal_icons_v1.png',
 'assets/modern/journal_leather_v1.png',
 'assets/modern/journal_order_icons_v1.png',
 'assets/modern/journal_paper_v1.png',
 'assets/modern/journal_portraits_v1.png',
 'assets/modern/pedestrian_walk_v2.png',
 'assets/modern/safehouse.png',
 'fonts/journal/LibreBaskerville-Italic-Variable.ttf',
 'fonts/journal/LibreBaskerville-Variable.ttf',
 'fonts/journal/OFL.txt',
 'fonts/modern/roboto-black.ttf',
 'fonts/modern/roboto-bold.ttf',
 'fonts/modern/roboto-medium.ttf',
 'fonts/modern/roboto-regular.ttf',
 'fonts/modern/roboto_license.txt'}
PINNED_ASSET_HASHES = {'assets/modern/app_mark.svg': '65fe758840326810cac7cc604fb7072984b3152432ee1b94adb393d41a6a90e4',
 'assets/modern/building_sprites_v2.png': 'bae3af57cfe77627eefdbaff3a9c193a29154e5a5c976cd1f73fd398b0c47263',
 'assets/modern/city_panorama.png': '45c13fe656e6073fa3d22303fcbfe89cfbb6e7fcb9025c0966cc6fb3a6062a4c',
 'assets/modern/crew_portraits_v1.png': '25134e519a8151730ededaf2b94fed8f43543a81d917a04a5e74102e45cf6e07',
 'assets/modern/journal_icons_v1.png': '5044642d06d418cc6a7289d0fc6380a6855dc7cc15d12f66ccf09cfb0ddca043',
 'assets/modern/journal_leather_v1.png': 'c2b5275322ab51be597e2349a3e3bb83bdff4eb9c4a93add1fb3932f9be4518b',
 'assets/modern/journal_order_icons_v1.png': '4cad6bdf225e0d5e0070ab9c8e94403c458eba383499830bec38d34a5f8585e5',
 'assets/modern/journal_paper_v1.png': '4ded547ed5561c66fc504858416ac1a49d38073a7ff3aa2e5d60f28126ab824d',
 'assets/modern/journal_portraits_v1.png': 'cfc84cc822f3a124e1ab7ddae5447157654d0a84e8a8fa1f74ec9ce26c087121',
 'assets/modern/pedestrian_walk_v2.png': 'ed117eb4a247ef4848997971a326ee0541f2106b98560983c9b1378d8f1e5048',
 'assets/modern/safehouse.png': 'fbdf7c6c3e751168ff9b8414f3c0707f0e6ccd4fcc9a4a803bf893d60eec4040',
 'fonts/journal/LibreBaskerville-Italic-Variable.ttf': '223959683dc73ec4437bd61fabaa4b3f22209e22855ffd3aee36ba61a5116e97',
 'fonts/journal/LibreBaskerville-Variable.ttf': '05a95421961341c5b2556285e8415df9db27dab4f4abe22b446b3c6a8b916c5d',
 'fonts/journal/OFL.txt': '55959eef5b0c3b2e3c1c7631b8ff0f9447d75de20f29cfa7db5bcfb026763343',
 'fonts/modern/roboto-black.ttf': '3872e9b39760a1b59ac1e192633dbb3b58e595b4d423930ac7ded525e9ae25e0',
 'fonts/modern/roboto-bold.ttf': '7d0b991ee3e0be7af01ad7ea8cd2beea6c00a25e679a0226b6737f079aafff86',
 'fonts/modern/roboto-medium.ttf': 'f205cc511821ea56078a105557fcea6253129404d411c997e1866fbd006abb68',
 'fonts/modern/roboto-regular.ttf': '79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95',
 'fonts/modern/roboto_license.txt': 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30'}


def group(path: str) -> str | None:
    if path.startswith("lib/") and path.endswith(".dart"):
        return "dart_source"
    if path.startswith("assets/xml/"):
        return "xml_data"
    if path.startswith("assets/maps/"):
        return "authored_maps"
    if path.startswith("assets/"):
        return "other_original_assets"
    if path.startswith("fonts/"):
        return "original_fonts"
    if path in {"LICENSE", "AUTHORS.md"}:
        return "license_and_credits"
    return None


def canonical(data: bytes, path: str) -> bytes:
    if Path(path).suffix.lower() in TEXT_SUFFIXES or path == "LICENSE":
        return data.replace(b"\r\n", b"\n")
    return data


def sha(data: bytes, path: str) -> str:
    return hashlib.sha256(canonical(data, path)).hexdigest()


def git(project: Path, *args: str, data: bytes | None = None) -> bytes:
    return subprocess.run(["git", "-C", str(project), *args], input=data,
                          check=True, capture_output=True).stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    project = root / "upstream"
    output = args.output or root / "docs/FIDELITY_AUDIT.json"
    verified = git(project, "rev-parse", "--verify", f"{BASE}^{{commit}}").decode().strip()
    if verified != BASE:
        raise RuntimeError("Pinned upstream base did not resolve exactly.")
    originals = {}
    for row in git(project, "ls-tree", "-r", "-z", "--full-tree", BASE).split(b"\0"):
        if not row:
            continue
        info, raw_path = row.split(b"\t", 1)
        mode, kind, oid = info.decode().split()
        path = raw_path.decode("utf-8")
        category = group(path)
        if category:
            if kind != "blob":
                raise RuntimeError(f"Unexpected non-file original {path}")
            originals[path] = (oid, category)
    stream = io.BytesIO(git(project, "cat-file", "--batch", data=(
        "\n".join(oid for oid, _ in originals.values()) + "\n").encode()))
    rows = []
    failures = []
    counts: dict[str, Counter] = {}
    declared_generated = set()
    for path, (oid, category) in originals.items():
        header = stream.readline().decode().strip().split()
        if len(header) != 3 or header[0] != oid or header[1] != "blob":
            raise RuntimeError(f"Invalid Git blob response for {path}")
        base_data = stream.read(int(header[2]))
        if stream.read(1) != b"\n":
            raise RuntimeError(f"Invalid Git blob boundary for {path}")
        expected = sha(base_data, path)
        if path.endswith(".dart"):
            for part in re.findall(r"\bpart\s+['\"]([^'\"]+\.g\.dart)['\"]", base_data.decode("utf-8")):
                declared_generated.add((Path(path).parent / part).as_posix())
        current_path = project / path
        current_data = current_path.read_bytes() if current_path.is_file() else None
        actual = sha(current_data, path) if current_data is not None else None
        if actual is None:
            status = "missing"
            failures.append(f"Missing original: {path}")
        elif actual == expected:
            status = "unchanged"
        elif path in REVIEWED:
            status = "reviewed_change"
        else:
            status = "unexpected_change"
            failures.append(f"Unreviewed original modification: {path}")
        if actual is not None and path in REVIEWED and actual != REVIEWED[path][0]:
            failures.append(f"Reviewed file changed after approval: {path}")
        counts.setdefault(category, Counter())[status] += 1
        rows.append({"path": path, "group": category, "status": status,
                     "base_git_blob": oid, "base_sha256": expected,
                     "current_sha256": actual,
                     "base_bytes": len(base_data),
                     "current_bytes": len(current_data) if current_data is not None else None,
                     "reason": REVIEWED.get(path, (None, None))[1]})
    for path in REVIEWED:
        if path not in originals:
            failures.append(f"Reviewed source is absent from pinned base: {path}")
    if declared_generated != GENERATED.keys():
        failures.append("Generated serializer inventory does not match original model part declarations.")
    current = {
        path.relative_to(project).as_posix()
        for folder in ("lib", "assets", "fonts")
        for path in (project / folder).rglob("*")
        if path.is_file() and group(path.relative_to(project).as_posix())
    }
    additions = current - originals.keys()
    expected_additions = ADDED_SOURCE.keys() | GENERATED.keys() | ADDED_ASSETS
    for path in sorted(additions - expected_additions):
        failures.append(f"Unexpected new source/data: {path}")
    for path in sorted(expected_additions - additions):
        failures.append(f"Missing approved new presentation file: {path}")
    added_rows = []
    accepted_source_hashes = ADDED_SOURCE | GENERATED | PINNED_ASSET_HASHES
    for path in sorted(additions):
        actual = sha((project / path).read_bytes(), path)
        if path in accepted_source_hashes and actual != accepted_source_hashes[path]:
            failures.append(f"Approved new or generated content changed after approval: {path}")
        added_rows.append({"path": path, "sha256": actual,
                           "kind": "generated_serializer" if path in GENERATED else "modern_presentation_or_asset",
                           "status": "approved_addition" if path in expected_additions else "unexpected_addition"})
    report = {
        "status": "passed" if not failures else "failed",
        "checked_utc": datetime.now(timezone.utc).isoformat(),
        "audit_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "audited_snapshot_sha256": hashlib.sha256("\n".join(sorted(
            [f"{row['path']}\0{row['current_sha256']}" for row in rows]
            + [f"{row['path']}\0{row['sha256']}" for row in added_rows]
        )).encode()).hexdigest(),
        "upstream_repository": "https://github.com/ashley-s-fox/lcs-new-age",
        "upstream_base_revision": BASE,
        "normalization": "Text CRLF is normalized to LF only; binary bytes remain exact. SHA-256 is not a semantic-equivalence claim.",
        "scope": "All original lib/**/*.dart, assets/**, fonts/**, LICENSE and AUTHORS.md; approved added modern source/art/fonts.",
        "summary": {name: {"original_files": sum(c.values()), **dict(c)}
                    for name, c in sorted(counts.items())},
        "original_file_count": len(rows),
        "approved_modified_source_count": len(REVIEWED),
        "added_source_count": len(ADDED_SOURCE),
        "generated_serializer_count": len(GENERATED),
        "generated_serializer_origin": "Inventory matches original model part declarations; current generated contents are pinned, not claimed to be tracked original files.",
        "added_asset_and_font_count": len(ADDED_ASSETS),
        "files": rows, "additions": added_rows, "failures": failures,
        "limitations": "Source/data retention and exact reviewed change identity only. Runtime scenario evidence is documented separately in GAMEPLAY_FIDELITY.md; this does not certify every original rule path.",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "summary": report["summary"],
                      "approved_modified_source_count": len(REVIEWED),
                      "added_source_count": len(ADDED_SOURCE),
                      "generated_serializer_count": len(GENERATED),
                      "failures": failures, "report": str(output)}, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
