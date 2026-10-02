import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../domain/models/dose.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/medication.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import '../shared/dose_actions.dart';
import '../shared/dose_status.dart';
import '../shared/formatters.dart';
import 'medication_detail_view_model.dart';

class MedicationDetailScreen extends StatelessWidget {
  const MedicationDetailScreen({
    required this.medicationId,
    this.doseAt,
    super.key,
  });

  final String medicationId;
  final DateTime? doseAt;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MedicationDetailViewModel(
        medicationId: medicationId,
        doseAt: doseAt,
        medications: context.read<MedicationRepository>(),
        logs: context.read<DoseLogRepository>(),
      ),
      child: const _DetailView(),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<MedicationDetailViewModel>();
    final medication = vm.medication;

    if (vm.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (medication == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: l10n.medicationNotFound,
        ),
      );
    }

    final dose = vm.dose;
    final today = LocalDate.fromDateTime(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(medication.name),
        actions: [
          IconButton(
            tooltip: l10n.editMedication,
            onPressed: () => context.push(Routes.editMedication(medication.id)),
            icon: const Icon(Icons.edit_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _onMenu(context, vm, value),
            itemBuilder: (context) => [
              if (medication.isEnded)
                PopupMenuItem(
                  value: 'resume',
                  child: Text(l10n.resumeMedication),
                )
              else
                PopupMenuItem(value: 'end', child: Text(l10n.endMedication)),
              PopupMenuItem(
                value: 'delete',
                child: Text(l10n.deleteMedication),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(medication: medication),
          if (dose != null) ...[
            const SizedBox(height: 16),
            _DoseCard(dose: dose),
          ],
          if (medication.isFinishedOn(today)) ...[
            const SizedBox(height: 12),
            Card(
              color: AppColors.muted.withValues(alpha: 0.15),
              child: ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: Text(l10n.medicationFinished),
              ),
            ),
          ],
          SectionTitle(l10n.scheduleTitle),
          _ScheduleCard(medication: medication),
          SectionTitle(
            l10n.historyTitle,
            trailing: vm.adherence == null
                ? null
                : Text(l10n.adherence((vm.adherence! * 100).round())),
          ),
          if (vm.history.isEmpty)
            EmptyState(icon: Icons.history_rounded, title: l10n.noHistory)
          else
            Card(
              child: Column(
                children: [for (final log in vm.history) _HistoryRow(log: log)],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    MedicationDetailViewModel vm,
    String value,
  ) async {
    final l10n = AppLocalizations.of(context);
    switch (value) {
      case 'end':
        if (await confirm(
          context,
          title: l10n.endMedication,
          message: l10n.endMedicationConfirm,
          confirmLabel: l10n.endMedication,
        )) {
          await vm.end();
        }
      case 'resume':
        await vm.resume();
      case 'delete':
        if (await confirm(
          context,
          title: l10n.deleteMedication,
          message: l10n.deleteMedicationConfirm,
          confirmLabel: l10n.actionDelete,
          destructive: true,
        )) {
          await vm.delete();
          if (context.mounted) {
            showMessage(context, l10n.medicationDeleted);
            context.pop();
          }
        }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.medication});

  final Medication medication;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = medication.imagePath;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (path != null && File(path).existsSync())
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.file(File(path), fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(medication.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  context.dosageText(medication),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (medication.notes != null) ...[
                  const SizedBox(height: 8),
                  Text(medication.notes!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose});

  final DoseInstance dose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = DoseActions.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.doseAt(context.formatDateTime(dose.effectiveAt)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DoseStatusChip(status: dose.status),
              ],
            ),
            const SizedBox(height: 14),
            if (!dose.isDone) ...[
              FilledButton.icon(
                onPressed: () async {
                  await actions.take(dose);
                  if (context.mounted) {
                    showMessage(context, l10n.doseMarkedTaken);
                  }
                },
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.actionTake),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await actions.skip(dose);
                        if (context.mounted) {
                          showMessage(context, l10n.doseMarkedSkipped);
                        }
                      },
                      child: Text(l10n.actionSkip),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final time = await pickRescheduleTime(context, dose);
                        if (time == null) return;
                        await actions.reschedule(dose, time);
                        if (context.mounted) {
                          showMessage(context, l10n.doseRescheduled);
                        }
                      },
                      child: Text(l10n.actionReschedule),
                    ),
                  ),
                ],
              ),
            ] else
              OutlinedButton.icon(
                onPressed: () => actions.undo(dose),
                icon: const Icon(Icons.undo_rounded),
                label: Text(l10n.actionUndo),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.medication});

  final Medication medication;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final end = medication.endDate;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.repeat_rounded),
            title: Text(
              medication.frequency == Frequency.daily
                  ? l10n.frequencyDaily
                  : l10n.frequencyWeekly,
            ),
            subtitle: Text(context.scheduleSummary(medication)),
          ),
          ListTile(
            leading: const Icon(Icons.alarm_rounded),
            title: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in medication.times)
                  Chip(
                    label: Text(
                      t.weekday == null
                          ? context.formatDoseTime(t)
                          : '${context.weekdayName(t.weekday!, short: true)} ${context.formatDoseTime(t)}',
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_rounded),
            title: Text(
              end == null
                  ? l10n.fromDate(context.formatLocalDate(medication.startDate))
                  : l10n.fromToDate(
                      context.formatLocalDate(medication.startDate),
                      context.formatLocalDate(end),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.log});

  final DoseLog log;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = switch (log.status) {
      DoseLogStatus.taken => DoseStatus.taken,
      DoseLogStatus.skipped => DoseStatus.skipped,
      DoseLogStatus.rescheduled => DoseStatus.upcoming,
    };
    return ListTile(
      leading: Icon(status.icon, color: status.color(context)),
      title: Text(context.formatDateTime(log.scheduledAt)),
      subtitle: Text(
        log.status == DoseLogStatus.rescheduled
            ? l10n.rescheduledTo(context.formatTime(log.rescheduledTo!))
            : l10n.recordedAt(context.formatTime(log.actedAt)),
      ),
      trailing: log.status == DoseLogStatus.rescheduled
          ? null
          : DoseStatusChip(status: status),
    );
  }
}
