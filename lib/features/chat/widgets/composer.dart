/// The chat composer.
///
/// Carries the desktop composer's controls at phone scale: approval mode,
/// attachment, model override, context meter and send. Access mode and model
/// live here as local state for the UI-only build; both are one callback away
/// from persisting to the backend.
library;

import 'package:flutter/material.dart';
import '../../../core/message_reference.dart';
import 'reference_preview.dart';
import 'package:flutter/services.dart';

import '../../../design/appearance.dart';
import '../../../design/glass.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';

enum ApprovalMode {
  approvals('Request approvals', Icons.verified_user_outlined),
  fullAccess('Full access', Icons.shield_outlined);

  const ApprovalMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class MukaiComposer extends StatefulWidget {
  const MukaiComposer({
    super.key,
    required this.botName,
    required this.onSend,
    required this.onStop,
    required this.responding,
    this.enabled = true,
    this.autofocus = false,
    this.initialDraft = '',
    this.onDraftChanged,
    this.onSubmit,
    this.allowQueue = false,
    this.submitting = false,
    this.reference,
    this.onRemoveReference,
    this.accessMode,
    this.onModeChanged,
    this.onModelChanged,
    this.onAttach,
    this.attachments = const [],
    this.onRemoveAttachment,
    this.modelLabel = 'Workspace default',
    this.modelOptions = const <String>[
      'Workspace default',
      'Claude Opus 4.5',
      'Claude Sonnet 4.5',
      'GPT-5.1',
      'gpt-5.1-codex',
    ],
  });

  final bool enabled;
  final bool autofocus;
  final String initialDraft;
  final ValueChanged<String>? onDraftChanged;
  final Future<void> Function(String)? onSubmit;
  final bool allowQueue;
  final bool submitting;
  final MessageReference? reference;
  final VoidCallback? onRemoveReference;
  final String? accessMode;
  final ValueChanged<String>? onModeChanged;
  final ValueChanged<String>? onModelChanged;
  final VoidCallback? onAttach;
  final List<Map<String, dynamic>> attachments;
  final ValueChanged<String>? onRemoveAttachment;
  final String botName;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final bool responding;
  final String modelLabel;
  final List<String> modelOptions;

  @override
  State<MukaiComposer> createState() => _MukaiComposerState();
}

class _MukaiComposerState extends State<MukaiComposer> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  ApprovalMode _mode = ApprovalMode.fullAccess;
  late String _model = widget.modelLabel;

