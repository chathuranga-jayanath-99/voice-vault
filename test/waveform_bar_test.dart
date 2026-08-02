import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_vault/widgets/waveform_bar.dart';

void main() {
  Widget _wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
      );

  group('WaveformBar', () {
    testWidgets('renders nothing when peaks are empty', (tester) async {
      await tester.pumpWidget(_wrap(WaveformBar(peaks: const [], progress: 0)));
      expect(find.byType(WaveformBar), findsOneWidget);
      // ClipRRect should not be present when peaks are empty.
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('renders a row of bars for non-empty peaks', (tester) async {
      await tester.pumpWidget(
        _wrap(WaveformBar(
          peaks: List<double>.generate(40, (i) => (i % 10) / 10.0),
          progress: 0.5,
        )),
      );
      // Bars are drawn as small Containers inside Rows.
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('does not crash at progress edges 0 and 1', (tester) async {
      for (final p in <double>[0.0, 1.0, 0.3, 0.7]) {
        await tester.pumpWidget(
          _wrap(WaveformBar(
            peaks: List<double>.generate(20, (i) => 0.5),
            progress: p,
          )),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}