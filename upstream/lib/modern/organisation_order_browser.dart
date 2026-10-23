import 'package:flutter/widgets.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/order_search.dart';

/// Local task browsing only. Drafts, actors and source commands stay in the
/// journal/controller; neither cached rows nor search facts authorize input.
class OrganisationOrderBrowser {
  final search = TextEditingController();
  final taskScroll = ScrollController();
  int group = 0;
  String? categoryId;
  bool showMap = false;

  int _searchRequest = 0;
  bool _disposed = false;
  List<ConsoleAction> _cachedActions = const [];
  List<ActivityOrderCategory> _cachedCatalog = const [];
  String? _cachedTaskStorageId;

  int beginSearchRequest() => ++_searchRequest;
  void invalidateSearchRequests() => _searchRequest++;
  bool isCurrentSearchRequest(int request) =>
      !_disposed && request == _searchRequest;

  void prepareForSourceInput() {
    search.clear();
    invalidateSearchRequests();
    showMap = false;
  }

  void syncSourceCategory(ConsoleAction? category) {
    categoryId = category?.entityId;
    group = category == null
        ? 3
        : const {'legal', 'illegal', 'sleeper-espionage'}.contains(categoryId)
        ? 0
        : const {'activism', 'sleeper-advocacy'}.contains(categoryId)
        ? 2
        : 1;
  }

  void selectSearchCategory(ActivityOrderCategory category) {
    categoryId = category.id == 'operations' ? null : category.id;
    group = switch (category.id) {
      'legal' || 'illegal' => 0,
      'activism' => 2,
      'operations' => 3,
      _ => 1,
    };
  }

  OrganisationOrderBrowsing project({
    required List<ConsoleAction> actions,
    required ActivityOrderFrame? frame,
    required bool busy,
    required bool undercover,
  }) {
    final taskStorageId = 'journal-tasks:$group:$categoryId';
    // Keep the old rows and their own scroll identity through actor/category
    // transitions. The journal disables their callbacks until a fresh reader.
    if (frame != null && !busy) {
      _cachedActions = List.unmodifiable(actions);
      _cachedCatalog = frame.catalog;
      _cachedTaskStorageId = taskStorageId;
    }
    final browsingActions = busy ? _cachedActions : actions;
    final catalog = busy
        ? _cachedCatalog
        : frame?.catalog ?? const <ActivityOrderCategory>[];
    final categoryIds = undercover
        ? const {'sleeper-advocacy', 'sleeper-espionage'}
        : switch (group) {
            0 => const {'legal', 'illegal'},
            1 => const {'acquisition', 'education', 'teaching', 'medical'},
            2 => const {'activism'},
            _ => const <String>{},
          };
    final searching = search.text.trim().isNotEmpty && catalog.isNotEmpty;
    return OrganisationOrderBrowsing(
      categories: browsingActions.where(
        (action) =>
            const {
              'activity-category',
              'sleeper-category',
              'sleeper-category-selected',
            }.contains(action.entityType) &&
            categoryIds.contains(action.entityId),
      ),
      tasks: browsingActions.where(
        (action) =>
            activityTypeForAction(action) != null &&
            !action.entityType!.endsWith('-confirm') &&
            (group == 3 ? action.x < 40 : action.x >= 40),
      ),
      catalog: catalog,
      searching: searching,
      results: [
        for (final category in catalog)
          for (final task in category.tasks)
            if (matchesOrderSearch(category, task, search.text))
              (category, task),
      ],
      taskStorageId: searching
          ? 'journal-task-search:${search.text.trim()}'
          : busy && _cachedTaskStorageId != null
          ? _cachedTaskStorageId!
          : taskStorageId,
    );
  }

  void settleTaskScroll() {
    if (taskScroll.hasClients) {
      // Persist the current offset before disposing a reader's scroll position.
      taskScroll.jumpTo(taskScroll.offset);
    }
  }

  void dispose() {
    _disposed = true;
    search.dispose();
    taskScroll.dispose();
  }
}

/// Display facts retain original action identities but are never commands.
@immutable
class OrganisationOrderBrowsing {
  OrganisationOrderBrowsing({
    required Iterable<ConsoleAction> categories,
    required Iterable<ConsoleAction> tasks,
    required Iterable<ActivityOrderCategory> catalog,
    required Iterable<(ActivityOrderCategory, ActivityOrderTask)> results,
    required this.searching,
    required this.taskStorageId,
  }) : categories = List.unmodifiable(categories),
       tasks = List.unmodifiable(tasks),
       catalog = List.unmodifiable(catalog),
       results = List.unmodifiable(results);

  final List<ConsoleAction> categories, tasks;
  final List<ActivityOrderCategory> catalog;
  final List<(ActivityOrderCategory, ActivityOrderTask)> results;
  final bool searching;
  final String taskStorageId;
}
