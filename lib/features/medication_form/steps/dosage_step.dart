import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/medication.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/common_widgets.dart';
import '../../shared/formatters.dart';
import '../medication_form_view_model.dart';

class DosageStep extends StatefulWidget {
  const DosageStep({super.key});

  @override
  State<DosageStep> createState() => _DosageStepState();
}

class _DosageStepState extends State<DosageStep> {
  late final TextEditingController _amount = TextEditingController(
    text: context.read<MedicationFormViewModel>().dosageAmount,
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<MedicationFormViewModel>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.dosageLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,/]')),
                ],
                onChanged: vm.setDosageAmount,
                decoration: InputDecoration(hintText: l10n.dosageHint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<DosageUnit>(
                initialValue: vm.unit,
                items: [
                  for (final unit in DosageUnit.values)
                    DropdownMenuItem(
                      value: unit,
                      child: Text(l10n.dosageUnitName(unit.name)),
                    ),
                ],
                onChanged: (unit) {
                  if (unit != null) vm.setUnit(unit);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(l10n.frequencyLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<Frequency>(
          segments: [
            ButtonSegment(
              value: Frequency.daily,
              label: Text(l10n.frequencyDaily),
              icon: const Icon(Icons.today_rounded),
            ),
            ButtonSegment(
              value: Frequency.weekly,
              label: Text(l10n.frequencyWeekly),
              icon: const Icon(Icons.date_range_rounded),
            ),
          ],
          selected: {vm.frequency},
          onSelectionChanged: (value) => vm.setFrequency(value.first),
        ),
        const SizedBox(height: 20),
        if (vm.frequency == Frequency.daily)
          const _DailyTimes()
        else
          const _WeeklyTimes(),
      ],
    );
  }
}

Future<int?> _pickMinutes(BuildContext context, int? current) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: current == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : TimeOfDay(hour: current ~/ 60, minute: current % 60),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.minutes,
    required this.auto,
    required this.onTap,
  });

  final String label;
  final int? minutes;
  final bool auto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutes = this.minutes;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.alarm_rounded),
        title: Text(label),
        subtitle: auto ? Text(l10n.autoFilledTime) : null,
        trailing: Text(
          minutes == null
              ? l10n.chooseTime
              : context.formatTimeOfDay(
                  TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
                ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: minutes == null
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DailyTimes extends StatelessWidget {
  const _DailyTimes();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<MedicationFormViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.timesPerDayLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (var n = 1; n <= MedicationFormViewModel.maxTimesPerDay; n++)
              ChoiceChip(
                label: Text('$n'),
                selected: vm.timesPerDay == n,
                onSelected: (_) => vm.setTimesPerDay(n),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < vm.timesPerDay; i++) ...[
          _TimeTile(
            label: l10n.doseNumber(i + 1),
            minutes: vm.dailyTimes[i],
            auto: vm.isDailyAuto(i),
            onTap: () async {
              final minutes = await _pickMinutes(context, vm.dailyTimes[i]);
              if (minutes != null) vm.setDailyTime(i, minutes);
            },
          ),
          const SizedBox(height: 8),
        ],
        if (vm.timesPerDay > 1)
          Text(l10n.autoFillHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WeeklyTimes extends StatelessWidget {
  const _WeeklyTimes();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<MedicationFormViewModel>();
    // Saturday first, as in the Saudi week.
    const order = [6, 7, 1, 2, 3, 4, 5];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.weekdaysLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final day in order)
              FilterChip(
                label: Text(context.weekdayName(day)),
                selected: vm.weekdays.contains(day),
                onSelected: (_) {
                  if (!vm.toggleWeekday(day)) {
                    showMessage(context, l10n.maxWeekdaysReached, error: true);
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final day in vm.weekdays) ...[
          _TimeTile(
            label: context.weekdayName(day),
            minutes: vm.weeklyTime(day),
            auto: vm.isWeeklyAuto(day),
            onTap: () async {
              final minutes = await _pickMinutes(context, vm.weeklyTime(day));
              if (minutes != null) vm.setWeeklyTime(day, minutes);
            },
          ),
          const SizedBox(height: 8),
        ],
        if (vm.weekdays.length > 1)
          OutlinedButton.icon(
            onPressed: () {
              if (!vm.applyFirstTimeToAll()) {
                showMessage(context, l10n.setFirstDayTimeFirst, error: true);
              }
            },
            icon: const Icon(Icons.copy_all_rounded),
            label: Text(l10n.applySameTime),
          ),
      ],
    );
  }
}
