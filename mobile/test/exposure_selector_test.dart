import 'package:flutter_test/flutter_test.dart';
import 'package:radiobuddy/exposure_selector.dart';

void main() {
  test('selectExposureFromProtocol matches size/grid/sid', () {
    final protocol = <String, Object?>{
      'recommendations': [
        {
          'inputs': {
            'projection': 'chest_pa_erect',
            'size_class': 'average',
            'grid': true,
            'sid_cm': 180,
          },
          'output': {
            'kvp': 120,
            'mas': 1.6,
            'notes': 'ok',
          },
        },
        {
          'inputs': {
            'projection': 'chest_pa_erect',
            'size_class': 'average',
            'grid': false,
            'sid_cm': 180,
          },
          'output': {
            'kvp': 110,
            'mas': 1.2,
          },
        },
      ],
    };

    final selected = selectExposureFromProtocol(
      protocol,
      projectionId: 'chest_pa_erect',
      sizeClass: 'average',
      grid: true,
      sidCm: 180,
    );

    expect(selected, isNotNull);
    expect(selected!['kvp'], 120);
    expect(selected['mas'], 1.6);
  });
}
