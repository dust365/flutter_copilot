import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class NavigationDemoPage extends StatefulWidget {
  const NavigationDemoPage({super.key});

  @override
  State<NavigationDemoPage> createState() => _NavigationDemoPageState();
}

class _NavigationDemoPageState extends State<NavigationDemoPage> {
  final _logger = Logger('NavigationDemoPage');
  int _pageNumber = 1;
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['page'] is int) {
        _pageNumber = args['page'] as int;
      }
      _hasInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Navigation Demo - Page $_pageNumber'),
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Page $_pageNumber',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                key: ValueKey('push_page_button_$_pageNumber'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NavigationDemoPage(),
                      settings: RouteSettings(
                        name: '/navigation-demo',
                        arguments: {'page': _pageNumber + 1},
                      ),
                    ),
                  ).then((_) {
                    _logger.info('Returned from page ${_pageNumber + 1}');
                  });
                },
                child: Text('Push Page ${_pageNumber + 1}'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const ValueKey('pop_button'),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                    _logger.info('Popped from page $_pageNumber');
                  }
                },
                child: const Text('Pop (Go Back)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const ValueKey('pop_to_root_button'),
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                  _logger.info('Popped to root');
                },
                child: const Text('Pop to Root'),
              ),
              const SizedBox(height: 32),
              const Text(
                'Use MCP navigate tool to control navigation programmatically',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
