import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import '../receipt_ocr_service.dart';
import 'image_pick_adapter.dart';

/// タイムアウト安全弁（秒）: 全経路で Future 未完了を防止
const int _pickerTimeoutSeconds = 120;

/// focus 復帰後のキャンセル判定猶予（ミリ秒）
const int _focusCancelDelayMs = 800;

/// Web向け画像取得アダプタ（直接 file input 管理）
///
/// `image_picker_for_web` の内部 hidden input に依存せず、
/// アプリ側で `<input type="file">` を直接生成・監視する。
/// mobile Web（iOS Safari / Android Chrome）での file picker 起動安定性を向上。
///
/// 起動方式:
/// - `showPicker()` を優先（mobile Web で安定）
/// - 非対応時は `click()` にフォールバック
/// - `display: none` は使わず、不可視配置でブラウザの起動制約を回避
///
/// イベント分類:
/// - `change`: ファイル選択完了 → サイズ/形式検証 → success or エラー
/// - `cancel`: ユーザーがダイアログを閉じた → canceled
/// - `error`: input 要素エラー → browserBlocked
/// - window `focus` 復帰: cancel 非対応ブラウザ向けフォールバック → canceled
/// - タイムアウト（120秒）: 安全弁 → canceled
/// - `showPicker()` / `click()` 例外: ブラウザ制約で開始不可 → browserBlocked
/// - FileReader エラー: 読み込み失敗 → fileReadError
class WebImagePickAdapter implements ImagePickAdapter {
  @override
  Future<PickImageResult> pickImage(ImageSource source) async {
    final completer = Completer<PickImageResult>();

    // <input type="file"> を生成
    // display: none は mobile Web で起動がブロックされるため、
    // DOM に存在しレンダリング対象だが不可視な状態にする
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    input.accept = 'image/jpeg,image/png';
    input.style.cssText =
        'position:fixed;top:-100px;left:-100px;'
        'width:1px;height:1px;opacity:0;overflow:hidden;';

    final body = web.document.body;
    if (body == null) {
      debugPrint('WebImagePickAdapter: document.body が null');
      return PickImageResult(
        PickImageStatus.browserBlocked,
        errorDetail: PickImageStatus.browserBlocked.defaultMessage,
      );
    }
    body.appendChild(input);

    Timer? focusFallbackTimer;
    Timer? timeoutTimer;
    JSFunction? focusListener;
    bool completed = false;
    bool fileSelected = false;

    /// 結果を確定し、全リソースをクリーンアップする
    void doComplete(PickImageResult result) {
      if (completed) return;
      completed = true;
      focusFallbackTimer?.cancel();
      timeoutTimer?.cancel();
      if (focusListener != null) {
        web.window.removeEventListener('focus', focusListener);
      }
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      try {
        input.remove();
      } catch (_) {}
    }

    // ─── イベントリスナー登録 ───

    // change: ファイルが選択された
    input.addEventListener(
      'change',
      ((web.Event e) {
        final files = input.files;
        if (files == null || files.length == 0) {
          doComplete(const PickImageResult(PickImageStatus.canceled));
          return;
        }

        final file = files.item(0)!;
        // ファイル選択済みフラグ: focus フォールバックの誤発火を防止
        fileSelected = true;

        // サイズ事前チェック（readAsArrayBuffer 前にメモリ負荷を回避）
        if (file.size > maxPickFileSizeBytes) {
          final sizeMB = (file.size / (1024 * 1024)).toStringAsFixed(1);
          doComplete(PickImageResult(
            PickImageStatus.fileTooLarge,
            errorDetail:
                '画像サイズが大きすぎます（${sizeMB}MB）。10MB以下の画像を選択してください。',
          ));
          return;
        }

        // FileReader でバイト列を読み取り
        _readFileAsBytes(file).then(doComplete);
      }).toJS,
    );

    // cancel: ユーザーがダイアログを閉じた（対応ブラウザのみ）
    input.addEventListener(
      'cancel',
      ((web.Event e) {
        debugPrint('WebImagePickAdapter: cancel イベント検出');
        doComplete(const PickImageResult(PickImageStatus.canceled));
      }).toJS,
    );

    // error: input 要素のエラー
    input.addEventListener(
      'error',
      ((web.Event e) {
        debugPrint('WebImagePickAdapter: input error イベント');
        doComplete(PickImageResult(
          PickImageStatus.browserBlocked,
          errorDetail: PickImageStatus.browserBlocked.defaultMessage,
        ));
      }).toJS,
    );

    // ─── file picker を開く ───

    try {
      // showPicker() を優先: mobile Web で安定性が高い
      try {
        input.showPicker();
      } catch (_) {
        // showPicker() 非対応時は click() にフォールバック
        debugPrint(
          'WebImagePickAdapter: showPicker() 非対応、click() にフォールバック',
        );
        input.click();
      }
    } catch (e) {
      debugPrint('WebImagePickAdapter: file picker 起動エラー: $e');
      doComplete(PickImageResult(
        PickImageStatus.browserBlocked,
        errorDetail: PickImageStatus.browserBlocked.defaultMessage,
      ));
      return completer.future;
    }

    // ─── キャンセル検出フォールバック ───

    // cancel 非対応ブラウザ向け: window focus 復帰でキャンセルを推定
    // file picker が閉じると window に focus が戻る。
    // ファイル未選択のまま focus 復帰した場合のみキャンセルと判定する。
    // fileSelected が true（FileReader 読み込み中）の場合は発火しない。
    focusListener = ((web.Event e) {
      focusFallbackTimer?.cancel();
      focusFallbackTimer = Timer(
        const Duration(milliseconds: _focusCancelDelayMs),
        () {
          if (!completed && !fileSelected) {
            debugPrint('WebImagePickAdapter: focus 復帰によるキャンセル判定');
            doComplete(const PickImageResult(PickImageStatus.canceled));
          }
        },
      );
    }).toJS;
    web.window.addEventListener('focus', focusListener);

    // タイムアウト安全弁: 全経路で Future 未完了を防止
    timeoutTimer = Timer(
      const Duration(seconds: _pickerTimeoutSeconds),
      () {
        if (!completed) {
          debugPrint('WebImagePickAdapter: タイムアウト（$_pickerTimeoutSeconds秒）');
          doComplete(const PickImageResult(PickImageStatus.canceled));
        }
      },
    );

    return completer.future;
  }

