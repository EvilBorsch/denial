part of 'lock_screen_layer.dart';

class _LockAuthenticationPanel extends StatelessWidget {
  const _LockAuthenticationPanel({
    required this.desktop,
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onBegin,
    required this.onCancel,
    required this.onSwitchCredential,
    required this.usingPin,
    this.onRequestKeyboard,
  });

  final bool desktop;
  final AuthenticationState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onBegin;
  final VoidCallback onCancel;

  /// Offered only when a PIN is set: switches between PIN and password.
  final VoidCallback? onSwitchCredential;
  final bool usingPin;

  /// Mobile: a tap on the password field focuses it and brings the software
  /// keyboard up.
  final VoidCallback? onRequestKeyboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prompt = state.prompt;
    final pin = prompt?.isPin ?? false;
    final message =
        state.resultMessage ??
        state.statusMessage ??
        (pin ? l10n.lockEnterPin : prompt?.message) ??
        (state.busy ? l10n.lockWaitingForAuthentication : null);
    final error =
        state.resultIsError || prompt?.style == AuthenticationPromptStyle.error;
    final canRespond =
        state.available && state.busy && (prompt?.requiresResponse ?? false);
    final canBegin =
        state.available && state.locked && !state.busy && !state.rateLimited;
    final cooldownSeconds = (state.cooldown.inMilliseconds / 1000).ceil().clamp(
      1,
      30,
    );
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final size = MediaQuery.sizeOf(context);

    if (!desktop) {
      return _MobileLockAuthenticationPanel(
        state: state,
        controller: controller,
        focusNode: focusNode,
        onSubmit: onSubmit,
        onBegin: onBegin,
        onCancel: onCancel,
        onUsePin: onSwitchCredential,
        onRequestKeyboard: onRequestKeyboard ?? focusNode.requestFocus,
      );
    }

