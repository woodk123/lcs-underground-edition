import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// A snapshot of an existing follow-up. Reading it never starts a meeting,
/// generates a prospect, changes eagerness or spends a recruitment slot.
@immutable
class PendingRecruitmentMeeting {
  PendingRecruitmentMeeting(RecruitmentSession session)
    : recruiterId = session.recruiter.id,
      prospectId = session.recruit.id,
      recruiterName = session.recruiter.name,
      prospectName = session.recruit.name,
      profession = session.recruit.type.name,
      canOfferJoin =
          session.recruiter.subordinatesLeft > 0 && session.eagerness >= 4,
      readiness = session.eagerness >= 4
          ? 'Ready for a join offer'
          : switch (session.eagerness) {
              1 => 'Will take a lot of persuading',
              2 => 'Interested in learning more',
              3 => 'Feels something needs to be done',
              _ => 'Regrets agreeing to the meetings',
            },
      freeSlots = session.recruiter.subordinatesLeft,
      recruiterLocation =
          session.recruiter.location?.getName() ?? 'No current location',
      inPerson =
          session.recruiter.location?.city == session.recruit.location?.city,
      meetingPlace =
          session.recruit.location?.getName() ?? 'Prospect’s current location',
      venueWarning = !session.recruiter.alive
          ? 'The recruiter is dead. This meeting will be removed when follow-ups run.'
          : session.recruiter.site?.controller != SiteController.lcs
          ? 'The recruiter is currently outside an LCS safehouse. They must return after daily work or this meeting will be lost.'
          : session.recruiter.site?.siege.underSiege == true
          ? 'The recruiter’s safehouse is under siege. This meeting will be lost if it is still under siege when follow-ups run.'
          : null;

  final int recruiterId, prospectId;
  final String recruiterName, prospectName, profession;
  final bool canOfferJoin, inPerson;
  final int freeSlots;
  final String readiness, recruiterLocation, meetingPlace;
  final String? venueWarning;
}

List<PendingRecruitmentMeeting> pendingRecruitmentMeetings() => [
  for (final session in game.recruitmentSessions)
    PendingRecruitmentMeeting(session),
];

/// A compact entry keeps the personnel directory usable. Full follow-ups open
/// in a bounded reader, so long lists do not push its order controls offscreen.
class JournalRecruitmentOverview extends StatelessWidget {
  JournalRecruitmentOverview({super.key})
    : meetings = pendingRecruitmentMeetings(),
      paused = game.disbanding;

  final List<PendingRecruitmentMeeting> meetings;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const ValueKey('people-recruitment-overview'),
      onPressed: () => _showMeetings(context),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        minimumSize: const Size(44, 44),
        foregroundColor: JournalPalette.ink,
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          const JournalIllustratedIcon(icon: JournalIcon.leadership, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Recruitment meetings · ${meetings.length}',
                  style: JournalPalette.small.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  meetings.isEmpty
                      ? 'Recruiting finds prospects when the day runs.'
                      : paused
                      ? 'Follow-ups are paused while disbanding.'
                      : 'Follow-ups run after daily work when you advance the day.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JournalPalette.small.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.expand_more, size: 19),
        ],
      ),
    );
  }

  Future<void> _showMeetings(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) {
      final meetings = pendingRecruitmentMeetings();
      return AlertDialog(
        key: const ValueKey('people-recruitment-dialog'),
        backgroundColor: JournalPalette.page,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Recruitment meetings',
          style: JournalPalette.heading,
        ),
        content: SizedBox(
          width: 620,
          height: math.min(460, MediaQuery.sizeOf(context).height * .55),
          child: SingleChildScrollView(
            key: const ValueKey('people-recruitment-details'),
            child: DefaultTextStyle.merge(
              style: JournalPalette.small,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Follow-up meetings run after daily work when you advance the day. They continue independently of ordinary daily assignments; the recruiter does not need another Recruiting order.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep the recruiter alive and back at an LCS safehouse without a siege when follow-ups run. Otherwise the meeting is lost. Finding a contact is separate from persuading them to join.',
                  ),
                  if (game.disbanding) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Follow-ups are paused while the organisation is disbanding.',
                      style: TextStyle(color: JournalPalette.danger),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (meetings.isEmpty)
                    const Text(
                      'No recruitment meetings pending. Assign Recruiting to look for new prospects during the next day.',
                      key: ValueKey('people-recruitment-empty'),
                    ),
                  for (final meeting in meetings) _meeting(meeting),
                  const SizedBox(height: 5),
                  const Text(
                    'Only current follow-ups appear here. Joined, ended or lost meetings are removed from this list.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('people-recruitment-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to People'),
          ),
        ],
      );
    },
  );

  Widget _meeting(PendingRecruitmentMeeting meeting) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: JournalSurface(
      key: ValueKey(
        'people-recruitment-meeting:${meeting.recruiterId}:${meeting.prospectId}',
      ),
      inset: true,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${meeting.prospectName} · ${meeting.profession}',
            style: JournalPalette.small.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Recruiter: ${meeting.recruiterName}'),
          Text(meeting.readiness),
          Text(
            meeting.freeSlots <= 0
                ? 'No free recruitment slots. A join offer is unavailable until the recruiter has capacity; discuss politics to continue meeting.'
                : '${meeting.freeSlots} free recruitment ${meeting.freeSlots == 1 ? 'slot' : 'slots'}. ${meeting.canOfferJoin ? 'A join offer is available at the next eligible meeting.' : 'Discuss politics to build eagerness; the join offer appears when they are ready.'}',
          ),
          const SizedBox(height: 5),
          Text('Recruiter now: ${meeting.recruiterLocation}'),
          Text(
            meeting.inPerson
                ? 'Current meeting route: in person at ${meeting.meetingPlace}.'
                : 'Current meeting route: video chat across cities.',
          ),
          Text(
            meeting.venueWarning ??
                'Currently at an eligible safehouse. The location is checked again after daily work.',
            style: meeting.venueWarning == null
                ? null
                : const TextStyle(color: JournalPalette.danger),
          ),
        ],
      ),
    ),
  );
}
