import 'dart:convert';

import 'package:flutter/material.dart';

import 'xboard_api.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  bool busy = false;
  String? err;
  Map<String, dynamic>? balance;
  List<dynamic> plans = [];
  List<dynamic> orders = [];
  List<dynamic> paymentMethods = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        XBoardApi.I.fetchBalance(),
        XBoardApi.I.fetchPlans(),
        XBoardApi.I.fetchUserOrders(),
        XBoardApi.I.fetchPaymentMethods(),
      ]);

      setState(() {
        balance = results[0] as Map<String, dynamic>;
        plans = results[1] as List<dynamic>;
        orders = results[2] as List<dynamic>;
        paymentMethods = results[3] as List<dynamic>;
      });
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _jsonCard(String title, Object data) {
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    return Card(
      color: const Color(0xFF121827),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectableText(pretty, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('商店'),
        actions: [
          IconButton(
            onPressed: busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : _load,
                  icon: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.storefront),
                  label: Text(busy ? '加载中…' : '刷新商店数据'),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 12),
                Text(err!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _jsonCard('余额信息', balance ?? const <String, dynamic>{}),
                    _jsonCard('套餐列表', plans),
                    _jsonCard('订单列表', orders),
                    _jsonCard('支付方式', paymentMethods),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
