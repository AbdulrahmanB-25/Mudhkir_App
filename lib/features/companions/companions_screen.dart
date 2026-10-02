import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/companion_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/companion_link.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import 'invite_dialog.dart';

/// People the user looks after, and people who look after the user.
class CompanionsScreen extends StatelessWidget {
  const CompanionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.watch<AuthRepository>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabCompanions)),
      floatingActionButton: auth.isSignedIn
          ? FloatingActionButton.extended(
              onPressed: () => _invite(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(l10n.addCompanion),
            )
          : null,
      body: !auth.cloudAvailable
          ? Center(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: l10n.companionsNeedCloudTitle,
                message: l10n.companionsNeedCloudMessage,
              ),
            )
          : !auth.isSignedIn
          ? Center(
              child: EmptyState(
                icon: Icons.family_restroom_rounded,
                title: l10n.companionsSignInTitle,
                message: l10n.companionsSignInMessage,
                action: FilledButton(
                  onPressed: () => context.push(Routes.login),
                  child: Text(l10n.signIn),
                ),
              ),
            )
          : _LinksList(userId: auth.ownerId),
    );
  }

  Future<void> _invite(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    final companions = context.read<CompanionRepository>();
    final profile = await context.read<ProfileRepository>().get(auth.ownerId);
    if (!context.mounted) return;
    final request = await showDialog<InviteRequest>(
      context: context,
      builder: (_) => const InviteDialog(),
    );
    if (request == null || !context.mounted) return;
    try {
      final result = await companions.invite(
        caregiverId: auth.ownerId,
        caregiverName: profile?.name ?? auth.displayName ?? auth.email ?? '',
        email: request.email,
        displayName: request.name,
        relationship: request.relationship,
      );
      if (!context.mounted) return;
      switch (result) {
        case InviteResult.sent:
          showMessage(context, l10n.inviteSent);
          context.read<SyncService>().schedule();
        case InviteResult.notFound:
          showMessage(context, l10n.inviteNotFound, error: true);
        case InviteResult.isSelf:
          showMessage(context, l10n.inviteSelf, error: true);
        case InviteResult.alreadyLinked:
          showMessage(context, l10n.inviteAlreadyLinked, error: true);
      }
    } catch (_) {
      if (context.mounted) showMessage(context, l10n.errorNetwork, error: true);
    }
  }
}

class _LinksList extends StatelessWidget {
  const _LinksList({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final companions = context.read<CompanionRepository>();

    return RefreshIndicator(
      onRefresh: context.read<SyncService>().syncNow,
      child: WatchBuilder<List<CompanionLink>>(
        streamKey: userId,
        create: () => companions.watchLinks(userId),
        builder: (context, snapshot) {
          final links = snapshot.data;
          if (links == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final caring = links
              .where((l) => l.caregiverId == userId && l.isAccepted)
              .toList();
          final sent = links
              .where((l) => l.caregiverId == userId && !l.isAccepted)
              .toList();
          final requests = links
              .where((l) => l.patientId == userId && !l.isAccepted)
              .toList();
          final followers = links
              .where((l) => l.patientId == userId && l.isAccepted)
              .toList();

          if (links.isEmpty) {
            return ListView(
              children: [
                EmptyState(
                  icon: Icons.family_restroom_rounded,
                  title: l10n.noCompanionsTitle,
                  message: l10n.noCompanionsMessage,
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              if (requests.isNotEmpty) ...[
                SectionTitle(l10n.incomingRequests),
                for (final link in requests)
                  _RequestCard(link: link, companions: companions),
              ],
              if (caring.isNotEmpty) ...[
                SectionTitle(l10n.peopleICareFor),
                for (final link in caring)
                  _LinkTile(
                    icon: Icons.favorite_rounded,
                    title: link.patientName ?? link.patientEmail ?? '',
                    subtitle: link.relationship,
                    onTap: () => context.push(Routes.companion(link.patientId)),
                  ),
              ],
              if (sent.isNotEmpty) ...[
                SectionTitle(l10n.invitesSent),
                for (final link in sent)
                  _LinkTile(
                    icon: Icons.hourglass_top_rounded,
                    title: link.patientName ?? link.patientEmail ?? '',
                    subtitle: l10n.waitingForAcceptance,
                    trailing: IconButton(
                      tooltip: l10n.cancelInvite,
                      onPressed: () => companions.remove(link.id),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
              ],
              if (followers.isNotEmpty) ...[
                SectionTitle(l10n.peopleCaringForMe),
                for (final link in followers)
                  _LinkTile(
                    icon: Icons.visibility_rounded,
                    title: link.caregiverName ?? '',
                    subtitle: l10n.canSeeYourMedications,
                    trailing: IconButton(
                      tooltip: l10n.stopSharing,
                      onPressed: () async {
                        if (await confirm(
                          context,
                          title: l10n.stopSharing,
                          message: l10n.stopSharingConfirm(
                            link.caregiverName ?? '',
                          ),
                          confirmLabel: l10n.stopSharing,
                          destructive: true,
                        )) {
                          await companions.remove(link.id);
                        }
                      },
                      icon: const Icon(Icons.link_off_rounded),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing:
              trailing ??
              (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.link, required this.companions});

  final CompanionLink link;
  final CompanionRepository companions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.requestMessage(link.caregiverName ?? ''),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(l10n.requestExplanation),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await companions.accept(link.id);
                        if (context.mounted) {
                          context.read<SyncService>().schedule();
                        }
                      },
                      child: Text(l10n.actionAccept),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => companions.remove(link.id),
                      child: Text(l10n.actionDecline),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
