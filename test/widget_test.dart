// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:face_attendance/main.dart';

void main() {
  testWidgets('App boots to splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceAttendanceApp());
    expect(find.text('SmartWorker'), findsOneWidget);
    expect(find.text('Face Attendance System'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
