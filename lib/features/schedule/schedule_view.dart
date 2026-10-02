import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../app/theme.dart';
import '../../domain/models/local_date.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import '../shared/dose_tile.dart';
import '../shared/formatters.dart';
import 'schedule_view_model.dart';

/// Calendar plus the doses of the selected day. Used for the user's own
/// schedule and for someone a caregiver looks after.
class ScheduleView extends StatelessWidget {
  const ScheduleView({this.header, this.emptyAction, super.key});

  /// Optional widget shown above the calendar (e.g. companion details).
  final Widget? header;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ScheduleViewModel>();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    if (vm.isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        ?header,
        Card(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TableCalendar<void>(
              locale: locale,
              firstDay: DateTime(2020),
              lastDay: DateTime(2100),
              focusedDay: vm.focusedDay.toDateTime(),
              currentDay: vm.today.toDateTime(),
              selectedDayPredicate: (day) =>
                  LocalDate.fromDateTime(day) == vm.selectedDay,
              startingDayOfWeek: StartingDayOfWeek.saturday,
              availableCalendarFormats: {
                CalendarFormat.month: l10n.calendarMonth,
                CalendarFormat.week: l10n.calendarWeek,
              },
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonShowsNext: false,
                titleTextStyle: theme.textTheme.titleMedium!,
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                selectedDecoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              onDaySelected: (selected, _) =>
                  vm.selectDay(LocalDate.fromDateTime(selected)),
              onPageChanged: (focused) =>
                  vm.changeMonth(LocalDate.fromDateTime(focused)),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, _) {
                  final mark = vm.markFor(LocalDate.fromDateTime(day));
                  if (mark == DayMark.none) return null;
                  final color = switch (mark) {
                    DayMark.missed => AppColors.danger,
                    DayMark.allTaken => AppColors.success,
                    _ => theme.colorScheme.primary,
                  };
                  return Positioned(
                    bottom: 4,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        SectionTitle(
          context.formatDayHeader(vm.selectedDay.toDateTime()),
          trailing: vm.selectedDay == vm.today
              ? null
              : TextButton(onPressed: vm.goToToday, child: Text(l10n.today)),
        ),
        if (vm.selectedDoses.isEmpty)
          EmptyState(
            icon: Icons.event_busy_rounded,
            title: l10n.noDosesThisDay,
            action: vm.medications.isEmpty ? emptyAction : null,
          )
        else
          for (final dose in vm.selectedDoses) ...[
            DoseTile(dose: dose),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}