    return Positioned.fill(
      child: SafeArea(
        minimum: desktop
            ? EdgeInsets.fromLTRB(24, 24, math.max(32.0, size.width * 0.06), 24)
            : const EdgeInsets.fromLTRB(16, 16, 16, 30),
        child: Align(
          alignment: desktop ? Alignment.centerRight : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? math.min(460.0, size.width * 0.42) : 520,
              maxHeight: math.max(220.0, size.height * (desktop ? 0.86 : 0.72)),
            ),
            child: DecoratedBox(
              key: const ValueKey<String>('desktop-lock-authentication-panel'),
              decoration: _desktopLockPanelDecoration(
                theme: theme,
                accent: accent,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: FocusTraversalGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: accent.subtle,
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox(
                              width: 42,
                              height: 42,
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 21,
                                color: accent.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.lockUnlockDenial,
                                  style: ShellText.statusClock.copyWith(
                                    fontSize: 20,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  state.available
                                      ? l10n.lockPamVerified
                                      : l10n.lockAuthenticationUnavailable,
                                  style: ShellText.base.copyWith(
                                    color: context.shellColors.textTertiary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (message != null && message.isNotEmpty) ...[
                        const SizedBox(height: 15),
                        Semantics(
                          liveRegion: true,
                          label: message,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: error
                                  ? context.shellColors.performanceBad
                                        .withValues(alpha: 0.14)
                                  : accent.subtle,
                              borderRadius: context.shellTheme.borderRadius(14),
                              border: Border.all(
                                color: error
                                    ? context.shellColors.performanceBad
                                          .withValues(alpha: 0.40)
                                    : accent.outline,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 10,
                              ),
                              child: Text(
                                message,
                                style: ShellText.base.copyWith(
                                  color: error
                                      ? context.shellColors.performanceBad
                                      : context.shellColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (state.rateLimited) ...[
                        const SizedBox(height: 10),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            l10n.lockRetryInSeconds(cooldownSeconds),
                            textAlign: TextAlign.center,
                            style: ShellText.base.copyWith(
                              color: context.shellColors.performanceWarning,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (canRespond) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          label: pin
                              ? l10n.lockPinObscured
                              : prompt!.obscure
                              ? l10n.lockPasswordObscured
                              : l10n.lockAuthenticationResponse,
                          textField: true,
                          obscured: prompt!.obscure,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.shellColors.surfaceContainerHigh,
                              borderRadius: context.shellTheme.borderRadius(16),
                              border: Border.all(
                                color: focusNode.hasFocus
                                    ? accent.primary
                                    : context.shellColors.hairline,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              child: EditableText(
                                controller: controller,
                                focusNode: focusNode,
                                style: context.shellTheme.text.base.copyWith(
                                  fontSize: 16,
                                  letterSpacing: pin
                                      ? 6
                                      : prompt.obscure
                                      ? 2.5
                                      : 0,
                                ),
                                cursorColor: accent.primary,
                                backgroundCursorColor:
                                    context.shellColors.textTertiary,
                                selectionColor: accent.selection,
                                obscureText: prompt.obscure,
                                obscuringCharacter: '•',
                                autocorrect: false,
                                enableSuggestions: false,
                                enableInteractiveSelection: false,
                                keyboardType: pin
                                    ? TextInputType.number
                                    : TextInputType.visiblePassword,
                                textInputAction: TextInputAction.done,
                                inputFormatters: _responseFormatters(
                                  pin: pin,
                                  pinLength: state.pinLength,
                                ),
                                // The last PIN digit submits, as on mobile.
                                onChanged: pin
                                    ? (text) {
                                        if (text.length == state.pinLength) {
                                          onSubmit();
                                        }
                                      }
                                    : null,
                                onSubmitted: (_) => onSubmit(),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: _LockActionButton(
                              label: l10n.commonCancel,
                              icon: Icons.close_rounded,
                              onPressed: onCancel,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _LockActionButton(
                              label: canRespond
                                  ? l10n.lockUnlock
                                  : state.busy
                                  ? l10n.lockAuthenticating
                                  : state.rateLimited
                                  ? l10n.lockPleaseWait
                                  : l10n.lockTryAgain,
                              icon: Icons.arrow_forward_rounded,
                              primary: true,
                              enabled: canRespond || canBegin,
                              onPressed: canRespond ? onSubmit : onBegin,
                            ),
                          ),
                        ],
                      ),
                      if (onSwitchCredential case final onSwitch?) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: _PinLink(
                            label: usingPin
                                ? l10n.lockUsePassword
                                : l10n.lockUsePin,
                            onPressed: onSwitch,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<TextInputFormatter> _responseFormatters({
  required bool pin,
  required int pinLength,
}) => pin
    ? [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(pinLength > 0 ? pinLength : 12),
      ]
    : [LengthLimitingTextInputFormatter(1024)];

class _MobileLockAuthenticationPanel extends ConsumerWidget {
  const _MobileLockAuthenticationPanel({
    required this.state,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onBegin,
    required this.onCancel,
    required this.onUsePin,
    required this.onRequestKeyboard,
  });

  final AuthenticationState state;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onBegin;
  final VoidCallback onCancel;

  /// Offered when a PIN is set; this panel only ever asks for the password.
  final VoidCallback? onUsePin;

  /// A tap anywhere on the field's row: focus and the software keyboard.
  final VoidCallback onRequestKeyboard;

  /// Space around the panel; the bottom is its distance from the screen's
  /// edge while the keyboard is down.
  static const EdgeInsets _margin = EdgeInsets.fromLTRB(18, 12, 18, 22);

  /// Between the panel and the keys while the keyboard is up.
  static const double _keyboardGap = 16;

  /// The field's row is one touch target, comfortably finger sized.
  static const double _fieldHeight = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final prompt = state.prompt;
    final error =
        state.resultIsError || prompt?.style == AuthenticationPromptStyle.error;
    final canRespond =
        state.available && state.busy && (prompt?.requiresResponse ?? false);
    final canBegin =
        state.available && state.locked && !state.busy && !state.rateLimited;
    final promptLabel = prompt?.message.trim();
    final message =
        state.resultMessage ??
        state.statusMessage ??
        (error ? promptLabel : null) ??
        (!canRespond && state.busy ? l10n.lockWaitingForAuthentication : null);
    final cooldownSeconds = (state.cooldown.inMilliseconds / 1000).ceil().clamp(
      1,
      30,
    );
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final (keyboardShown, shortcuts) = ref.watch(
      referenceShellProvider.select(
        (shell) => (shell.edgePanelVisible, shell.oskShortcuts),
      ),
    );
    // The panel rides above the keyboard (KeyboardClearance), so it must fit
    // in the room the keys leave, in either orientation.
    final keyboardHeight = ReferenceShellMetrics.edgePanelHeight(
      size,
      shortcuts: shortcuts,
    );
    final roomAboveKeyboard =
        size.height -
        keyboardHeight -
        _keyboardGap -
        math.max(padding.top, _margin.top);
    final maxHeight = math.max(
      180.0,
      math.min(size.height * 0.58, roomAboveKeyboard),
    );

    return Positioned.fill(
      child: SafeArea(
        minimum: _margin,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: KeyboardClearance(
            clearance: math.max(padding.bottom, _margin.bottom),
            gap: _keyboardGap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _MobileFace.isTablet(size) ? 560 : 480,
                maxHeight: maxHeight,
              ),
              child: DecoratedBox(
                key: const ValueKey<String>('mobile-lock-authentication-panel'),
                decoration: BoxDecoration(
                  color: context.shellColors.surfaceContainerLow,
                  borderRadius: context.shellTheme.borderRadius(24),
                  border: Border.all(color: context.shellColors.hairline),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 20),
                  child: FocusTraversalGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.lockUnlockDenial,
                                style: ShellText.base.copyWith(
                                  fontSize: 23,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.35,
                                ),
                              ),
                            ),
                            _MobileLockCancelButton(
                              label: l10n.commonCancel,
                              onPressed: onCancel,
                            ),
                          ],
                        ),
                        if (!state.available) ...[
                          const SizedBox(height: 7),
                          Text(
                            l10n.lockAuthenticationUnavailable,
                            style: ShellText.base.copyWith(
                              color: context.shellColors.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (message != null && message.isNotEmpty) ...[
                          const SizedBox(height: 11),
                          Semantics(
                            liveRegion: true,
                            label: message,
                            child: Text(
                              message,
                              style: ShellText.base.copyWith(
                                color: error
                                    ? context.shellColors.performanceBad
                                    : context.shellColors.textSecondary,
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: error
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                        if (state.rateLimited) ...[
                          const SizedBox(height: 10),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              l10n.lockRetryInSeconds(cooldownSeconds),
                              style: ShellText.base.copyWith(
                                color: context
                                    .shellColors
                                    .performanceWarning,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        if (canRespond) ...[
                          const SizedBox(height: 14),
                          Text(
                            (promptLabel == null ||
                                    promptLabel.isEmpty ||
                                    error)
                                ? l10n.lockAuthenticationResponse
                                : promptLabel,
                            style: ShellText.base.copyWith(
                              color: context.shellColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _MobileLockResponseField(
                            prompt: prompt!,
                            controller: controller,
                            focusNode: focusNode,
                            keyboardShown: keyboardShown,
                            height: _fieldHeight,
                            onSubmit: onSubmit,
                            onRequestKeyboard: onRequestKeyboard,
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          _MobileLockPrimaryButton(
                            label: state.busy
                                ? l10n.lockAuthenticating
                                : state.rateLimited
                                ? l10n.lockPleaseWait
                                : l10n.lockTryAgain,
                            enabled: canBegin,
                            onPressed: onBegin,
                          ),
                        ],
                        if (onUsePin case final onUsePin?) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: _PinLink(
                              label: l10n.lockUsePin,
                              onPressed: onUsePin,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The password field: the whole row takes the touch, focuses the field and
/// brings the software keyboard up, and it keeps focus until the panel
/// closes, so a keyboard cover always types into it.
class _MobileLockResponseField extends StatelessWidget {
  const _MobileLockResponseField({
    required this.prompt,
    required this.controller,
    required this.focusNode,
    required this.keyboardShown,
    required this.height,
    required this.onSubmit,
    required this.onRequestKeyboard,
  });

  final AuthenticationPrompt prompt;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool keyboardShown;
  final double height;
  final VoidCallback onSubmit;
  final VoidCallback onRequestKeyboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = ShellTheme.of(context).accentPalette;
    return Semantics(
      label: prompt.obscure
          ? l10n.lockPasswordObscured
          : l10n.lockAuthenticationResponse,
      textField: true,
      obscured: prompt.obscure,
      onTap: onRequestKeyboard,
      // Keys of the software keyboard belong to the same tap group, so
      // typing on them is never a tap outside the field.
      child: TextFieldTapRegion(
        child: GestureDetector(
          key: const ValueKey<String>('lock-authentication-field-row'),
          behavior: HitTestBehavior.opaque,
          onTap: onRequestKeyboard,
          child: AnimatedBuilder(
            animation: focusNode,
            builder: (context, child) => DecoratedBox(
              decoration: BoxDecoration(
                color: context.shellColors.background.withValues(alpha: 0.72),
                borderRadius: context.shellTheme.borderRadius(16),
                border: Border.all(
                  width: focusNode.hasFocus ? 2 : 1,
                  color: focusNode.hasFocus
                      ? accent.primary
                      : context.shellColors.hairline,
                ),
              ),
              child: child,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: EditableText(
                        key: const ValueKey<String>(
                          'lock-authentication-field',
                        ),
                        controller: controller,
                        focusNode: focusNode,
                        style: context.shellTheme.text.base.copyWith(
                          fontSize: 20,
                          letterSpacing: prompt.obscure ? 2.6 : 0,
                        ),
                        cursorColor: accent.primary,
                        backgroundCursorColor: context.shellColors.textTertiary,
                        selectionColor: accent.selection,
                        obscureText: prompt.obscure,
                        obscuringCharacter: '•',
                        autocorrect: false,
                        enableSuggestions: false,
                        enableInteractiveSelection: false,
                        // The row handles every touch on the field.
                        rendererIgnoresPointer: true,
                        // A touch elsewhere on the lock screen, or between
                        // the keys, must not take the field's focus: a
                        // keyboard cover would then type into nothing.
                        onTapOutside: (_) {},
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(1024),
                        ],
                        onSubmitted: (_) => onSubmit(),
                      ),
                    ),
                    if (!keyboardShown) ...[
                      const SizedBox(width: 8),
                      ExcludeSemantics(
                        child: Icon(
                          Icons.keyboard_rounded,
                          size: 24,
                          color: context.shellColors.textTertiary,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    _MobileLockSubmitButton(
                      label: l10n.lockUnlock,
                      onPressed: onSubmit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileLockCancelButton extends StatelessWidget {
  const _MobileLockCancelButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        // A finger-sized target around the small label.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: ShellText.base.copyWith(
                  color: context.shellColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileLockSubmitButton extends StatelessWidget {
  const _MobileLockSubmitButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.primary,
            borderRadius: context.shellTheme.borderRadius(11),
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 22,
              color: accent.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileLockPrimaryButton extends StatelessWidget {
  const _MobileLockPrimaryButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: enabled ? accent.primary : accent.subtle,
            borderRadius: context.shellTheme.borderRadius(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: ShellText.base.copyWith(
                color: enabled
                    ? accent.onPrimary
                    : context.shellColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockActionButton extends StatefulWidget {
  const _LockActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool enabled;

  @override
  State<_LockActionButton> createState() => _LockActionButtonState();
}

class _LockActionButtonState extends State<_LockActionButton> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _highlighted;
    final accent = ShellTheme.of(context).accentPalette;
    final foreground = widget.enabled
        ? (widget.primary ? accent.onPrimary : context.shellColors.textPrimary)
        : context.shellColors.textTertiary.withValues(alpha: 0.55);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _highlighted = value),
        onShowHoverHighlight: (value) => setState(() => _highlighted = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) {
                widget.onPressed();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.tile,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.primary
                  ? (widget.enabled ? accent.primary : accent.subtle)
                  : (active
                        ? context.shellColors.surfaceContainerHighest
                        : context.shellColors.surfaceContainerHigh),
              borderRadius: context.shellTheme.borderRadius(16),
              border: Border.all(
                color: active
                    ? accent.primary
                    : context.shellColors.hairlineSoft,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 17, color: foreground),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.base.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
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
}

BoxDecoration _desktopLockPanelDecoration({
  required ShellThemeData theme,
  required ShellAccentPalette accent,
}) {
  return BoxDecoration(
    color: theme.panelColor(theme.colors.panelBackground),
    borderRadius: BorderRadius.circular(theme.panelRadius),
    border: Border.all(color: accent.outline),
  );
}

/// Independent feedback also appears before the password panel is opened.
class _LockFingerprintFeedback extends StatelessWidget {
  const _LockFingerprintFeedback({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    return Positioned(
      top: 76,
      left: 24,
      right: 24,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: visible
                  ? Semantics(
                      key: const ValueKey('fingerprint-rejected'),
                      liveRegion: true,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: context.shellTheme.borderRadius(16),
                          border: Border.all(
                            color: colors.performanceBad.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: Icon(
                                Icons.fingerprint_rounded,
                                color: colors.performanceBad,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                context.l10n.lockFingerprintNotRecognized,
                                style: ShellText.base.copyWith(
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
