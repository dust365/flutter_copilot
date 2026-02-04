import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';
import 'package:flutter_copilot_claw/src/services/log_collector.dart';
import 'pages/basic_interaction_demo_page.dart';
import 'pages/debug_monitor_demo_page.dart';
import 'pages/gesture_demo_page.dart';
import 'pages/home_page.dart';
import 'pages/navigation_demo_page.dart';
import 'pages/scroll_demo_page.dart';
import 'pages/text_input_demo_page.dart';

void main() {
  // Use Zone to intercept print() calls and capture them in LogCollector
  // IMPORTANT: Initialize binding inside the Zone to avoid zone mismatch errors
  runZonedGuarded(
    () {
      // Initialize binding inside the Zone
      FlutterCopilotBinding.ensureInitialized();

      // Log application startup (captures the equivalent of Flutter toolchain messages)
      // Note: The actual Flutter toolchain messages are output before main() runs,
      // so they cannot be captured. This is a manual log for reference.
      // ignore: avoid_print
      print('Flutter Copilot: Application started and ready for VM Service connection');

      runApp(const MyApp());
    },
    (error, stack) {
      // Capture errors in console logs
      //收集错误日志
      LogCollector.addConsoleLogStatic(
        'Uncaught error: $error\n$stack',
        isError: true,
      );
      // Also print to console
      // ignore: avoid_print
      print('Uncaught error: $error\n$stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // Capture print() calls in LogCollector
        //收集普通日志
        LogCollector.addConsoleLogStatic(line);
        // Also print to original console
        parent.print(zone, line);
      },
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Copilot Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/home',
      routes: {
        '/home': (context) => const HomePage(),
        '/basic-interaction-demo': (context) => const BasicInteractionDemoPage(),
        '/text-input-demo': (context) => const TextInputDemoPage(),
        '/scroll-demo': (context) => const ScrollDemoPage(),
        '/gesture-demo': (context) => const GestureDemoPage(),
        '/navigation-demo': (context) => const NavigationDemoPage(),
        '/debug-monitor-demo': (context) => const DebugMonitorDemoPage(),
        '/old-home': (context) => const MyHomePage(title: 'Flutter Demo Home Page'),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    // ignore: avoid_print
    print('Incrementing counter, from $_counter');
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
