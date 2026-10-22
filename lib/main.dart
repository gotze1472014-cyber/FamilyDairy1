import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyDairyApp());
}

String formatNumber(dynamic number) {
  if (number == null) return '0';
  double val = number is int ? number.toDouble() : (number as double);
  String str = val.toStringAsFixed(0);
  RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  return str.replaceAllMapped(reg, (Match m) => '${m[1]},');
}

String formatDecimal(dynamic number) {
  if (number == null) return '0';
  double val = number is int ? number.toDouble() : (number as double);
  if (val == val.roundToDouble()) {
    return formatNumber(val.toInt());
  }
  return val.toStringAsFixed(2);
}

class AppSettings {
  static String adminPassword = '1234';
  static String subAccountPassword = '0000';
  static bool subAccountCanDeleteInvoice = false;
  static bool subAccountCanModifyPrices = false;
  static bool subAccountCanAccessReports = true;
}

class FamilyDairyApp extends StatelessWidget {
  const FamilyDairyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ألبان وأجبان العائلة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          primary: Colors.amber.shade800,
          secondary: Colors.orangeAccent,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ================= 1. Models =================
class ProductModel {
  String id;
  String name;
  double purchasePrice;
  double sellingPrice;
  double stockQuantity;
  String unit;
  String barcode;
  bool canBeUsedAsIngredient;
  bool isManufactured;
  double baseIngredientRequiredPerUnit;
  double minStockAlert;
  String notes;
  String category;
  
  bool isSplitProduct; 
  double splitFactor; 
  String subUnitName; 
  double unitSellingPrice; 
  double maxCapacity;

  ProductModel({
    required this.id, required this.name, required this.purchasePrice, required this.sellingPrice,
    required this.stockQuantity, this.unit = 'كيلو', this.barcode = '', this.canBeUsedAsIngredient = false,
    this.isManufactured = false, this.baseIngredientRequiredPerUnit = 0.0, this.minStockAlert = 5.0,
    this.notes = '', this.category = 'ألبان وأجبان', this.isSplitProduct = false,
    this.splitFactor = 1.0, this.subUnitName = 'قطعة', this.unitSellingPrice = 0.0, this.maxCapacity = 100.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'purchasePrice': purchasePrice, 'sellingPrice': sellingPrice,
    'stockQuantity': stockQuantity, 'unit': unit, 'barcode': barcode,
    'canBeUsedAsIngredient': canBeUsedAsIngredient, 'isManufactured': isManufactured,
    'baseIngredientRequiredPerUnit': baseIngredientRequiredPerUnit, 'minStockAlert': minStockAlert,
    'notes': notes, 'category': category, 'isSplitProduct': isSplitProduct,
    'splitFactor': splitFactor, 'subUnitName': subUnitName, 'unitSellingPrice': unitSellingPrice,
    'maxCapacity': maxCapacity,
  };

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
    id: json['id'] ?? '', name: json['name'] ?? '',
    purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0.0,
    sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0.0,
    stockQuantity: (json['stockQuantity'] as num?)?.toDouble() ?? 0.0,
    unit: json['unit'] ?? 'كيلو', barcode: json['barcode'] ?? '',
    canBeUsedAsIngredient: json['canBeUsedAsIngredient'] ?? false,
    isManufactured: json['isManufactured'] ?? false,
    baseIngredientRequiredPerUnit: (json['baseIngredientRequiredPerUnit'] as num?)?.toDouble() ?? 0.0,
    minStockAlert: (json['minStockAlert'] as num?)?.toDouble() ?? 5.0,
    notes: json['notes'] ?? '', category: json['category'] ?? 'ألبان وأجبان',
    isSplitProduct: json['isSplitProduct'] ?? false,
    splitFactor: (json['splitFactor'] as num?)?.toDouble() ?? 1.0,
    subUnitName: json['subUnitName'] ?? 'قطعة',
    unitSellingPrice: (json['unitSellingPrice'] as num?)?.toDouble() ?? 0.0,
    maxCapacity: (json['maxCapacity'] as num?)?.toDouble() ?? 100.0,
  );
}

class SupplierModel {
  String id;
  String name;
  String phone;
  String category;
  SupplierModel({required this.id, required this.name, required this.phone, required this.category});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'category': category};
  factory SupplierModel.fromJson(Map<String, dynamic> json) => SupplierModel(
    id: json['id'] ?? '', name: json['name'] ?? '', phone: json['phone'] ?? '', category: json['category'] ?? '',
  );
}

class InvoiceItem {
  ProductModel product;
  double quantity;
  double priceUsed;
  String unitLabelUsed;

  double get total => quantity * priceUsed;
  double get profit => total - (quantity * product.purchasePrice);

  InvoiceItem({required this.product, required this.quantity, required this.priceUsed, required this.unitLabelUsed});

  Map<String, dynamic> toJson() => {
    'productId': product.id, 'productName': product.name, 'quantity': quantity, 'priceUsed': priceUsed, 'unitLabelUsed': unitLabelUsed,
  };

  factory InvoiceItem.fromJson(Map<String, dynamic> json, List<ProductModel> products) {
    ProductModel foundProd;
    try {
      foundProd = products.firstWhere((p) => p.id == json['productId']);
    } catch (_) {
      foundProd = ProductModel(id: json['productId'] ?? '0', name: json['productName'] ?? 'مادة', purchasePrice: 0, sellingPrice: 0, stockQuantity: 0);
    }
    return InvoiceItem(
      product: foundProd,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      priceUsed: (json['priceUsed'] as num?)?.toDouble() ?? 0.0,
      unitLabelUsed: json['unitLabelUsed'] ?? 'كيلو',
    );
  }
}

enum InvoiceType { sales, purchase }

class InvoiceModel {
  String id;
  String partyName;
  List<InvoiceItem> items;
  double subTotal;
  double discountOrExtra;
  double totalAmount;
  double totalProfit;
  DateTime date;
  InvoiceType type;
  bool isDebt;

