import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

    final errors = <String>[];

    Map<String, dynamic>? nextBalance = balance;
    List<dynamic> nextPlans = plans;
    List<dynamic> nextOrders = orders;
    List<dynamic> nextPaymentMethods = paymentMethods;

<<<<<<< codex-5jlcba
    try {
      nextBalance = await XBoardApi.I.fetchBalance();
    } catch (e) {
      errors.add('余额接口失败: $e');
      nextBalance ??= const <String, dynamic>{};
    }

    try {
      nextPlans = await XBoardApi.I.fetchPlans();
    } catch (e) {
      errors.add('套餐接口失败: $e');
      nextPlans = const [];
    }

    try {
      nextOrders = await XBoardApi.I.fetchUserOrders();
    } catch (e) {
      errors.add('订单接口失败: $e');
      nextOrders = const [];
    }

    try {
      nextPaymentMethods = await XBoardApi.I.fetchPaymentMethods();
    } catch (e) {
      errors.add('支付方式接口失败: $e');
      nextPaymentMethods = const [];
    }

    if (!mounted) return;

    setState(() {
      balance = nextBalance;
      plans = nextPlans;
      orders = nextOrders;
      paymentMethods = nextPaymentMethods;
      err = errors.isEmpty ? null : errors.join('\n');
      busy = false;
    });
  }

  String _bytesText(dynamic bytesRaw) {
    final bytes = (bytesRaw is num) ? bytesRaw.toDouble() : double.tryParse(bytesRaw?.toString() ?? '') ?? 0;
    if (bytes <= 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int idx = 0;
    double val = bytes;
    while (val >= 1024 && idx < units.length - 1) {
      val /= 1024;
      idx++;
    }
    return '${val.toStringAsFixed(idx == 0 ? 0 : 1)} ${units[idx]}';
  }

  String _priceText(dynamic raw) {
    final n = (raw is num) ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;
    if (n <= 0) return '-';
    final yuan = n >= 100 ? n / 100 : n;
    return '¥${yuan.toStringAsFixed(2)}';
  }

  List<MapEntry<String, dynamic>> _planPeriods(Map<String, dynamic> plan) {
    final keys = const ['month_price', 'quarter_price', 'half_year_price', 'year_price', 'two_year_price', 'three_year_price', 'onetime_price'];
    final out = <MapEntry<String, dynamic>>[];
    for (final k in keys) {
      final v = plan[k];
      if (v == null) continue;
      final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
      if (n > 0) out.add(MapEntry(k, v));
    }
    return out;
  }

  String _periodName(String k) {
    switch (k) {
      case 'month_price':
        return '每月';
      case 'quarter_price':
        return '每季';
      case 'half_year_price':
        return '半年';
      case 'year_price':
        return '每年';
      case 'two_year_price':
        return '两年';
      case 'three_year_price':
        return '三年';
      case 'onetime_price':
        return '一次性';
      default:
        return k;
    }
  }

  Future<void> _openBuySheet(Map<String, dynamic> plan) async {
    final planId = plan['id']?.toString() ?? '';
    if (planId.isEmpty) {
      setState(() => err = '套餐缺少 id，无法购买');
      return;
    }

    final periods = _planPeriods(plan);
    if (periods.isEmpty) {
      setState(() => err = '套餐没有可购买周期');
      return;
    }

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BuyBottomSheet(
        plan: plan,
        periods: periods,
        paymentMethods: paymentMethods,
        onCheckCoupon: ({required code, required period}) {
          return XBoardApi.I.checkCoupon(code: code, planId: planId, period: period);
        },
        onCreateOrder: ({required period, couponCode}) {
          return XBoardApi.I.createOrder(planId: planId, period: period, couponCode: couponCode);
        },
      ),
    );

    if (!mounted || result == null) return;

    final tradeNo = result['trade_no'] ?? '';
    final method = result['method'] ?? '';

    if (tradeNo.isNotEmpty && method.isNotEmpty) {
      await _doCheckout(tradeNo, method);
    } else {
      await _load();
    }
  }

  Future<void> _doCheckout(String tradeNo, String method) async {
    try {
      final resp = await XBoardApi.I.checkout(tradeNo: tradeNo, method: method);
      final data = resp['data'];
      String? jump;
      if (data is String && data.trim().isNotEmpty) {
        jump = data.trim();
      } else if (data is Map) {
        jump = data['payment_url']?.toString() ?? data['qrcode_url']?.toString();
      }

      if (jump != null && jump.isNotEmpty) {
        final uri = Uri.tryParse(jump);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已发起支付，请在外部页面完成付款')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发起支付失败: $e')));
