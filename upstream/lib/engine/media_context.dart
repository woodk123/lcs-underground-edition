import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/console.dart';

/// A visible archive row computed by the original media handler.
@immutable
class MediaArchiveEntry {
  const MediaArchiveEntry({
    required this.index,
    required this.action,
    required this.headline,
    required this.date,
    required this.dateLabel,
    required this.publisher,
    required this.publisherAlignment,
    required this.impact,
    required this.impactLabel,
    required this.unread,
  });

  final int index;
  final ConsoleAction action;
  final String headline;
  final DateTime date;
  final String dateLabel;
  final String publisher;
  final String publisherAlignment;
  final double impact;
  final String impactLabel;
  final bool unread;
}

/// Exact statistics, rows and commands from one original archive await.
///
/// It contains source-computed data only. It does not generate news, estimate
/// effects, reinterpret the political formulas or alter a story's read state.
@immutable
class MediaOverviewFrame {
  MediaOverviewFrame({
    required this.publicMood,
    required this.lcsSupport,
    required this.lcsSupportColorKey,
    required this.page,
    required this.pageCount,
    required this.totalStories,
    required List<MediaArchiveEntry> entries,
    required List<ConsoleAction> controls,
    required List<String> notes,
  }) : entries = List.unmodifiable(entries),
       controls = List.unmodifiable(controls),
       notes = List.unmodifiable(notes);

  final double publicMood;
  final double lcsSupport;
  final String lcsSupportColorKey;
  final int page;
  final int pageCount;
  final int totalStories;
  final List<MediaArchiveEntry> entries;
  final List<ConsoleAction> controls;
  final List<String> notes;
}

final _mediaFrames = Expando<MediaOverviewFrame>();

void describeMediaOverview(Console console, MediaOverviewFrame frame) =>
    _mediaFrames[console] = frame;

MediaOverviewFrame? mediaOverviewFrame(Console console) =>
    console.awaitingInput &&
        !console.textInput &&
        console.screen == 'media-archive'
    ? _mediaFrames[console]
    : null;
