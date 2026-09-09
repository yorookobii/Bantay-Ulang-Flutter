import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'tapping screen hides navbar, scrolling down keeps it hidden, scrolling up reveals it',
      (tester) async {
    final isNavBarVisible = ValueNotifier<bool>(true);
    Offset? pointerDownPosition;
    DateTime? pointerDownTime;

    Widget testHarness() {
      return MaterialApp(
        home: Scaffold(
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              pointerDownPosition = event.position;
              pointerDownTime = DateTime.now();
            },
            onPointerUp: (event) {
              if (pointerDownPosition != null && pointerDownTime != null) {
                final distance =
                    (event.position - pointerDownPosition!).distance;
                final elapsed = DateTime.now().difference(pointerDownTime!);
                if (distance < 18 && elapsed.inMilliseconds < 600) {
                  isNavBarVisible.value = !isNavBarVisible.value;
                }
              }
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (notification.metrics.axis != Axis.vertical) return false;

                if (notification is UserScrollNotification) {
                  if (notification.direction == ScrollDirection.reverse) {
                    if (isNavBarVisible.value) isNavBarVisible.value = false;
                  } else if (notification.direction == ScrollDirection.forward) {
                    if (!isNavBarVisible.value) isNavBarVisible.value = true;
                  }
                } else if (notification is ScrollUpdateNotification) {
                  final delta = notification.scrollDelta ?? 0;
                  if (delta < -4) {
                    if (!isNavBarVisible.value) isNavBarVisible.value = true;
                  } else if (delta > 4) {
                    if (isNavBarVisible.value) isNavBarVisible.value = false;
                  }
                }

                if (notification.metrics.maxScrollExtent > 20 &&
                    notification.metrics.pixels >=
                        notification.metrics.maxScrollExtent - 20) {
                  if (!isNavBarVisible.value) isNavBarVisible.value = true;
                }
                return false;
              },
              child: ListView.builder(
                itemCount: 50,
                itemBuilder: (context, index) {
                  return Container(
                    height: 80,
                    margin: const EdgeInsets.all(8),
                    color: Colors.teal.shade100,
                    child: Center(child: Text('Item $index')),
                  );
                },
              ),
            ),
          ),
          bottomNavigationBar: ValueListenableBuilder<bool>(
            valueListenable: isNavBarVisible,
            builder: (context, visible, child) {
              return Visibility(
                visible: visible,
                child: Container(
                  height: 60,
                  key: const Key('bottom_nav_bar'),
                  color: Colors.teal,
                  child: const Center(child: Text('Bottom Nav Bar')),
                ),
              );
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(testHarness());

    // 1. Initially visible
    expect(isNavBarVisible.value, isTrue);
    expect(find.byKey(const Key('bottom_nav_bar')), findsOneWidget);

    // 2. Tap on any part of the screen (e.g., Item 2)
    await tester.tap(find.text('Item 2'));
    await tester.pumpAndSettle();

    // Bottom navbar should disappear
    expect(isNavBarVisible.value, isFalse);

    // 3. Tap on the screen again while hidden
    await tester.tap(find.text('Item 2'));
    await tester.pumpAndSettle();

    // Bottom navbar should reappear!
    expect(isNavBarVisible.value, isTrue);

    // 4. Tap again to hide before testing scroll
    await tester.tap(find.text('Item 2'));
    await tester.pumpAndSettle();
    expect(isNavBarVisible.value, isFalse);

    // 5. Scroll down further (drag upwards)
    await tester.drag(find.text('Item 5'), const Offset(0, -150));
    await tester.pumpAndSettle();

    // Still hidden
    expect(isNavBarVisible.value, isFalse);

    // 6. Scroll up (drag downwards)
    await tester.drag(find.byType(ListView), const Offset(0, 150));
    await tester.pumpAndSettle();

    // Bottom navbar should appear again!
    expect(isNavBarVisible.value, isTrue);
  });
}
