import 'package:denial_desktop/src/core/shell_secure_stage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Attaching or detaching the keyboard cover switches the presentation while
// the session may be locked. The scene of the presentation switched to
// mounts a secure stage of its own: it must start under the lock, showing
// nothing of the session for a single frame, and must not unlock.
//
// The stage translates with Denial's own engine layer, which upstream
// flutter_tester cannot paint; it is built and laid out here, not painted.
void main() {
  testWidgets('the presentation switched to starts under the lock', (
    tester,
  ) async {
    var unlocked = 0;
    final progress = <double>[];
    const notPainted = Key('not painted');
    Widget stage(String presentation) => Offstage(
      key: notPainted,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: UnlockTransitionHost(
          key: ValueKey<String>(presentation),
          locked: true,
          lockLayerVisible: true,
          lockFrameToken: 7,
          onUnlockComplete: () => unlocked += 1,
          backdrop: const SizedBox.expand(),
          scene: Text('$presentation apps'),
          chrome: const SizedBox.shrink(),
          lockLayerBuilder: (unlock) {
            progress.add(unlock.value);
            return const Text('lock');
          },
        ),
      ),
    );
    // Whether the stage itself keeps the scene from being painted.
    bool hidden(String scene) => tester
        .widgetList<Offstage>(
          find.ancestor(
            of: find.text(scene, skipOffstage: false),
            matching: find.byType(Offstage, skipOffstage: false),
          ),
        )
        .any((offstage) => offstage.key != notPainted && offstage.offstage);

    await tester.pumpWidget(stage('tablet'));
    expect(find.text('lock', skipOffstage: false), findsOneWidget);
    expect(hidden('tablet apps'), isTrue);

    // The cover attached: the desktop's scene replaces the tablet's.
    progress.clear();
    await tester.pumpWidget(stage('desktop'));
    expect(progress, isNotEmpty);
    expect(progress, everyElement(0.0));
    expect(find.text('lock', skipOffstage: false), findsOneWidget);
    expect(hidden('desktop apps'), isTrue);

    await tester.pumpAndSettle();
    expect(hidden('desktop apps'), isTrue);
    expect(progress.last, 0.0);
    expect(unlocked, 0);
  });
}