  @override
  void initState() {
    super.initState();
    _input.text = widget.initialDraft;
    _input.addListener(_onTextChanged);
    _focus.addListener(_onTextChanged);
    if (widget.autofocus) {
      // A cold start can mount this composer while the conversation is
      // still loading (so TextField's one-shot autofocus is swallowed by
      // the disabled field). Ask again once the frame has settled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled && !_focus.hasFocus) {
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _input.removeListener(_onTextChanged);
    _focus.removeListener(_onTextChanged);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onDraftChanged?.call(_input.text);
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant MukaiComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reference != null && widget.reference != oldWidget.reference) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    if (widget.autofocus && widget.enabled && !oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _focus.requestFocus();
      });
    }
    if (_input.text.isEmpty &&
        oldWidget.initialDraft != widget.initialDraft &&
        widget.initialDraft.isNotEmpty) {
      _input.text = widget.initialDraft;
    }
  }

  bool get _canSend =>
      widget.enabled &&
      !widget.submitting &&
      (_input.text.trim().isNotEmpty || widget.attachments.isNotEmpty) &&
      (!widget.responding || widget.allowQueue);

  void _send() {
    if (!_canSend) return;
    final String text = _input.text;
    _input.clear();
    Haptics.success();
    if (widget.onSubmit != null) {
      widget.onSubmit!(text);
    } else {
      widget.onSend(text);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text?.isNotEmpty ?? false) {
      final selection = _input.selection;
      final start = selection.isValid ? selection.start : _input.text.length;
      final end = selection.isValid ? selection.end : start;
      _input.value = TextEditingValue(
        text: _input.text.replaceRange(start, end, data!.text!),
        selection: TextSelection.collapsed(offset: start + data.text!.length),
      );
      _focus.requestFocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copy some text first, then paste it here.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MukaiColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: MukaiGlassProbe(
        builder: (BuildContext context, bool glass, Widget? _) =>
            MukaiGlassSurface(
              cornerRadius: 26,
              child: AnimatedContainer(
                duration: MukaiMotion.fast,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  // On glass the material itself supplies depth and edges.
                  color: glass ? null : colors.card,
                  borderRadius: BorderRadius.circular(26),
                  border: glass
                      ? null
                      : Border.all(color: colors.hairlineStrong),
                  boxShadow: glass
                      ? null
                      : MukaiShadows.card(colors.brightness),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (widget.reference case final reference?)
                      ReferencePreview(
                        reference: reference,
                        onRemove: widget.onRemoveReference,
                      ),
                    if (widget.attachments.isNotEmpty)
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final file in widget.attachments)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InputChip(
                                  label: Text(
                                    file['name'] as String? ?? 'File',
                                  ),
                                  onDeleted: () => widget.onRemoveAttachment
                                      ?.call(file['id'] as String),
                                ),
                              ),
                          ],
                        ),
                      ),
                    TextField(
                      enabled: widget.enabled,
                      autofocus: widget.autofocus || widget.reference != null,
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      style: text.bodyLarge?.copyWith(
                        color: colors.ink,
                        height: 1.45,
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(2, 14, 8, 14),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: widget.responding && widget.allowQueue
                            ? 'Add a follow-up…'
                            : 'Message ${widget.botName}…',
                        hintStyle: text.bodyLarge?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        MukaiIconButton(
                          icon: Icons.add_rounded,
                          tooltip: widget.onAttach == null
                              ? 'Paste text'
                              : 'Add attachment',
                          size: 44,
                          border: false,
                          onTap: widget.onAttach ?? _paste,
                        ),
                        _ModePicker(
                          mode: widget.accessMode == null
                              ? _mode
                              : widget.accessMode == 'ask-for-approval'
                              ? ApprovalMode.approvals
                              : ApprovalMode.fullAccess,
                          onChanged: (mode) {
                            if (widget.accessMode != null) {
                              widget.onModeChanged?.call(
                                mode == ApprovalMode.approvals
                                    ? 'ask-for-approval'
                                    : 'full-access',
                              );
                            } else {
                              setState(() => _mode = mode);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _ModelPicker(
                            model: widget.onModelChanged == null
                                ? _model
                                : widget.modelLabel,
                            options: widget.modelOptions,
                            onChanged: (model) {
                              if (widget.onModelChanged != null) {
                                widget.onModelChanged!(model);
                              } else {
                                setState(() => _model = model);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.responding && widget.allowQueue && _canSend)
                          MukaiIconButton(
                            icon: Icons.playlist_add_rounded,
                            tooltip: 'Queue follow-up',
                            border: false,
                            onTap: _send,
                          ),
                        _SendButton(
                          canSend: _canSend,
                          responding: widget.responding,
                          onSend: _send,
                          onStop: widget.onStop,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});
  final ApprovalMode mode;
  final ValueChanged<ApprovalMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final bool full = mode == ApprovalMode.fullAccess;
    final Color tint = full ? const Color(0xFFCA7331) : colors.textSecondary;

    return MenuAnchor(
      menuChildren: <Widget>[
        for (final ApprovalMode option in ApprovalMode.values)
          MenuItemButton(
            leadingIcon: Icon(option.icon, size: 16),
            onPressed: () => onChanged(option),
            child: Text(option.label),
          ),
      ],
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
            return PressableScale(
              scale: 0.94,
              onTap: () {
                Haptics.select();
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              child: Tooltip(
                message: mode.label,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(mode.icon, size: 19, color: tint),
                ),
              ),
            );
          },
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({
    required this.model,
    required this.options,
    required this.onChanged,
  });

  final String model;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  bool _open = false;

  String _shorten(String value) =>
      value.length <= 16 ? value : '${value.substring(0, 15)}…';

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    final String model = widget.model;
    return MukaiGlassMenuButton(
      tooltip: model,
      width: 220,
      expandWidth: true,
      up: true,
      onOpenChanged: (open) {
        if (mounted) setState(() => _open = open);
      },
      icon: IgnorePointer(
        ignoring: _open,
        // The panel unfurls from the chip, so only the chip steps aside —
        // the rest of the composer stays put.
        child: AnimatedScale(
          scale: _open ? .8 : 1,
          duration: MukaiMotion.fast,
          curve: MukaiMotion.curve,
          child: AnimatedOpacity(
            opacity: _open ? 0 : 1,
            duration: MukaiMotion.fast,
            curve: MukaiMotion.curve,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      model == 'Workspace default'
                          ? 'Default model'
                          : _shorten(model),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 14,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      items: [
        for (final String option in widget.options)
          MukaiGlassMenuItem(
            label: option,
            selected: option == model,
            onTap: () => widget.onChanged(option),
          ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.canSend,
    required this.responding,
    required this.onSend,
    required this.onStop,
  });

  final bool canSend;
  final bool responding;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final MukaiColors colors = MukaiColors.of(context);
    return Tooltip(
      message: responding ? 'Stop response' : 'Send message',
      child: Semantics(
        button: true,
        enabled: responding || canSend,
        label: responding ? 'Stop response' : 'Send message',
        child: PressableScale(
          scale: 0.9,
          enableHaptics: false,
          onTap: !responding && !canSend
              ? null
              : () {
                  Haptics.tap();
                  if (responding) {
                    onStop();
                  } else if (canSend) {
                    onSend();
                  }
                },
          child: AnimatedContainer(
            duration: MukaiMotion.fast,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: responding || canSend
                  ? colors.accentColor
                  : colors.accentSoft,
              shape: BoxShape.circle,
              boxShadow: canSend || responding
                  ? MukaiShadows.card(colors.brightness)
                  : null,
            ),
            child: AnimatedSwitcher(
              duration: MukaiMotion.fast,
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                responding ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                key: ValueKey<bool>(responding),
                size: 19,
                color: responding || canSend
                    ? colors.textOnAccent
                    : colors.accentInk.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
