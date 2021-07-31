import 'dart:async';
import 'package:flutter/services.dart';

import './enums/key_code.dart';
import './enums/key_modifier.dart';
import './hotkey.dart';

typedef HotKeyHandler = void Function(HotKey hotKey);

class HotKeyManager {
  HotKeyManager._();

  /// The shared instance of [HotKeyManager].
  static final HotKeyManager instance = HotKeyManager._();

  final MethodChannel _channel = const MethodChannel('hotkey_manager');

  bool _inited = false;
  List<HotKey> _hotKeyList = [];
  Map<String, HotKeyHandler> _keyDownHandlerMap = {};
  Map<String, HotKeyHandler> _keyUpHandlerMap = {};

  // 最后按下的快捷键
  HotKey? _lastPressedHotKey;

  void _init() {
    RawKeyboard.instance.addListener(this._handleRawKeyEvent);
    _channel.setMethodCallHandler(_methodCallHandler);
    _inited = true;
  }

  _handleRawKeyEvent(RawKeyEvent value) {
    if (value is RawKeyUpEvent && _lastPressedHotKey != null) {
      HotKeyHandler? handler = _keyUpHandlerMap[_lastPressedHotKey!.identifier];
      if (handler != null) handler(_lastPressedHotKey!);
      _lastPressedHotKey = null;
      return;
    }

    if (value is RawKeyDownEvent) {
      HotKey hotKey = _hotKeyList.firstWhere(
        (e) {
          return value.isKeyPressed(e.keyCode.logicalKey) &&
              (e.modifiers ?? []).every((m) => m.logicalKeys
                  .map((lk) => value.isKeyPressed(lk))
                  .contains(true));
        },
        orElse: () => HotKey(KeyCode.none),
      );

      if (hotKey.isSetted) {
        HotKeyHandler? handler = _keyDownHandlerMap[hotKey.identifier];
        if (handler != null) handler(hotKey);
        _lastPressedHotKey = hotKey;
      }
    }
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    String identifier = call.arguments['identifier'];
    HotKey hotKey = _hotKeyList.firstWhere((e) => e.identifier == identifier);

    switch (call.method) {
      case 'onKeyDown':
        HotKeyHandler handler = _keyDownHandlerMap[identifier]!;
        handler(hotKey);
        break;
      case 'onKeyUp':
        HotKeyHandler handler = _keyUpHandlerMap[identifier]!;
        handler(hotKey);
        break;
      default:
        UnimplementedError();
    }
  }

  Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  List<HotKey> get registeredHotKeyList => _hotKeyList;

  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    if (!_inited) this._init();

    if (hotKey.scope == HotKeyScope.system) {
      await _channel.invokeMethod('register', hotKey.toJson());
    }
    if (keyDownHandler != null)
      _keyDownHandlerMap.update(
        hotKey.identifier,
        (_) => keyDownHandler,
        ifAbsent: () => keyDownHandler,
      );
    if (keyUpHandler != null)
      _keyUpHandlerMap.update(
        hotKey.identifier,
        (_) => keyUpHandler,
        ifAbsent: () => keyUpHandler,
      );

    _hotKeyList.add(hotKey);
  }

  Future<void> unregister(HotKey hotKey) async {
    if (!_inited) this._init();

    if (hotKey.scope == HotKeyScope.system) {
      await _channel.invokeMethod('unregister', hotKey.toJson());
    }
    if (_keyDownHandlerMap.containsKey(hotKey.identifier))
      _keyDownHandlerMap.remove(hotKey.identifier);
    if (_keyUpHandlerMap.containsKey(hotKey.identifier))
      _keyUpHandlerMap.remove(hotKey.identifier);

    _hotKeyList.removeWhere((e) => e.identifier == hotKey.identifier);
  }
}
