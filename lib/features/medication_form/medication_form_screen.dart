import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../data/services/image_store.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import 'medication_form_view_model.dart';
import 'steps/dates_step.dart';
import 'steps/dosage_step.dart';
import 'steps/name_photo_step.dart';

/// Add or edit a medication. [ownerId] lets a caregiver add a medication for
/// someone they look after; [medicationId] switches to edit mode.
class MedicationFormScreen extends StatelessWidget {
  const MedicationFormScreen({this.ownerId, this.medicationId, super.key});

  final String? ownerId;
  final String? medicationId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MedicationFormViewModel(
        ownerId: ownerId ?? context.read<AuthRepository>().ownerId,
        medicationId: medicationId,
        repository: context.read<MedicationRepository>(),
        images: context.read<ImageStore>(),
      ),
      child: const _FormView(),
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<MedicationFormViewModel>();

    if (vm.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (vm.notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: l10n.medicationNotFound,
        ),
      );
    }

    final steps = const [NamePhotoStep(), DosageStep(), DatesStep()];
    final titles = [l10n.stepNamePhoto, l10n.stepDosage, l10n.stepDates];

    return PopScope(
      canPop: vm.step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) vm.back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(vm.isEditing ? l10n.editMedication : l10n.addMedication),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  Text(
                    l10n.stepOf(
                      vm.step + 1,
                      MedicationFormViewModel.stepCount,
                      titles[vm.step],
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (vm.step + 1) / MedicationFormViewModel.stepCount,
                      minHeight: 6,
                      color: Theme.of(context).colorScheme.onPrimary,
                      backgroundColor: Theme.of(context).colorScheme.onPrimary
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(key: ValueKey(vm.step), child: steps[vm.step]),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                if (vm.step > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: vm.isSaving ? null : vm.back,
                      child: Text(l10n.actionBack),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: vm.isSaving ? null : () => _next(context, vm),
                    child: vm.isSaving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(
                            vm.isLastStep ? l10n.actionSave : l10n.actionNext,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _next(BuildContext context, MedicationFormViewModel vm) async {
    final l10n = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    if (!vm.isLastStep) {
      final issue = vm.next();
      if (issue != null) showMessage(context, issue.message(l10n), error: true);
      return;
    }
    final (saved, issue) = await vm.save();
    if (!context.mounted) return;
    if (issue != null) {
      showMessage(context, issue.message(l10n), error: true);
      return;
    }
    if (saved != null) {
      showMessage(
        context,
        vm.isEditing ? l10n.medicationUpdated : l10n.medicationAdded,
      );
      context.pop();
    }
  }
}

extension FormIssueMessage on FormIssue {
  String message(AppLocalizations l10n) => switch (this) {
    FormIssue.nameRequired => l10n.issueNameRequired,
    FormIssue.dosageRequired => l10n.issueDosageRequired,
    FormIssue.timesRequired => l10n.issueTimesRequired,
    FormIssue.weekdaysRequired => l10n.issueWeekdaysRequired,
    FormIssue.endBeforeStart => l10n.issueEndBeforeStart,
  };
}
