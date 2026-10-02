import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';

class InviteRequest {
  const InviteRequest({
    required this.email,
    required this.name,
    this.relationship,
  });

  final String email;
  final String name;
  final String? relationship;
}

/// Asks for the email of the person to look after (they must already have
/// a Mudhkir account) plus how to show them in the list.
class InviteDialog extends StatefulWidget {
  const InviteDialog({
    this.initialName,
    this.initialRelationship,
    this.editOnly = false,
    super.key,
  });

  final String? initialName;
  final String? initialRelationship;

  /// Rename an existing companion instead of inviting a new one.
  final bool editOnly;

  @override
  State<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  late final _name = TextEditingController(text: widget.initialName);
  late final _relationship = TextEditingController(
    text: widget.initialRelationship,
  );

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _relationship.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.editOnly ? l10n.editCompanion : l10n.addCompanion),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.editOnly) ...[
                Text(l10n.inviteExplanation),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => Validators.email(v, l10n),
                  decoration: InputDecoration(
                    labelText: l10n.companionEmailLabel,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.companionNameLabel),
                validator: widget.editOnly
                    ? (v) => Validators.required(v, l10n)
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _relationship,
                decoration: InputDecoration(
                  labelText: l10n.relationshipLabel,
                  hintText: l10n.relationshipHint,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              InviteRequest(
                email: _email.text.trim(),
                name: _name.text.trim(),
                relationship: _relationship.text.trim().isEmpty
                    ? null
                    : _relationship.text.trim(),
              ),
            );
          },
          child: Text(widget.editOnly ? l10n.actionSave : l10n.sendInvite),
        ),
      ],
    );
  }
}