  InvoiceModel({
    required this.id, required this.partyName, required this.items, required this.subTotal,
    this.discountOrExtra = 0, required this.totalAmount, required this.totalProfit,
    required this.date, required this.type, this.isDebt = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'partyName': partyName, 'items': items.map((i) => i.toJson()).toList(),
    'subTotal': subTotal, 'discountOrExtra': discountOrExtra, 'totalAmount': totalAmount,
    'totalProfit': totalProfit, 'date': date.toIso8601String(),
    'type': type == InvoiceType.sales ? 'sales' : 'purchase', 'isDebt': isDebt,
  };

  factory InvoiceModel.fromJson(Map<String, dynamic> json, List<ProductModel> products) => InvoiceModel(
    id: json['id'] ?? '',
    partyName: json['partyName'] ?? '',
    items: (json['items'] as List<dynamic>? ?? []).map((i) => InvoiceItem.fromJson(i, products)).toList(),
    subTotal: (json['subTotal'] as num?)?.toDouble() ?? 0.0,
    discountOrExtra: (json['discountOrExtra'] as num?)?.toDouble() ?? 0.0,
    totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
    totalProfit: (json['totalProfit'] as num?)?.toDouble() ?? 0.0,
    date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
    type: json['type'] == 'purchase' ? InvoiceType.purchase : InvoiceType.sales,
    isDebt: json['isDebt'] ?? false,
  );
}

class PaymentVoucherModel {
  String title;
  double amount;
  String details;
  DateTime date;
  PaymentVoucherModel({required this.title, required this.amount, required this.details, required this.date});
  Map<String, dynamic> toJson() => {'title': title, 'amount': amount, 'details': details, 'date': date.toIso8601String()};
  factory PaymentVoucherModel.fromJson(Map<String, dynamic> json) => PaymentVoucherModel(
    title: json['title'] ?? '', amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    details: json['details'] ?? '', date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
  );
}

class DebtPaymentModel {
  String partyName;
  double amountPaid;
  DateTime date;
  bool isCustomer;
  DebtPaymentModel({required this.partyName, required this.amountPaid, required this.date, required this.isCustomer});
  Map<String, dynamic> toJson() => {'partyName': partyName, 'amountPaid': amountPaid, 'date': date.toIso8601String(), 'isCustomer': isCustomer};
  factory DebtPaymentModel.fromJson(Map<String, dynamic> json) => DebtPaymentModel(
    partyName: json['partyName'] ?? '', amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0.0,
    date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(), isCustomer: json['isCustomer'] ?? true,
  );
}

// ================= 2. Login Screen =================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _passController = TextEditingController();
  bool _isAdmin = true;

