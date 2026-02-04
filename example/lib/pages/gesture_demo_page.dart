import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class GestureDemoPage extends StatefulWidget {
  const GestureDemoPage({super.key});

  @override
  State<GestureDemoPage> createState() => _GestureDemoPageState();
}

class _GestureDemoPageState extends State<GestureDemoPage> {
  final _logger = Logger('GestureDemoPage');
  double _sliderValue = 0.5;
  double _dragPosition = 100.0;
  int _doubleTapCount = 0;
  int _longPressCount = 0;
  int _swipeCount = 0;
  String _swipeDirection = 'None';
  double _swipeStartX = 0.0;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gesture Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
            : null,
        automaticallyImplyLeading: canPop,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Demo Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Drag Demo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Try dragging the slider or the card below',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    // Slider
                    Slider(
                      key: const ValueKey('demo_slider'),
                      value: _sliderValue,
                      onChanged: (value) {
                        setState(() {
                          _sliderValue = value;
                        });
                        _logger.info('Slider value changed to: $value');
                      },
                    ),
                    Text(
                      'Slider Value: ${_sliderValue.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Draggable Card
                    GestureDetector(
                      onPanStart: (details) {
                        _logger.info('Pan started at: ${details.globalPosition}');
                      },
                      onPanUpdate: (details) {
                        _logger.info(
                            'Pan update: delta=${details.delta}, position=${details.globalPosition}');
                        setState(() {
                          _dragPosition += details.delta.dx;
                          _dragPosition = _dragPosition.clamp(0.0, 300.0);
                          _logger.info('Updated drag position to: $_dragPosition');
                        });
                      },
                      onPanEnd: (details) {
                        _logger.info('Pan ended at: ${details.velocity}');
                      },
                      child: Container(
                        key: const ValueKey('draggable_card'),
                        width: 100,
                        height: 100,
                        margin: EdgeInsets.only(left: _dragPosition),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'Drag Me',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Swipe Demo Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Swipe Demo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Try swiping left/right on the card below',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onHorizontalDragStart: (details) {
                        _swipeStartX = details.globalPosition.dx;
                      },
                      onHorizontalDragUpdate: (details) {
                        // Track the drag direction during update
                        final currentX = details.globalPosition.dx;
                        if (currentX > _swipeStartX + 50) {
                          // Moved right significantly
                          _swipeDirection = 'Right';
                        } else if (currentX < _swipeStartX - 50) {
                          // Moved left significantly
                          _swipeDirection = 'Left';
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        setState(() {
                          _swipeCount++;
                          // Use primaryVelocity if available, otherwise use tracked direction
                          if (details.primaryVelocity != null) {
                            if (details.primaryVelocity! > 0) {
                              _swipeDirection = 'Right';
                            } else if (details.primaryVelocity! < 0) {
                              _swipeDirection = 'Left';
                            }
                          }
                          // If direction is still None, keep the tracked direction
                          if (_swipeDirection == 'None') {
                            final deltaX = details.globalPosition.dx - _swipeStartX;
                            if (deltaX > 0) {
                              _swipeDirection = 'Right';
                            } else if (deltaX < 0) {
                              _swipeDirection = 'Left';
                            }
                          }
                        });
                        _logger.info('Swipe detected: $_swipeDirection, Count: $_swipeCount');
                      },
                      child: Container(
                        key: const ValueKey('swipeable_card'),
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Swipe Count: $_swipeCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Last Direction: $_swipeDirection',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Double Tap Demo Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Double Tap Demo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Double tap the card below to increment counter',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onDoubleTap: () {
                        setState(() {
                          _doubleTapCount++;
                        });
                        _logger.info('Double tapped! Count: $_doubleTapCount');
                      },
                      child: Container(
                        key: const ValueKey('double_tap_card'),
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.touch_app,
                                size: 40,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Double Taps: $_doubleTapCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Long Press Demo Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Long Press Demo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Long press the card below to trigger action',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onLongPress: () {
                        setState(() {
                          _longPressCount++;
                        });
                        _logger.info('Long pressed! Count: $_longPressCount');
                        // Show a snackbar to indicate long press was detected
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Long Press Detected! Count: $_longPressCount'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        key: const ValueKey('long_press_card'),
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.purple,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.touch_app,
                                size: 40,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Long Presses: $_longPressCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Hold for 500ms',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
