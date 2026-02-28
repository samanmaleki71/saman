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

  // صفحه‌ای که شورتکد افزونه داخلش هست:
  static const String url = 'https://faryazandecor.com/add';

  @override
  void initState() {
    super.initState();

    final params = const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));

    // فقط اندروید: هندل کردن <input type="file"> داخل WebView
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnShowFileSelector((FileSelectorParams p) async {
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
          final editedPath = await _cropAndBrightness(x.path);
          if (editedPath != null) outPaths.add(editedPath);
        }
        return outPaths; // مسیر فایل‌های نهایی برای آپلود در فرم سایت
      });
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
    if (cropped == null) return null;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