=======
    try {
      nextBalance = await XBoardApi.I.fetchBalance();
    } catch (e) {
      errors.add('余额接口失败: $e');
      nextBalance ??= const <String, dynamic>{};
    }

    try {
      nextPlans = await XBoardApi.I.fetchPlans();
    } catch (e) {
      errors.add('套餐接口失败: $e');
      nextPlans = const [];
>>>>>>> main
    }

    try {
      nextOrders = await XBoardApi.I.fetchUserOrders();
    } catch (e) {
      errors.add('订单接口失败: $e');
      nextOrders = const [];
    }

    try {
      nextPaymentMethods = await XBoardApi.I.fetchPaymentMethods();
    } catch (e) {
      errors.add('支付方式接口失败: $e');
      nextPaymentMethods = const [];
    }

    if (!mounted) return;

    setState(() {
      balance = nextBalance;
      plans = nextPlans;
      orders = nextOrders;
      paymentMethods = nextPaymentMethods;
      err = errors.isEmpty ? null : errors.join('\n');
      busy = false;
    });
  }

  Widget _buildBalanceCard() {
    final b = balance ?? const <String, dynamic>{};
    final amount = b['balance'] ?? b['commission_balance'] ?? b['data']?['balance'];
    return Card(
      color: const Color(0xFF121827),
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: const Text('账户余额'),
        subtitle: Text(_priceText(amount)),
        trailing: IconButton(onPressed: busy ? null : _load, icon: const Icon(Icons.refresh)),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final periods = _planPeriods(plan);
    final primaryPrice = periods.isEmpty ? '-' : '${_priceText(periods.first.value)}/${_periodName(periods.first.key)}';
    return Card(
      color: const Color(0xFF121827),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan['name']?.toString() ?? '未命名套餐',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(primaryPrice, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text('流量: ${_bytesText(plan['transfer_enable'])}   设备: ${plan['device_limit'] ?? '-'}   速率: ${plan['speed_limit'] ?? '-'}Mbps'),
            const SizedBox(height: 8),
            Text(plan['content']?.toString() ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: () => _openBuySheet(plan), child: const Text('购买')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final tradeNo = order['trade_no']?.toString() ?? '';
    return Card(
      color: const Color(0xFF121827),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(order['plan_name']?.toString() ?? '订单'),
        subtitle: Text('订单号: $tradeNo\n状态: ${order['status']}  金额: ${_priceText(order['final_amount'] ?? order['amount'])}'),
        isThreeLine: true,
        trailing: tradeNo.isEmpty
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'refresh') {
                    _load();
                  } else {
                    _doCheckout(tradeNo, v);
                  }
                },
                itemBuilder: (ctx) {
                  final items = <PopupMenuEntry<String>>[
                    const PopupMenuItem(value: 'refresh', child: Text('刷新')),
                  ];
                  for (final m in paymentMethods) {
                    if (m is! Map) continue;
                    final code = m['payment']?.toString() ?? m['method']?.toString() ?? '';
                    final name = m['name']?.toString() ?? code;
                    if (code.isEmpty) continue;
                    items.add(PopupMenuItem(value: code, child: Text('用$name支付')));
                  }
                  return items;
                },
              ),
      ),
    );
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
                    _buildBalanceCard(),
                    const SizedBox(height: 8),
                    const Text('套餐列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (plans.isEmpty) _jsonCard('套餐原始数据', plans),
                    ...plans.whereType<Map>().map((e) => _buildPlanCard(Map<String, dynamic>.from(e))),
                    const SizedBox(height: 8),
                    const Text('订单列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (orders.isEmpty) _jsonCard('订单原始数据', orders),
                    ...orders.whereType<Map>().map((e) => _buildOrderCard(Map<String, dynamic>.from(e))),
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

class _BuyBottomSheet extends StatefulWidget {
  final Map<String, dynamic> plan;
  final List<MapEntry<String, dynamic>> periods;
  final List<dynamic> paymentMethods;
  final Future<Map<String, dynamic>> Function({required String code, required String period}) onCheckCoupon;
  final Future<Map<String, dynamic>> Function({required String period, String? couponCode}) onCreateOrder;

  const _BuyBottomSheet({
    required this.plan,
    required this.periods,
    required this.paymentMethods,
    required this.onCheckCoupon,
    required this.onCreateOrder,
  });

  @override
  State<_BuyBottomSheet> createState() => _BuyBottomSheetState();
}

class _BuyBottomSheetState extends State<_BuyBottomSheet> {
  String? selectedPeriod;
  String? selectedMethod;
  final couponCtrl = TextEditingController();
  String? couponMsg;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    selectedPeriod = widget.periods.first.key;
    final firstMethod = widget.paymentMethods.whereType<Map>().firstWhere(
          (e) => (e['payment']?.toString() ?? e['method']?.toString() ?? '').isNotEmpty,
          orElse: () => const {},
        );
    selectedMethod = firstMethod['payment']?.toString() ?? firstMethod['method']?.toString();
  }

  @override
  void dispose() {
    couponCtrl.dispose();
    super.dispose();
  }

  String _priceText(dynamic raw) {
    final n = (raw is num) ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;
    final yuan = n >= 100 ? n / 100 : n;
    return '¥${yuan.toStringAsFixed(2)}';
  }

  String _periodName(String k) {
    switch (k) {
      case 'month_price':
        return '每月';
      case 'quarter_price':
        return '每季';
      case 'half_year_price':
        return '半年';
      case 'year_price':
        return '每年';
      case 'two_year_price':
        return '两年';
      case 'three_year_price':
        return '三年';
      case 'onetime_price':
        return '一次性';
      default:
        return k;
    }
  }

  Future<void> _checkCoupon() async {
    final code = couponCtrl.text.trim();
    if (code.isEmpty || selectedPeriod == null) return;
    setState(() => busy = true);
    try {
      final r = await widget.onCheckCoupon(code: code, period: selectedPeriod!);
      final d = r['data'];
      if (d is Map && d['valid'] == false) {
        couponMsg = d['message']?.toString() ?? '优惠券不可用';
      } else {
        couponMsg = '优惠券可用';
      }
    } catch (e) {
      couponMsg = '校验失败: $e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    if (selectedPeriod == null) return;
    setState(() => busy = true);
    try {
      final createResp = await widget.onCreateOrder(
        period: selectedPeriod!,
        couponCode: couponCtrl.text.trim().isEmpty ? null : couponCtrl.text.trim(),
      );
      final data = createResp['data'];
      String tradeNo = '';
      if (data is String) {
        tradeNo = data;
      } else if (data is Map) {
        tradeNo = data['trade_no']?.toString() ?? '';
      }
      if (tradeNo.isEmpty) throw Exception('下单成功但未返回 trade_no');

      if (selectedMethod == null || selectedMethod!.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop({'trade_no': tradeNo, 'method': ''});
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop({'trade_no': tradeNo, 'method': selectedMethod!});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建订单失败: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.plan['name']?.toString() ?? '套餐详情', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text('选择周期', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: widget.periods
                    .map(
                      (e) => ChoiceChip(
                        label: Text('${_periodName(e.key)} ${_priceText(e.value)}'),
                        selected: selectedPeriod == e.key,
                        onSelected: busy
                            ? null
                            : (_) {
                                setState(() => selectedPeriod = e.key);
                              },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: couponCtrl,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: '优惠券',
                  suffixIcon: TextButton(onPressed: busy ? null : _checkCoupon, child: const Text('验证')),
                ),
              ),
              if (couponMsg != null) ...[
                const SizedBox(height: 6),
                Text(couponMsg!, style: const TextStyle(fontSize: 12.5)),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedMethod,
                items: widget.paymentMethods
                    .whereType<Map>()
                    .map((m) {
                      final code = m['payment']?.toString() ?? m['method']?.toString() ?? '';
                      final name = m['name']?.toString() ?? code;
                      if (code.isEmpty) return null;
                      return DropdownMenuItem(value: code, child: Text(name));
                    })
                    .whereType<DropdownMenuItem<String>>()
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => selectedMethod = v),
                decoration: const InputDecoration(labelText: '支付方式'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('创建订单'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
