import 'image_pick_adapter.dart';

import 'image_pick_adapter_stub.dart'
    if (dart.library.io) 'image_pick_adapter_mobile.dart'
    if (dart.library.js_interop) 'image_pick_adapter_web.dart' as platform;

/// プラットフォーム別に画像取得アダプタを生成するファクトリ
ImagePickAdapter createImagePickAdapter() => platform.createImagePickAdapter();
