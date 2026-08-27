import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

const _kFilename = 'example/lib/pages/tap_demo_page.dart';

class TapDemoPage extends StatefulWidget {
  const TapDemoPage({super.key});

  @override
  State<TapDemoPage> createState() => _TapDemoPageState();
}

class _TapDemoPageState extends State<TapDemoPage> {
  bool _liked = false;
  int _likeCount = 128;

  bool _favorited = false;
  int _favoriteCount = 32;

  bool _followed = false;
  int _followerCount = 1024;

  int _cartQty = 1;
  final double _unitPrice = 19.90;

  String _output = '— 等待点击 —';

  void _log(String msg) {
    FlutterCopilotBinding.addLog('[tap_demo] $msg');
    setState(() => _output = msg);
  }

  void _toggleLike() {
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    _log('like(liked=$_liked, count=$_likeCount)');
  }

  void _toggleFavorite() {
    setState(() {
      _favorited = !_favorited;
      _favoriteCount += _favorited ? 1 : -1;
    });
    _log('favorite(favorited=$_favorited, count=$_favoriteCount)');
  }

  void _toggleFollow() {
    setState(() {
      _followed = !_followed;
      _followerCount += _followed ? 1 : -1;
    });
    _log('follow(followed=$_followed, followers=$_followerCount)');
  }

  void _bumpQty(int delta) {
    setState(() => _cartQty = (_cartQty + delta).clamp(1, 99));
    _log('cart.qty=$_cartQty  subtotal=¥${(_unitPrice * _cartQty).toStringAsFixed(2)}');
  }

  void _checkout() {
    final total = (_unitPrice * _cartQty).toStringAsFixed(2);
    _log('cart.checkout(qty=$_cartQty, unit=¥$_unitPrice, total=¥$total)');
  }

  void _onFabPressed() {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final message = '已发布一条动态 @ $ts';
    _log('fab → showSnackBar("$message")');
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('fab_snackbar'),
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => _log('snackbar.action("撤销") tapped'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点击 · tap'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fileBanner(),
            const SizedBox(height: 16),
            _outputCard(),
            const SizedBox(height: 16),
            _socialCard(),
            const SizedBox(height: 12),
            _cartCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('test_fab'),
        onPressed: _onFabPressed,
        icon: const Icon(Icons.send),
        label: const Text('发布动态'),
      ),
    );
  }

  Widget _fileBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.insert_drive_file_outlined,
              color: Colors.cyanAccent, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _kFilename,
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.cyanAccent,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _outputCard() {
    return Card(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('> ',
                style: TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12)),
            Expanded(
              child: SelectableText(
                _output,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('动态卡片 · 点赞 / 收藏 / 关注',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Flutter Copilot',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('刚刚发布了一条动态',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('follow_button'),
                  onPressed: _toggleFollow,
                  icon: Icon(_followed ? Icons.check : Icons.add,
                      size: 18),
                  label: Text(_followed ? '已关注' : '关注'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        _followed ? Colors.grey : Colors.blue,
                    side: BorderSide(
                      color: _followed
                          ? Colors.grey.shade400
                          : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Row(
              children: [
                _iconStat(
                  keyValue: 'like_button',
                  icon: _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? Colors.red : Colors.grey.shade700,
                  label: '$_likeCount',
                  onTap: _toggleLike,
                ),
                _iconStat(
                  keyValue: 'favorite_button',
                  icon: _favorited ? Icons.star : Icons.star_border,
                  color:
                      _favorited ? Colors.amber : Colors.grey.shade700,
                  label: '$_favoriteCount',
                  onTap: _toggleFavorite,
                ),
                _iconStat(
                  keyValue: 'follower_count',
                  icon: Icons.people_outline,
                  color: Colors.grey.shade700,
                  label: '$_followerCount 粉丝',
                  onTap: null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconStat({
    required String keyValue,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        key: ValueKey(keyValue),
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(color: color, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartCard() {
    final subtotal = (_unitPrice * _cartQty).toStringAsFixed(2);
    return Card(
      child: InkWell(
        key: const ValueKey('test_tappable_card'),
        borderRadius: BorderRadius.circular(8),
        onTap: _checkout,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('InkWell · 购物车（点卡片=结算）',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('数量：'),
                  IconButton(
                    key: const ValueKey('test_icon_button_minus'),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.redAccent,
                    onPressed: () => _bumpQty(-1),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text('$_cartQty',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    key: const ValueKey('test_icon_button_plus'),
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.green,
                    onPressed: () => _bumpQty(1),
                  ),
                  const Spacer(),
                  Text('小计 ¥$subtotal',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
