import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/engine/media_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/newspaper/display_news.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/newspaper/squad_story_text.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/interface_options.dart';

Future<void> mediaOverview() async {
  List<NewsStory> newsArchive = gameState.newsArchive.reversed.toList();
  bool redraw = true;
  while (redraw) {
    redraw = false;
    erase();
    double publicMood = gameState.politics.publicMood();
    double lcsSupport = gameState.politics.lcsApproval();
    final archiveRows = <int, MediaArchiveEntry>{};
    const supporterNote =
        'LCS activities will inspire supporters, but may alienate detractors.';
    const violenceNote =
        'Avoiding violence will increase public support for your actions.';
    makeDelimiter(y: 20);
    mvaddstrx(
      21,
      0,
      "&G${gameState.politics.publicMood().toStringAsFixed(1)}%&w of people have Liberal views",
    );
    String lcsSupportColorKey = lcsSupport >= publicMood
        ? ColorKey.lightGreen
        : lcsSupport < publicMood - 20
        ? ColorKey.red
        : ColorKey.yellow;
    String lcsSupportString = lcsSupport.toStringAsFixed(1);
    mvaddstrx(
      22,
      0,
      "&$lcsSupportColorKey$lcsSupportString%&w support the Liberal Crime Squad",
    );
    setColor(midGray);
    mvaddstrx(
      23,
      0,
      '  $supporterNote',
    );
    mvaddstrx(
      24,
      0,
      '  $violenceNote',
    );

    await pagedInterface(
      navigationSection: 'media',
      headerPrompt: "Media Overview",
      headerKey: {4: "HEADLINE", 40: "DATE", 53: "SOURCE", 72: "IMPACT"},
      footerPrompt: "Press a Letter to read a news article",
      count: gameState.newsArchive.length,
      pageSize: 17,
      onAwait: (page, pageCount) {
        console.screen = 'media-archive';
        describeMediaOverview(
          console,
          MediaOverviewFrame(
            publicMood: publicMood,
            lcsSupport: lcsSupport,
            lcsSupportColorKey: lcsSupportColorKey,
            page: page,
            pageCount: pageCount,
            totalStories: gameState.newsArchive.length,
            entries: [
              for (final action in console.actions)
                if (action.entityType == 'news-story')
                  archiveRows[int.parse(action.entityId!)]!,
            ],
            controls: [
              for (final action in console.actions)
                if (action.entityType != 'news-story') action,
            ],
            notes: const [supporterNote, violenceNote],
          ),
        );
      },
      lineBuilder: (y, key, index) {
        NewsStory ns = newsArchive[index];
        String headline = ns.headline;
        if (headline.isEmpty) {
          switch (ns.type) {
            case NewsStories.squadSiteAction:
              String name = "";
              if (ns.loc != null) {
                name = squadStoryTextLocation(ns, false, includeOpening: false);
              }
              if (ns.liberalSpin) {
                headline = "LCS Action $name";
              } else {
                headline = "LCS Rampage $name";
              }
            case NewsStories.squadKilledInSiteAction:
              headline = "Tragic LCS Strike";
            case NewsStories.ccsKilledInSiteAction:
              headline = "CCS Squad KIA";
            case NewsStories.ccsSiteAction:
              String name = "";
              if (ns.loc != null) {
                name = squadStoryTextLocation(ns, true, includeOpening: false);
              }
              if (ns.liberalSpin) {
                headline = "CCS Action $name";
              } else {
                headline = "CCS Rampage $name";
              }
            default:
              headline = ns.body.split("\n").first.split(" - ").last;
          }
        }
        final fullHeadline = headline;
        if (headline.length > 32) {
          headline = "${headline.substring(0, 32).trim()}...";
        }
        DateTime date = ns.date;
        String dateString =
            "${getMonthShort(date.month)} ${date.day}, ${date.year}";
        mvaddstrc(y, 40, lightGray, dateString);
        Map<View, double> impact = ns.effects;
        double totalImpact = impact.entries
            .where((e) => e.key != View.lcsKnown)
            .fold(0, (a, b) => a + b.value);
        String headlineColorKey = ns.unread
            ? ColorKey.lightBlue
            : ColorKey.lightGray;
        addOptionText(y, 0, key, "$key - &$headlineColorKey$headline");
        console.annotateActionEntity(key,
            type: 'news-story', id: index.toString());
        mvaddstrc(y, 53, ns.publicationAlignment.color, ns.publicationName);
        final impactLabel = totalImpact > 0
            ? '+${totalImpact.toStringAsFixed(1)}%'
            : totalImpact < 0
                ? '${totalImpact.toStringAsFixed(1)}%'
                : 'N/A';
        if (totalImpact > 0) {
          mvaddstrc(y, 72, lightGreen, impactLabel);
        } else if (totalImpact < 0) {
          mvaddstrc(y, 72, red, impactLabel);
        } else {
          mvaddstrc(y, 72, lightGray, impactLabel);
        }
        archiveRows[index] = MediaArchiveEntry(
          index: index,
          action: console.actions.singleWhere((action) =>
              action.entityType == 'news-story' &&
              action.entityId == index.toString()),
          headline: fullHeadline,
          date: date,
          dateLabel: dateString,
          publisher: ns.publicationName,
          publisherAlignment: ns.publicationAlignment.label,
          impact: totalImpact,
          impactLabel: impactLabel,
          unread: ns.unread,
        );
      },
      onChoice: (index) async {
        if (index < newsArchive.length) {
          NewsStory ns = newsArchive[index];
          await readNewsStory(ns);
          redraw = true;
          return true;
        }
        return false;
      },
      onOtherKey: (key) {
        if (isBackKey(key)) return true;
        return false;
      },
    );
  }
}

Future<void> readNewsStory(NewsStory ns) async {
  ns.unread = false;
  erase();
  setColor(ns.publicationAlignment.color);
  mvaddstrc(0, 0, ns.publicationAlignment.color, ns.publicationName);
  if (ns.headline.isNotEmpty) {
    addstrc(lightGray, " - ");
    addstrc(white, ns.headline);
  }
  if (ns.byline != null) {
    mvaddstrc(console.y + 1, 0, lightGray, ns.byline!);
  }
  setColor(lightGray);
  addparagraph(console.y + 2, 0, ns.body);
  if (ns.newspaperPhotoId != null) {
    renderNewsPic(ns.newspaperPhotoId!, console.y + 1, ns.remapSkinTones);
  }
  List<String> effectText = ns.effects.entries.map<String>((entry) {
    String viewName = entry.key.label;
    double effectValue = entry.value;
    String effectValueText = effectValue > 0
        ? "&G+${effectValue.toStringAsFixed(1)}%&x"
        : "&R${effectValue.toStringAsFixed(1)}%&x";
    return "$viewName: $effectValueText";
  }).toList();
  setColor(lightGray);
  int y = console.y + 1;
  for (int i = 0; i < effectText.length; i++) {
    mvaddstrx(y + i ~/ 3, 26 * (i % 3), effectText.elementAt(i));
  }
  addOptionText(24, 0, "Any Key", "Press Any Key to Continue");
  console.showArticle(
    title: ns.headline,
    publisher: ns.publicationName.isEmpty
        ? ns.publication.name
        : ns.publicationName,
    body: ns.body,
    date: ns.date,
    byline: ns.byline,
    effects: {
      for (final effect in ns.effects.entries) effect.key.label: effect.value,
    },
  );
  declareMenuNavigation('media');
  await getKey();
}