  void _login() {
    String pass = _passController.text.trim();
    if (_isAdmin) {
      if (pass == AppSettings.adminPassword || pass.isEmpty) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => MainDashboardScreen(isAdmin: true)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة مرور المدير خاطئة'), backgroundColor: Colors.red));
      }
    } else {
      if (pass == AppSettings.subAccountPassword || pass.isEmpty) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => MainDashboardScreen(isAdmin: false)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة مرور الحساب الفرعي خاطئة'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.amber.shade50,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                      child: const Icon(Icons.kebab_dining, size: 50, color: Colors.brown),
                    ),
                    const SizedBox(height: 12),
                    const Text('ألبان وأجبان العائلة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.brown)),
                    const Text('إدارة محلية مع مزامنة Wi-Fi', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 20),
                    ToggleButtons(
                      isSelected: [_isAdmin, !_isAdmin],
                      onPressed: (index) => setState(() => _isAdmin = index == 0),
                      borderRadius: BorderRadius.circular(10),
                      selectedColor: Colors.white,
                      fillColor: Colors.amber.shade800,
                      children: const [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Text('حساب مدير')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Text('نقطة مبيع محلية')),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'أدخل كلمة المرور',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _login,
                      child: const Text('تسجيل الدخول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================= 3. Main Dashboard (التخزين الدائم والمزامنة المحلية) =================
class MainDashboardScreen extends StatefulWidget {
  final bool isAdmin;
  const MainDashboardScreen({super.key, required this.isAdmin});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  List<ProductModel> _productsDB = [];
  List<SupplierModel> _suppliersDB = [];
  List<InvoiceModel> _invoices = [];
  List<PaymentVoucherModel> _vouchers = [];
  List<DebtPaymentModel> _debtPayments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDataLocally();
  }

  // تحميل البيانات المحفوظة محلياً على الجهاز بشكل دائم
  Future<void> _loadDataLocally() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // تحميل المنتجات أو وضع القيم الافتراضية إذا فتح التطبيق لأول مرة
    String? prodString = prefs.getString('saved_products');
    if (prodString != null) {
      List decoded = jsonDecode(prodString);
      _productsDB = decoded.map((e) => ProductModel.fromJson(e)).toList();
    } else {
      _productsDB = [
        ProductModel(id: '1', name: 'حليب طازج (خام)', purchasePrice: 7000, sellingPrice: 8500, stockQuantity: 200, unit: 'ليتر', canBeUsedAsIngredient: true, category: 'ألبان وأجبان', maxCapacity: 500),
        ProductModel(id: '2', name: 'لبن رائب', purchasePrice: 8000, sellingPrice: 10000, stockQuantity: 60, unit: 'كيلو', canBeUsedAsIngredient: true, isManufactured: true, baseIngredientRequiredPerUnit: 1.1, category: 'ألبان وأجبان', maxCapacity: 200),
        ProductModel(id: '3', name: 'صحن بيض', purchasePrice: 30000, sellingPrice: 35000, stockQuantity: 10, unit: 'صحن', isSplitProduct: true, splitFactor: 30, subUnitName: 'بيضة', unitSellingPrice: 1300, category: 'غذائيات', maxCapacity: 50),
        ProductModel(id: '4', name: 'بسكويت شوكولاتة', purchasePrice: 5000, sellingPrice: 7000, stockQuantity: 40, unit: 'باكيت', category: 'بسكويت', maxCapacity: 100),
      ];
    }

    // تحميل الموردين
    String? supString = prefs.getString('saved_suppliers');
    if (supString != null) {
      List decoded = jsonDecode(supString);
      _suppliersDB = decoded.map((e) => SupplierModel.fromJson(e)).toList();
    } else {
      _suppliersDB = [SupplierModel(id: '1', name: 'مزرعة الخير (حليب)', phone: '0933111222', category: 'حليب خام')];
    }

    // تحميل الفواتير المسجلة
    String? invString = prefs.getString('saved_invoices');
    if (invString != null) {
      List decoded = jsonDecode(invString);
      _invoices = decoded.map((e) => InvoiceModel.fromJson(e, _productsDB)).toList();
    }

    // تحميل المصاريف
    String? vouString = prefs.getString('saved_vouchers');
    if (vouString != null) {
      List decoded = jsonDecode(vouString);
      _vouchers = decoded.map((e) => PaymentVoucherModel.fromJson(e)).toList();
    }

    // تحميل الديون
    String? debtString = prefs.getString('saved_debts');
    if (debtString != null) {
      List decoded = jsonDecode(debtString);
      _debtPayments = decoded.map((e) => DebtPaymentModel.fromJson(e)).toList();
    }

    setState(() => _isLoading = false);
  }

  // حفظ البيانات محلياً بشكل دائم لكي لا تختفي أبداً عند تسجيل الخروج
  Future<void> _saveDataLocally() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_products', jsonEncode(_productsDB.map((e) => e.toJson()).toList()));
    await prefs.setString('saved_suppliers', jsonEncode(_suppliersDB.map((e) => e.toJson()).toList()));
    await prefs.setString('saved_invoices', jsonEncode(_invoices.map((e) => e.toJson()).toList()));
    await prefs.setString('saved_vouchers', jsonEncode(_vouchers.map((e) => e.toJson()).toList()));
    await prefs.setString('saved_debts', jsonEncode(_debtPayments.map((e) => e.toJson()).toList()));
  }

  // زر المزامنة المحلية الصريح (لسحب ودمج فواتير الموظف بضغطة زر عند الاتصال بالشبكة)
  void _syncWithSubAccountData() {
    TextEditingController importController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مزامنة مع جهاز الموظف (Wi-Fi Sync)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('لإتمام المزامنة:\n1. افتح تطبيق الموظف واذهب إلى التقارير.\n2. اضغط زر "تصدير البيانات" وانسخ الكود.\n3. ألصقه هنا واضغط مزامنة لدمج الفواتير بحسابك.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(controller: importController, maxLines: 4, decoration: const InputDecoration(labelText: 'ألصق بيانات الموظف هنا', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () {
              try {
                Map<String, dynamic> data = jsonDecode(importController.text);
                if (data.containsKey('invoices')) {
                  List incomingInvoices = data['invoices'];
                  setState(() {
                    for (var invJson in incomingInvoices) {
                      InvoiceModel incomingInv = InvoiceModel.fromJson(invJson, _productsDB);
                      // تحقق إذا لم تكن الفاتورة موجودة مسبقاً لكي لا تتكرر
                      if (!_invoices.any((i) => i.id == incomingInv.id)) {
                        _invoices.add(incomingInv);
                        // خصم الكميات من المخزن محلياً
                        for (var item in incomingInv.items) {
                          if (incomingInv.type == InvoiceType.sales) {
                            item.product.stockQuantity -= item.quantity;
                          } else {
                            item.product.stockQuantity += item.quantity;
                          }
                        }
                      }
                    }
                  });
                  _saveDataLocally();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت مزامنة ودمج فواتير الموظف بنجاح تام! 🔄'), backgroundColor: Colors.green));
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الكود المدخل غير صالح للمزامنة!'), backgroundColor: Colors.red));
              }
            },
            child: const Text('تنفيذ المزامنة'),
          ),
        ],
      ),
    );
  }

  void _addInvoice(InvoiceModel invoice, bool isDebt) {
    setState(() {
      invoice.isDebt = isDebt;
      _invoices.add(invoice);
      for (var item in invoice.items) {
        if (invoice.type == InvoiceType.sales) {
          item.product.stockQuantity -= item.quantity;
        } else {
          item.product.stockQuantity += item.quantity;
        }
      }
    });
    _saveDataLocally(); // حفظ فوري دائم
  }

  void _deleteInvoice(InvoiceModel invoice) {
    if (!widget.isAdmin && !AppSettings.subAccountCanDeleteInvoice) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عذراً، الحساب الفرعي لا يمتلك صلاحية الحذف'), backgroundColor: Colors.red));
      return;
    }
    setState(() {
      for (var item in invoice.items) {
        if (invoice.type == InvoiceType.sales) {
          item.product.stockQuantity += item.quantity;
        } else {
          item.product.stockQuantity -= item.quantity;
        }
      }
      _invoices.removeWhere((i) => i.id == invoice.id);
    });
    _saveDataLocally();
  }

  void _navigateTo(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => screen)).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    DateTime now = DateTime.now();
    String formattedDate = "${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}";
    String formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.amber.shade700,
          foregroundColor: Colors.white,
          title: Text(widget.isAdmin ? 'لوحة تحكم المدير (تخزين دائم)' : 'نقطة المبيع (محلية)'),
          actions: [
            if (widget.isAdmin)
              IconButton(
                icon: const Icon(Icons.sync, color: Colors.white),
                tooltip: 'زر مزامنة بيانات الموظف',
                onPressed: _syncWithSubAccountData,
              ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'الإعدادات',
              onPressed: () => _navigateTo(AppSettingsWidget(isAdmin: widget.isAdmin, onUpdate: () => setState(() => _saveDataLocally()))),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'تسجيل خروج',
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen())),
            )
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.amber.shade100, Colors.amber.shade50]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [const Icon(Icons.calendar_today, size: 16, color: Colors.brown), const SizedBox(width: 5), Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown))]),
                    if (widget.isAdmin)
                      GestureDetector(
                        onTap: _syncWithSubAccountData,
                        child: const Row(children: [
                          Icon(Icons.wifi_tethering, size: 16, color: Colors.teal),
                          SizedBox(width: 5),
                          Text('اضغط لمزامنة الموظف', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal))
                        ]),
                      )
                    else
                      const Text('النظام يعمل محلياً', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
                    Row(children: [const Icon(Icons.access_time, size: 16, color: Colors.brown), const SizedBox(width: 5), Text(formattedTime, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown))]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('اختر القسم المطلوب:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _buildDashboardCard('إدارة المواد (كتالوج)', Icons.category, Colors.brown, () {
                      _navigateTo(ProductCatalogWidget(products: _productsDB, onUpdate: () => {setState(() {}), _saveDataLocally()}, isAdmin: widget.isAdmin));
                    }),
                    _buildDashboardCard('إدارة المخزن والترتيب', Icons.inventory_2, Colors.orange.shade800, () {
                      _navigateTo(StockManagementWidget(products: _productsDB, vouchers: _vouchers, suppliers: _suppliersDB, onUpdate: () => {setState(() {}), _saveDataLocally()}, isAdmin: widget.isAdmin));
                    }),
                    _buildDashboardCard('فاتورة مبيع جديدة', Icons.point_of_sale, Colors.green, () {
                      _navigateTo(Scaffold(
                        appBar: AppBar(title: const Text('فاتورة مبيع جديدة'), backgroundColor: Colors.green),
                        body: InvoiceBuilderWidget(type: InvoiceType.sales, products: _productsDB, suppliers: _suppliersDB, onSubmit: _addInvoice),
                      ));
                    }),
                    if (widget.isAdmin) ...[
                      _buildDashboardCard('فاتورة شراء جديدة', Icons.shopping_bag, Colors.blue, () {
                        _navigateTo(Scaffold(
                          appBar: AppBar(title: const Text('فاتورة شراء بضاعة'), backgroundColor: Colors.blue),
                          body: InvoiceBuilderWidget(type: InvoiceType.purchase, products: _productsDB, suppliers: _suppliersDB, onSubmit: _addInvoice),
                        ));
                      }),
                      _buildDashboardCard('وحدة التصنيع', Icons.precision_manufacturing, Colors.teal, () {
                        _navigateTo(Scaffold(
                          appBar: AppBar(title: const Text('وحدة التصنيع والتشغيل'), backgroundColor: Colors.teal),
                          body: AdvancedProductionWidget(products: _productsDB, vouchers: _vouchers, onUpdate: () => {setState(() {}), _saveDataLocally()}, isAdmin: widget.isAdmin),
                        ));
                      }),
                      _buildDashboardCard('إدارة الموردين', Icons.local_shipping, Colors.indigo, () {
                        _navigateTo(SuppliersWidget(suppliers: _suppliersDB, invoices: _invoices, onUpdate: () => {setState(() {}), _saveDataLocally()}, isAdmin: widget.isAdmin));
                      }),
                    ],
                    _buildDashboardCard('إدارة فواتير المبيع', Icons.receipt_long, Colors.green.shade700, () {
                      _navigateTo(InvoicesManagerWidget(invoices: _invoices, type: InvoiceType.sales, onDelete: _deleteInvoice, isAdmin: widget.isAdmin));
                    }),
                    _buildDashboardCard('الديون والآجل', Icons.account_balance_wallet, Colors.deepOrange, () {
                      _navigateTo(Scaffold(
                        appBar: AppBar(title: const Text('سجل الديون والذمم'), backgroundColor: Colors.deepOrange),
                        body: DebtsWidget(invoices: _invoices, debtPayments: _debtPayments, onAddPayment: (p) => {setState(() => _debtPayments.add(p)), _saveDataLocally()}),
                      ));
                    }),
                    _buildDashboardCard('سندات المصاريف', Icons.receipt, Colors.red.shade700, () {
                      _navigateTo(PaymentVouchersWidget(vouchers: _vouchers, onUpdate: () => {setState(() {}), _saveDataLocally()}, isAdmin: widget.isAdmin));
                    }),
                    _buildDashboardCard('التقارير والأرباح', Icons.analytics, Colors.purple, () {
                      if (!widget.isAdmin && !AppSettings.subAccountCanAccessReports) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('غير مسموح للحساب الفرعي بالدخول للتقارير'), backgroundColor: Colors.red));
                        return;
                      }
                      _navigateTo(Scaffold(
                        appBar: AppBar(title: const Text('التقارير والأرباح'), backgroundColor: Colors.purple),
                        body: ReportsAndBackupWidget(
                          products: _productsDB, suppliers: _suppliersDB, invoices: _invoices,
                          vouchers: _vouchers, debtPayments: _debtPayments, onUpdate: () => {setState(() {}), _saveDataLocally()},
                          onDeleteInvoice: _deleteInvoice, isAdmin: widget.isAdmin,
                        ),
                      ));
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: color),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// ================= 4. Barcode Scanner Screen =================
class BarcodeScannerScreen extends StatelessWidget {
  const BarcodeScannerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مسح باركود المادة')),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
              break;
            }
          }
        },
      ),
    );
  }
}

