import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/local_date.dart';
import '../../../domain/models/medication.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../medication_form_view_model.dart';

class DatesStep extends StatelessWidget {
  const DatesStep({super.key});

  Future<LocalDate?> _pickDate(
    BuildContext context,
    LocalDate initial, {
    LocalDate? first,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toDateTime(),
      firstDate: (first ?? LocalDate(initial.year - 1, 1, 1)).toDateTime(),
      lastDate: DateTime(initial.year + 5),
    );
    return picked == null ? null : LocalDate.fromDateTime(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<MedicationFormViewModel>();
    final theme = Theme.of(context);
    final end = vm.endDate;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.play_circle_outline_rounded),
            title: Text(l10n.startDateLabel),
            subtitle: Text(context.formatLocalDate(vm.startDate)),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: () async {
              final date = await _pickDate(context, vm.startDate);
              if (date != null) vm.setStartDate(date);
            },
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.stop_circle_outlined),
                title: Text(l10n.hasEndDate),
                value: end != null,
                onChanged: (on) =>
                    vm.setEndDate(on ? vm.startDate.addDays(6) : null),
              ),
              if (end != null)
                ListTile(
                  title: Text(l10n.endDateLabel),
                  subtitle: Text(context.formatLocalDate(end)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final date = await _pickDate(
                      context,
                      end,
                      first: vm.startDate,
                    );
                    if (date != null) vm.setEndDate(date);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: vm.notes,
          maxLines: 3,
          onChanged: vm.setNotes,
          decoration: InputDecoration(
            labelText: l10n.notesLabel,
            hintText: l10n.notesHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        Text(l10n.summaryTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow(icon: Icons.medication_rounded, text: vm.name),
                _SummaryRow(
                  icon: Icons.scale_rounded,
                  text:
                      '${vm.dosageAmount} ${l10n.dosageUnitName(vm.unit.name)}',
                ),
                _SummaryRow(
                  icon: Icons.alarm_rounded,
                  text: _timesText(context, vm),
                ),
                _SummaryRow(
                  icon: Icons.date_range_rounded,
                  text: end == null
                      ? l10n.fromDate(context.formatLocalDate(vm.startDate))
                      : l10n.fromToDate(
                          context.formatLocalDate(vm.startDate),
                          context.formatLocalDate(end),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _timesText(BuildContext context, MedicationFormViewModel vm) {
    final times = vm.doseTimes;
    if (vm.frequency == Frequency.daily) {
      return times
          .map(context.formatDoseTime)
          .join(AppLocalizations.of(context).listSeparator);
    }
    return times
        .map(
          (t) =>
              '${context.weekdayName(t.weekday!, short: true)} ${context.formatDoseTime(t)}',
        )
        .join(AppLocalizations.of(context).listSeparator);
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
