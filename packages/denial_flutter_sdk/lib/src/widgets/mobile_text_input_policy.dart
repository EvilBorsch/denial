import 'package:flutter/widgets.dart';

/// Applies laptop-shell focus semantics to editable controls in mobile mode.
///
/// Flutter's default mobile action deliberately keeps an [EditableText]
/// focused after a touchscreen tap outside its tap region. Denial uses that
/// same tap to dismiss its system keyboard, so retaining focus would let the
/// next shell gesture reopen the keyboard. Field-to-field taps remain inside
/// the shared [TextFieldTapRegion] group and therefore never invoke this
/// action.
///
/// With [enabled] false (the desktop) the default stays. The widget keeps
/// its place in the tree either way, so switching between the tablet and
/// desktop presentations keeps the state of everything below it.
class MobileTextInputPolicy extends StatelessWidget {
  const MobileTextInputPolicy({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool enabled;

  static final Map<Type, Action<Intent>> _mobileActions =
      <Type, Action<Intent>>{
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      };

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: enabled ? _mobileActions : const <Type, Action<Intent>>{},
      child: child,
    );
  }
}