// ================= 5. Product Catalog =================
class ProductCatalogWidget extends StatefulWidget {
  final List<ProductModel> products;
  final VoidCallback onUpdate;
  final bool isAdmin;
  final ProductModel? targetProductToEdit;
  const ProductCatalogWidget({super.key, required this.products, required this.onUpdate, required this.isAdmin, this.targetProductToEdit});
  @override
  State<ProductCatalogWidget> createState() => _ProductCatalogWidgetState();
}

class _ProductCatalogWidgetState extends State<ProductCatalogWidget> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _buyPriceController = TextEditingController();
  final TextEditingController _sellPriceController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _baseRatioController = TextEditingController(text: '1.0');
  final TextEditingController _minAlertController = TextEditingController(text: '5.0');
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController(text: 'ألبان وأجبان');
  final TextEditingController _maxCapacityController = TextEditingController(text: '100');
  final TextEditingController _splitFactorController = TextEditingController(text: '30');
  final TextEditingController _subUnitNameController = TextEditingController(text: 'بيضة');
  final TextEditingController _unitSellingPriceController = TextEditingController(text: '0');

  String _selectedUnit = 'كيلو';
  bool _canBeUsedAsIngredient = false;
  bool _isManufactured = false;
  bool _isSplitProduct = false;
  final List<String> _unitsList = ['كيلو', 'غرام', 'ليتر', 'صحن', 'كرتونة', 'علبة', 'قطعة', 'كيس', 'باكيت'];
  final List<String> _categoriesList = ['ألبان وأجبان', 'غذائيات', 'بسكويت'];
  String _filterCategory = 'الكل';

  @override
  void initState() {
    super.initState();
    if (widget.targetProductToEdit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openProductCardSheet(product: widget.targetProductToEdit));
    }
  }

  Future<void> _scanBarcodeForCard(StateSetter setSheetState) async {
    final scannedCode = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()));
    if (scannedCode != null) setSheetState(() => _barcodeController.text = scannedCode);
  }

  void _openProductCardSheet({ProductModel? product}) {
    if (product != null) {
      _nameController.text = product.name;
      _buyPriceController.text = product.purchasePrice.toString();
      _sellPriceController.text = product.sellingPrice.toString();
      _barcodeController.text = product.barcode;
      _selectedUnit = product.unit;
      _canBeUsedAsIngredient = product.canBeUsedAsIngredient;
      _isManufactured = product.isManufactured;
      _baseRatioController.text = product.baseIngredientRequiredPerUnit.toString();
      _minAlertController.text = product.minStockAlert.toString();
      _notesController.text = product.notes;
      _categoryController.text = product.category;
      _isSplitProduct = product.isSplitProduct;
      _splitFactorController.text = product.splitFactor.toString();
      _subUnitNameController.text = product.subUnitName;
      _unitSellingPriceController.text = product.unitSellingPrice.toString();
      _maxCapacityController.text = product.maxCapacity.toString();
    } else {
      _nameController.clear(); _buyPriceController.clear(); _sellPriceController.clear(); _barcodeController.clear();
      _selectedUnit = 'كيلو'; _canBeUsedAsIngredient = false; _isManufactured = false; _isSplitProduct = false;
      _baseRatioController.text = '1.0'; _minAlertController.text = '5.0'; _notesController.clear();
      _categoryController.text = 'ألبان وأجبان'; _maxCapacityController.text = '100';
      _splitFactorController.text = '30'; _subUnitNameController.text = 'بيضة'; _unitSellingPriceController.text = '0';
    }

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            double buyP = double.tryParse(_buyPriceController.text) ?? 0;
            double sellP = double.tryParse(_sellPriceController.text) ?? 0;
            double estimatedProfit = sellP - buyP;
            double profitMargin = sellP > 0 ? (estimatedProfit / sellP) * 100 : 0;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 16, right: 16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [const Icon(Icons.category, color: Colors.brown), const SizedBox(width: 8), Text(product == null ? 'إضافة مادة جديدة' : 'تعديل المادة', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown))]),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const Divider(),
                      TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'اسم المادة', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _barcodeController, decoration: const InputDecoration(labelText: 'الباركود', border: OutlineInputBorder(), isDense: true))),
                          const SizedBox(width: 6),
                          IconButton(icon: const Icon(Icons.qr_code_scanner, color: Colors.indigo), onPressed: () => _scanBarcodeForCard(setSheetState)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _categoriesList.contains(_categoryController.text) ? _categoryController.text : 'ألبان وأجبان',
                              decoration: const InputDecoration(labelText: 'الصنف الأساسي', border: OutlineInputBorder(), isDense: true),
                              items: _categoriesList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (v) => setSheetState(() => _categoryController.text = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedUnit,
                              decoration: const InputDecoration(labelText: 'وحدة القياس', border: OutlineInputBorder(), isDense: true),
                              items: _unitsList.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (v) => setSheetState(() => _selectedUnit = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _buyPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر التكلفة', border: OutlineInputBorder(), isDense: true), onChanged: (v) => setSheetState(() {}))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _sellPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع', border: OutlineInputBorder(), isDense: true), onChanged: (v) => setSheetState(() {}))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('الربح التقديري: ${formatNumber(estimatedProfit)} ل.س', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            Text('النسبة: ${formatDecimal(profitMargin)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ),
                      CheckboxListTile(
                        dense: true, title: const Text('تفعيل التجزئة (جملة ومفرق)'),
                        value: _isSplitProduct, onChanged: (v) => setSheetState(() => _isSplitProduct = v ?? false),
                      ),
                      if (_isSplitProduct) ...[
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _splitFactorController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد القطع (30)', border: OutlineInputBorder(), isDense: true))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: _subUnitNameController, decoration: const InputDecoration(labelText: 'اسم القطعة (بيضة)', border: OutlineInputBorder(), isDense: true))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(controller: _unitSellingPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر بيع القطعة مفرق', border: OutlineInputBorder(), isDense: true)),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                          onPressed: () {
                            if (_nameController.text.isNotEmpty) {
                              setState(() {
                                double maxCap = double.tryParse(_maxCapacityController.text) ?? 100.0;
                                if (product == null) {
                                  widget.products.add(ProductModel(
                                    id: DateTime.now().toString(),
                                    name: _nameController.text.trim(),
                                    purchasePrice: double.tryParse(_buyPriceController.text) ?? 0,
                                    sellingPrice: double.tryParse(_sellPriceController.text) ?? 0,
                                    stockQuantity: 0,
                                    barcode: _barcodeController.text.trim(),
                                    unit: _selectedUnit,
                                    canBeUsedAsIngredient: _canBeUsedAsIngredient,
                                    isManufactured: _isManufactured,
                                    baseIngredientRequiredPerUnit: double.tryParse(_baseRatioController.text) ?? 1.0,
                                    minStockAlert: double.tryParse(_minAlertController.text) ?? 5.0,
                                    notes: _notesController.text.trim(),
                                    category: _categoryController.text.trim(),
                                    isSplitProduct: _isSplitProduct,
                                    splitFactor: double.tryParse(_splitFactorController.text) ?? 1.0,
                                    subUnitName: _subUnitNameController.text.trim(),
                                    unitSellingPrice: double.tryParse(_unitSellingPriceController.text) ?? 0,
                                    maxCapacity: maxCap > 0 ? maxCap : 100.0,
                                  ));
                                } else {
                                  product.name = _nameController.text.trim();
                                  product.purchasePrice = double.tryParse(_buyPriceController.text) ?? 0;
                                  product.sellingPrice = double.tryParse(_sellPriceController.text) ?? 0;
                                  product.barcode = _barcodeController.text.trim();
                                  product.unit = _selectedUnit;
                                  product.canBeUsedAsIngredient = _canBeUsedAsIngredient;
                                  product.isManufactured = _isManufactured;
                                  product.baseIngredientRequiredPerUnit = double.tryParse(_baseRatioController.text) ?? 1.0;
                                  product.minStockAlert = double.tryParse(_minAlertController.text) ?? 5.0;
                                  product.notes = _notesController.text.trim();
                                  product.category = _categoryController.text.trim();
                                  product.isSplitProduct = _isSplitProduct;
                                  product.splitFactor = double.tryParse(_splitFactorController.text) ?? 1.0;
                                  product.subUnitName = _subUnitNameController.text.trim();
                                  product.unitSellingPrice = double.tryParse(_unitSellingPriceController.text) ?? 0;
                                  product.maxCapacity = maxCap > 0 ? maxCap : 100.0;
                                }
                              });
                              widget.onUpdate();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المادة بنجاح!'), backgroundColor: Colors.green));
                            }
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ المادة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<ProductModel> displayedProducts = _filterCategory == 'الكل'
        ? widget.products
        : widget.products.where((p) => p.category == _filterCategory).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة كتالوج المواد والأصناف'),
          backgroundColor: Colors.brown.shade100,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: Colors.white,
              child: Row(
                children: [
                  const Text('فرز حسب الصنف: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true, value: _filterCategory,
                      items: ['الكل', 'ألبان وأجبان', 'غذائيات', 'بسكويت'].map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setState(() => _filterCategory = v!),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: ListView.builder(
          itemCount: displayedProducts.length,
          itemBuilder: (ctx, idx) {
            final p = displayedProducts[idx];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: p.isManufactured ? Colors.teal.shade100 : (p.isSplitProduct ? Colors.brown.shade100 : Colors.amber.shade100),
                  child: Icon(p.isManufactured ? Icons.precision_manufacturing : (p.isSplitProduct ? Icons.call_split : Icons.category), color: Colors.brown),
                ),
                title: Text('${p.name} [${p.category}]', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('التكلفة: ${formatNumber(p.purchasePrice)} | البيع: ${formatNumber(p.sellingPrice)} (${p.unit})'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _openProductCardSheet(product: p)),
                    if (widget.isAdmin)
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                        setState(() => widget.products.remove(p));
                        widget.onUpdate();
                      }),
                  ],
                ),
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Colors.brown,
          onPressed: () => _openProductCardSheet(),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('إضافة مادة جديدة', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

// ================= 6. Stock Management =================
class StockManagementWidget extends StatefulWidget {
  final List<ProductModel> products;
  final List<PaymentVoucherModel> vouchers;
  final List<SupplierModel> suppliers;
  final VoidCallback onUpdate;
  final bool isAdmin;
  const StockManagementWidget({super.key, required this.products, required this.vouchers, required this.suppliers, required this.onUpdate, required this.isAdmin});

  @override
  State<StockManagementWidget> createState() => _StockManagementWidgetState();
}

class _StockManagementWidgetState extends State<StockManagementWidget> {
  String _stockFilterCategory = 'الكل';

  @override
  Widget build(BuildContext context) {
    List<ProductModel> filteredStock = _stockFilterCategory == 'الكل'
        ? widget.products
        : widget.products.where((p) => p.category == _stockFilterCategory).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المخزن والترتيب'),
          backgroundColor: Colors.orange.shade100,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: Colors.white,
              child: Row(
                children: [
                  const Text('ترتيب المخزن حسب الصنف: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true, value: _stockFilterCategory,
                      items: ['الكل', 'ألبان وأجبان', 'غذائيات', 'بسكويت'].map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setState(() => _stockFilterCategory = v!),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: ListView.builder(
          itemCount: filteredStock.length,
          itemBuilder: (ctx, idx) {
            final p = filteredStock[idx];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: ListTile(
                title: Text('${p.name} [${p.category}]', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('الرصيد الحالي: ${formatDecimal(p.stockQuantity)} ${p.unit}'),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                  onPressed: () {
                    final TextEditingController qtyEditCtrl = TextEditingController(text: p.stockQuantity.toString());
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('تعديل مخزون: ${p.name}'),
                        content: TextField(controller: qtyEditCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'الكمية بـ (${p.unit})')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                          ElevatedButton(onPressed: () {
                            setState(() => p.stockQuantity = double.tryParse(qtyEditCtrl.text) ?? p.stockQuantity);
                            widget.onUpdate();
                            Navigator.pop(ctx);
                          }, child: const Text('حفظ')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ================= 7. Advanced Production Module =================
class AdvancedProductionWidget extends StatefulWidget {
  final List<ProductModel> products;
  final List<PaymentVoucherModel> vouchers;
  final VoidCallback onUpdate;
  final bool isAdmin;
  const AdvancedProductionWidget({super.key, required this.products, required this.vouchers, required this.onUpdate, required this.isAdmin});

  @override
  State<AdvancedProductionWidget> createState() => _AdvancedProductionWidgetState();
}

class _AdvancedProductionWidgetState extends State<AdvancedProductionWidget> {
  ProductModel? _selectedSourceIngredient;
  ProductModel? _selectedTargetProduct;
  final TextEditingController _producedQtyController = TextEditingController(text: '10');

  @override
  Widget build(BuildContext context) {
    final ingredientList = widget.products.where((p) => p.canBeUsedAsIngredient).toList();
    final manufacturedList = widget.products.where((p) => p.isManufactured).toList();

    if (ingredientList.isNotEmpty && (_selectedSourceIngredient == null || !ingredientList.contains(_selectedSourceIngredient))) {
      _selectedSourceIngredient = ingredientList.first;
    }
    if (manufacturedList.isNotEmpty && (_selectedTargetProduct == null || !manufacturedList.contains(_selectedTargetProduct))) {
      _selectedTargetProduct = manufacturedList.first;
    }

    double producedQty = double.tryParse(_producedQtyController.text) ?? 0;
    double neededIngredientQty = (_selectedTargetProduct != null) ? (producedQty * _selectedTargetProduct!.baseIngredientRequiredPerUnit) : 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            const Text('وحدة التصنيع والتشغيل', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal)),
            const Divider(),
            DropdownButtonFormField<ProductModel>(
              value: _selectedSourceIngredient,
              decoration: const InputDecoration(labelText: 'المادة الأساسية (خام)', border: OutlineInputBorder()),
              items: ingredientList.map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (${formatDecimal(p.stockQuantity)})'))).toList(),
              onChanged: (v) => setState(() => _selectedSourceIngredient = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ProductModel>(
              value: _selectedTargetProduct,
              decoration: const InputDecoration(labelText: 'المادة المصنعة الناتجة', border: OutlineInputBorder()),
              items: manufacturedList.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
              onChanged: (v) => setState(() => _selectedTargetProduct = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: _producedQtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية المنتجة', border: OutlineInputBorder()), onChanged: (v) => setState(() {})),
            const SizedBox(height: 15),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () {
                if (_selectedSourceIngredient == null || _selectedTargetProduct == null || producedQty <= 0) return;
                if (_selectedSourceIngredient!.stockQuantity < neededIngredientQty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الكمية الأساسية الخام غير كافية بالمخزن!'), backgroundColor: Colors.red));
                  return;
                }
                setState(() {
                  _selectedSourceIngredient!.stockQuantity -= neededIngredientQty;
                  _selectedTargetProduct!.stockQuantity += producedQty;
                });
                widget.onUpdate();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التصنيع بنجاح!'), backgroundColor: Colors.green));
              },
              child: const Text('اعتماد التصنيع'),
            )
          ],
        ),
      ),
    );
  }
}

// ================= 8. Invoices Manager =================
class InvoicesManagerWidget extends StatefulWidget {
  final List<InvoiceModel> invoices;
  final InvoiceType type;
  final Function(InvoiceModel) onDelete;
  final bool isAdmin;
  const InvoicesManagerWidget({super.key, required this.invoices, required this.type, required this.onDelete, required this.isAdmin});

  @override
  State<InvoicesManagerWidget> createState() => _InvoicesManagerWidgetState();
}

class _InvoicesManagerWidgetState extends State<InvoicesManagerWidget> {
  @override
  Widget build(BuildContext context) {
    List<InvoiceModel> filtered = widget.invoices.where((i) => i.type == widget.type).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إدارة الفواتير'), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
        body: filtered.isEmpty
            ? const Center(child: Text('لا توجد فواتير مسجلة'))
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, idx) {
                  final inv = filtered.reversed.toList()[idx];
                  return Card(
                    child: ListTile(
                      title: Text('${inv.partyName} - ${formatNumber(inv.totalAmount)} ل.س', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('الحالة: ${inv.isDebt ? "آجل" : "نقدي"} | الربح: ${formatNumber(inv.totalProfit)}'),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                        widget.onDelete(inv);
                        setState(() {});
                      }),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ================= 9. Invoice Builder =================
class InvoiceBuilderWidget extends StatefulWidget {
  final InvoiceType type;
  final List<ProductModel> products;
  final List<SupplierModel> suppliers;
  final Function(InvoiceModel, bool) onSubmit;
  const InvoiceBuilderWidget({super.key, required this.type, required this.products, required this.suppliers, required this.onSubmit});

  @override
  State<InvoiceBuilderWidget> createState() => _InvoiceBuilderWidgetState();
}

class _InvoiceBuilderWidgetState extends State<InvoiceBuilderWidget> {
  final List<InvoiceItem> _items = [];
  final TextEditingController _partyController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '1');
  ProductModel? _selectedProduct;
  bool _isDebt = false;

  @override
  void initState() {
    super.initState();
    if (widget.products.isNotEmpty) _selectedProduct = widget.products.first;
  }

  void _addItem() {
    if (_selectedProduct == null) return;
    double qty = double.tryParse(_qtyController.text) ?? 0;
    if (qty <= 0) return;
    double price = widget.type == InvoiceType.sales ? _selectedProduct!.sellingPrice : _selectedProduct!.purchasePrice;

    setState(() {
      _items.add(InvoiceItem(product: _selectedProduct!, quantity: qty, priceUsed: price, unitLabelUsed: _selectedProduct!.unit));
      _qtyController.text = '1';
    });
  }

  void _saveInvoice() {
    if (_items.isEmpty) return;
    double subTotal = _items.fold(0, (sum, i) => sum + i.total);
    double profit = widget.type == InvoiceType.sales ? _items.fold(0, (sum, i) => sum + i.profit) : 0;
    String party = _partyController.text.trim().isEmpty ? (widget.type == InvoiceType.sales ? 'زبون عام' : 'مورد عام') : _partyController.text.trim();

    InvoiceModel inv = InvoiceModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      partyName: party, items: List.from(_items), subTotal: subTotal,
      totalAmount: subTotal, totalProfit: profit, date: DateTime.now(),
      type: widget.type, isDebt: _isDebt,
    );

    widget.onSubmit(inv, _isDebt);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الفاتورة محلياً بنجاح!'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isNotEmpty && (_selectedProduct == null || !widget.products.contains(_selectedProduct))) {
      _selectedProduct = widget.products.first;
    }
    double total = _items.fold(0, (s, i) => s + i.total);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(controller: _partyController, decoration: const InputDecoration(labelText: 'اسم الزبون / المورد', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            DropdownButtonFormField<ProductModel>(
              value: _selectedProduct,
              decoration: const InputDecoration(labelText: 'اختر المادة', border: OutlineInputBorder(), isDense: true),
              items: widget.products.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
              onChanged: (v) => setState(() => _selectedProduct = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder(), isDense: true))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _addItem, child: const Text('إضافة للمواد')),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (ctx, idx) {
                  final item = _items[idx];
                  return ListTile(
                    title: Text(item.product.name),
                    subtitle: Text('${formatDecimal(item.quantity)} × ${formatNumber(item.priceUsed)}'),
                    trailing: Text('${formatNumber(item.total)} ل.س'),
                  );
                },
              ),
            ),
            Text('الإجمالي: ${formatNumber(total)} ل.س', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SwitchListTile(title: const Text('فاتورة آجلة (دين)'), value: _isDebt, onChanged: (v) => setState(() => _isDebt = v)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(45)),
              onPressed: _saveInvoice,
              child: const Text('حفظ الفاتورة محلياً'),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 10. Suppliers =================
class SuppliersWidget extends StatelessWidget {
  final List<SupplierModel> suppliers;
  final List<InvoiceModel> invoices;
  final VoidCallback onUpdate;
  final bool isAdmin;
  const SuppliersWidget({super.key, required this.suppliers, required this.invoices, required this.onUpdate, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الموردين'), backgroundColor: Colors.indigo.shade100),
        body: ListView.builder(
          itemCount: suppliers.length,
          itemBuilder: (ctx, idx) => Card(child: ListTile(title: Text(suppliers[idx].name), subtitle: Text(suppliers[idx].phone))),
        ),
      ),
    );
  }
}

// ================= 11. Payment Vouchers =================
class PaymentVouchersWidget extends StatelessWidget {
  final List<PaymentVoucherModel> vouchers;
  final VoidCallback onUpdate;
  final bool isAdmin;
  const PaymentVouchersWidget({super.key, required this.vouchers, required this.onUpdate, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المصاريف'), backgroundColor: Colors.red.shade100),
        body: ListView.builder(
          itemCount: vouchers.length,
          itemBuilder: (ctx, idx) => Card(child: ListTile(title: Text(vouchers[idx].title), trailing: Text('${formatNumber(vouchers[idx].amount)}'))),
        ),
      ),
    );
  }
}

// ================= 12. Debts =================
class DebtsWidget extends StatelessWidget {
  final List<InvoiceModel> invoices;
  final List<DebtPaymentModel> debtPayments;
  final Function(DebtPaymentModel) onAddPayment;
  const DebtsWidget({super.key, required this.invoices, required this.debtPayments, required this.onAddPayment});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سجل الديون')),
        body: const Center(child: Text('قسم الديون والذمم')),
      ),
    );
  }
}

// ================= 13. Reports, Export/Import (زر مزامنة الموظف) =================
class ReportsAndBackupWidget extends StatefulWidget {
  final List<ProductModel> products;
  final List<SupplierModel> suppliers;
  final List<InvoiceModel> invoices;
  final List<PaymentVoucherModel> vouchers;
  final List<DebtPaymentModel> debtPayments;
  final VoidCallback onUpdate;
  final Function(InvoiceModel) onDeleteInvoice;
  final bool isAdmin;

  const ReportsAndBackupWidget({
    super.key, required this.products, required this.suppliers, required this.invoices,
    required this.vouchers, required this.debtPayments, required this.onUpdate,
    required this.onDeleteInvoice, required this.isAdmin,
  });

  @override
  State<ReportsAndBackupWidget> createState() => _ReportsAndBackupWidgetState();
}

class _ReportsAndBackupWidgetState extends State<ReportsAndBackupWidget> {
  // تصدير بيانات الموظف لنقلها إلى جهاز المدير عبر الواي فاي
  void _exportSubAccountDataForSync() {
    Map<String, dynamic> subData = {
      'invoices': widget.invoices.map((i) => i.toJson()).toList(),
    };
    String jsonString = jsonEncode(subData);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصدير فواتير الموظف للمزامنة'),
        content: SizedBox(
          width: 350,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('انسخ هذا الكود بالكامل، واذهب إلى جهاز المدير واضغط زر "مزامنة الموظف" وألصقه هناك:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                SelectableText(jsonString, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double sales = widget.invoices.where((i) => i.type == InvoiceType.sales).fold(0, (s, i) => s + i.totalAmount);
    double profit = widget.invoices.where((i) => i.type == InvoiceType.sales).fold(0, (s, i) => s + i.totalProfit);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التقارير والمزامنة المحلية')),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isAdmin)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                  onPressed: _exportSubAccountDataForSync,
                  icon: const Icon(Icons.share),
                  label: const Text('تصدير بيانات الموظف للمزامنة مع المدير', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('المبيعات: ${formatNumber(sales)} ل.س')))),
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('الأرباح: ${formatNumber(profit)} ل.س', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))))),
                ],
              ),
              const SizedBox(height: 10),
              const Text('سجل الفواتير:', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.invoices.length,
                  itemBuilder: (ctx, idx) {
                    final inv = widget.invoices.reversed.toList()[idx];
                    return Card(child: ListTile(title: Text('${inv.partyName} - ${formatNumber(inv.totalAmount)} ل.س')));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= 14. الإعدادات =================
class AppSettingsWidget extends StatefulWidget {
  final bool isAdmin;
  final VoidCallback onUpdate;
  const AppSettingsWidget({super.key, required this.isAdmin, required this.onUpdate});

  @override
  State<AppSettingsWidget> createState() => _AppSettingsWidgetState();
}

class _AppSettingsWidgetState extends State<AppSettingsWidget> {
  final TextEditingController _adminPassCtrl = TextEditingController(text: AppSettings.adminPassword);
  final TextEditingController _subPassCtrl = TextEditingController(text: AppSettings.subAccountPassword);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات'), backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              TextField(controller: _adminPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة مرور المدير', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _subPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة مرور الموظف', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                onPressed: () {
                  if (widget.isAdmin) {
                    AppSettings.adminPassword = _adminPassCtrl.text.trim();
                    AppSettings.subAccountPassword = _subPassCtrl.text.trim();
                  }
                  widget.onUpdate();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ بنجاح!'), backgroundColor: Colors.green));
                },
                child: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
