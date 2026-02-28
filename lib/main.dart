import 'dart:io';
import 'dart:math';

import 'package:faryazan_uploader/http_override.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const UploaderWebView(),
    );
  }
}

class UploaderWebView extends StatefulWidget {
  const UploaderWebView({super.key});

  @override
  State<UploaderWebView> createState() => _UploaderWebViewState();
}

class _UploaderWebViewState extends State<UploaderWebView> {
  late final WebViewController _controller;

  static const String defaultUrl = 'https://faryazandecor.com/add';

  final TextEditingController _addressCtrl = TextEditingController();
  String _currentUrl = defaultUrl;

  @override
  void initState() {
    super.initState();

    final params = const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            final u = change.url;
            if (u != null && u.isNotEmpty) {
              setState(() {
                _currentUrl = u;
                _addressCtrl.text = u;
              });
            }
          },
          onPageFinished: (u) {
            if (u.isNotEmpty) {
              setState(() {
                _currentUrl = u;
                _addressCtrl.text = u;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(defaultUrl));

    _addressCtrl.text = defaultUrl;

    // فقط اندروید: هندل کردن <input type="file"> داخل WebView
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnShowFileSelector((FileSelectorParams p) async {
        try {
          final picker = ImagePicker();

          final List<XFile> picked;
          if (p.mode == FileSelectorMode.openMultiple) {
            picked = await picker.pickMultiImage(imageQuality: 95);
          } else {
            final one = await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 95,
            );
            picked = one == null ? <XFile>[] : <XFile>[one];
          }

          if (picked.isEmpty) return <String>[];

          final outPaths = <String>[];
          for (final x in picked) {
            // اگر کراپ/نور خطا داد یا نمایش داده نشد، کرش نکنه و فایل اصلی رو بده
            String finalPath = x.path;
            try {
              final editedPath = await _cropAndBrightness(x.path);
              if (editedPath != null && editedPath.isNotEmpty) {
                finalPath = editedPath;
              }
            } catch (_) {
              // fallback: original path
              finalPath = x.path;
            }
            outPaths.add(finalPath);
          }

          return outPaths; // مسیر فایل‌های نهایی برای آپلود در فرم سایت
        } catch (_) {
          // مهم: هیچ وقت باعث خروج/کرش نشه
          return <String>[];
        }
      });
    }
  }

  Future<void> _goToAddressBarUrl() async {
    final raw = _addressCtrl.text.trim();
    if (raw.isEmpty) return;

    String u = raw;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }

    try {
      await _controller.loadRequest(Uri.parse(u));
    } catch (_) {
      // اگر آدرس غلط بود، هیچی
    }
  }

  Future<String?> _cropAndBrightness(String inputPath) async {
    // 1) Crop
    final cropped = await ImageCropper().cropImage(
      sourcePath: inputPath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop',
          lockAspectRatio: false,
        ),
      ],
    );

    // اگر کاربر Cancel زد، همون فایل اصلی رو بده (تا اپ خارج نشه)
    if (cropped == null) return inputPath;

    // 2) Brightness (اختیاری)
    final brightness = await _askBrightness(); // -100..+100 یا null
    if (brightness == null) return cropped.path;

    final bytes = await File(cropped.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return cropped.path;

    final adjusted = img.adjustColor(decoded, brightness: brightness / 100);

    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/fz_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.jpg',
    );
    await out.writeAsBytes(img.encodeJpg(adjusted, quality: 95));

    return out.path;
  }

  Future<int?> _askBrightness() async {
    int val = 0; // -100..+100
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text('نور'),
          content: StatefulBuilder(
            builder: (ctx, setSt) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(val.toString()),
                Slider(
                  min: -100,
                  max: 100,
                  value: val.toDouble(),
                  onChanged: (v) => setSt(() => val = v.round()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, val),
              child: const Text('اعمال'),
            ),
          ],
        );
      },
    );
  }

  Widget _addressBar() {
    return Material(
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () async {
                  final can = await _controller.canGoBack();
                  if (can) {
                    await _controller.goBack();
                  } else {
                    if (mounted) Navigator.maybePop(context);
                  }
                },
                icon: const Icon(Icons.arrow_back),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => _controller.reload(),
                icon: const Icon(Icons.refresh),
              ),
              Expanded(
                child: TextField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'آدرس را وارد کن…',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _goToAddressBarUrl(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _goToAddressBarUrl,
                child: const Text('Go'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // _currentUrl فقط برای اینکه بفهمی آپدیت میشه (فعلاً لازم نیست نمایش جداگانه بدیم)
    // ignore: unused_local_variable
    final _ = _currentUrl;

    return Scaffold(
      body: Column(
        children: [
          _addressBar(),
          Expanded(
            child: SafeArea(
              top: false,
              child: WebViewWidget(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }
}