  /// FileReader でファイルをバイト列として読み取り、検証する
  Future<PickImageResult> _readFileAsBytes(web.File file) {
    final completer = Completer<PickImageResult>();
    final reader = web.FileReader();

    // 読み込み完了
    reader.addEventListener(
      'load',
      ((web.Event e) {
        try {
          final arrayBuffer = reader.result as JSArrayBuffer;
          final bytes = arrayBuffer.toDart.asUint8List();

          // バイト列検証（形式チェック）
          final validation = validateImageBytes(bytes);
          if (validation != null) {
            completer.complete(validation);
            return;
          }

          completer.complete(
            PickImageResult(PickImageStatus.success, imageBytes: bytes),
          );
        } catch (e) {
          debugPrint('WebImagePickAdapter: バイト変換エラー: $e');
          completer.complete(PickImageResult(
            PickImageStatus.fileReadError,
            errorDetail: PickImageStatus.fileReadError.defaultMessage,
          ));
        }
      }).toJS,
    );

    // 読み込みエラー
    reader.addEventListener(
      'error',
      ((web.Event e) {
        debugPrint(
          'WebImagePickAdapter: FileReader エラー: ${reader.error?.message}',
        );
        completer.complete(PickImageResult(
          PickImageStatus.fileReadError,
          errorDetail: PickImageStatus.fileReadError.defaultMessage,
        ));
      }).toJS,
    );

    reader.readAsArrayBuffer(file);
    return completer.future;
  }

  @override
  void dispose() {}
}

ImagePickAdapter createImagePickAdapter() => WebImagePickAdapter();
