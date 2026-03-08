import 'receipt_image_preprocessor.dart';

import 'receipt_image_preprocessor_stub.dart'
    if (dart.library.io) 'receipt_image_preprocessor_mobile.dart' as platform;

/// プラットフォーム別に前処理を生成するファクトリ
ReceiptImagePreprocessor createImagePreprocessor() =>
    platform.createImagePreprocessor();
