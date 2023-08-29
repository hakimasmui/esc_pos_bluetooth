/*
 * esc_pos_bluetooth
 * Created by Andrey Ushakov
 * Updated by Hakim Asmui
 * Special thanks to Riski Febi
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_bluetooth_basic/flutter_bluetooth_basic.dart';
import './enums.dart';

/// Bluetooth printer
class PrinterBluetooth {
  PrinterBluetooth(this._device);
  final BluetoothDevice _device;

  String? get name => _device.name;
  String? get address => _device.address;
  int? get type => _device.type;
}

/// Printer Bluetooth Manager
class PrinterBluetoothManager {
  final BluetoothManager _bluetoothManager = BluetoothManager.instance;
  List<BluetoothManager> _listBManager = [];
  bool _isPrinting = false;
  bool _isConnected = false;
  StreamSubscription? _scanResultsSubscription;
  StreamSubscription? _isScanningSubscription;
  PrinterBluetooth? _selectedPrinter;
  List<PrinterBluetooth> _ListPrinter = [];
  List<int> list_jumlah = [];
  int? jumlah;

  final BehaviorSubject<bool> _isScanning = BehaviorSubject.seeded(false);
  Stream<bool> get isScanningStream => _isScanning.stream;

  final BehaviorSubject<List<PrinterBluetooth>> _scanResults =
  BehaviorSubject.seeded([]);
  Stream<List<PrinterBluetooth>> get scanResults => _scanResults.stream;

  Future _runDelayed(int seconds) {
    return Future<dynamic>.delayed(Duration(seconds: seconds));
  }

  void startScan(Duration timeout) async {
    _scanResults.add(<PrinterBluetooth>[]);

    _bluetoothManager.startScan(timeout: timeout);

    _scanResultsSubscription = _bluetoothManager.scanResults.listen((devices) {
      _scanResults.add(devices.map((d) => PrinterBluetooth(d)).toList());
    });

    _isScanningSubscription =
        _bluetoothManager.isScanning.listen((isScanningCurrent) async {
          // If isScanning value changed (scan just stopped)
          if (_isScanning.value! && !isScanningCurrent) {
            _scanResultsSubscription!.cancel();
            _isScanningSubscription!.cancel();
          }
          _isScanning.add(isScanningCurrent);
        });
  }

  void stopScan() async {
    await _bluetoothManager.stopScan();
  }

  void selectPrinter(PrinterBluetooth printer,{int jumlah_copy = 1}) {
    _selectedPrinter = printer;
    this.jumlah = jumlah_copy;
  }

  void selectListPrinter(List<PrinterBluetooth>printer,{List<int> jumlah_copy = const []}) {
    _ListPrinter = printer;
    for(int i=0;i<_ListPrinter.length;i++){
      BluetoothManager tmp = BluetoothManager.instance;
      _listBManager.add(tmp);
    }
    this.list_jumlah = jumlah_copy;
  }

  Future<PosPrintResult> writeBytes(
      List<int> bytes, {
        int chunkSizeBytes = 20,
        int queueSleepTimeMs = 20,
      }) async {
    final Completer<PosPrintResult> completer = Completer();

    const int timeout = 5;
    if (_selectedPrinter == null) {
      return Future<PosPrintResult>.value(PosPrintResult.printerNotSelected);
    } else if (_isScanning.value!) {
      return Future<PosPrintResult>.value(PosPrintResult.scanInProgress);
    }
    /*else if (_isPrinting) {
      return Future<PosPrintResult>.value(PosPrintResult.printInProgress);
    }*/

    _isPrinting = true;

    // We have to rescan before connecting, otherwise we can connect only once
    await _bluetoothManager.startScan(timeout: Duration(seconds: 1));
    await _bluetoothManager.stopScan();

    // Connect
    await _bluetoothManager.connect(_selectedPrinter!._device);

    // Subscribe to the events
    _bluetoothManager.state.listen((state) async {
      switch (state) {
        case BluetoothManager.CONNECTED:
        // To avoid double call
          if (!_isConnected) {
            for(int i=0;i<jumlah!;i++) {
              final len = bytes.length;
              List<List<int>> chunks = [];
              for (var i = 0; i < len; i += chunkSizeBytes) {
                var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
                chunks.add(bytes.sublist(i, end));
              }

              for (var i = 0; i < chunks.length; i += 1) {
                await _bluetoothManager.writeData(chunks[i]);
                sleep(Duration(milliseconds: queueSleepTimeMs));
              }

            }
            completer.complete(PosPrintResult.success);
          }
          // TODO sending disconnect signal should be event-based
          _runDelayed(3).then((dynamic v) async {
            await _bluetoothManager.disconnect();
            _isPrinting = false;
          });
          _isConnected = true;
          break;
        case BluetoothManager.DISCONNECTED:
          _isConnected = false;
          break;
        default:
          break;
      }
    });

    // Printing timeout
    _runDelayed(timeout).then((dynamic v) async {
      if (_isPrinting) {
        _isPrinting = false;
        completer.complete(PosPrintResult.timeout);
      }
    });

    return completer.future;
  }

  Future<PosPrintResult> writeBytesList(
      List<int> bytes, {
        int chunkSizeBytes = 20,
        int queueSleepTimeMs = 20,
      }) async {
    final Completer<PosPrintResult> completer = Completer();

    const int timeout = 5;
    if (_ListPrinter == null) {
      return Future<PosPrintResult>.value(PosPrintResult.printerNotSelected);
    }else if(_ListPrinter.isEmpty){
      return Future<PosPrintResult>.value(PosPrintResult.printerNotSelected);
    }else if (_isScanning.value!) {
      return Future<PosPrintResult>.value(PosPrintResult.scanInProgress);
    } else if (_isPrinting) {
      return Future<PosPrintResult>.value(PosPrintResult.printInProgress);
    }

    _isPrinting = true;

    // We have to rescan before connecting, otherwise we can connect only once
    bool time_out = false;
    for(int lp =0;lp<_ListPrinter.length;lp++){
      await _listBManager[lp].startScan(timeout: Duration(seconds: 1));
      await _listBManager[lp].stopScan();
      _isConnected = false;
      // Connect
      try{
        await _listBManager[lp].connect(_ListPrinter[lp]._device);
        // Subscribe to the events
        _listBManager[lp].state.listen((state) async {
          switch (state) {
            case BluetoothManager.CONNECTED:
            // To avoid double call
              if (!_isConnected) {
                for(int z=0;z< list_jumlah[lp];z++) {
                  final len = bytes.length;
                  List<List<int>> chunks = [];
                  for (var i = 0; i < len; i += chunkSizeBytes) {
                    var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
                    chunks.add(bytes.sublist(i, end));
                  }

                  for (var i = 0; i < chunks.length; i += 1) {
                    await _listBManager[lp].writeData(chunks[i]);
                    sleep(Duration(milliseconds: queueSleepTimeMs));
                  }
                }
              }
              _isConnected = true;
              break;
            case BluetoothManager.DISCONNECTED:
              _isConnected = false;
              break;
            default:
              break;
          }
        });
      }catch(e){
        time_out = true;
      }
      // if(BluetoothManager.CONNECTED == 1){
      //   // Subscribe to the events
      //   for(int i=0;i<list_jumlah[lp];i++) {
      //     final len = bytes.length;
      //     List<List<int>> chunks = [];
      //     for (var i = 0; i < len; i += chunkSizeBytes) {
      //       var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
      //       chunks.add(bytes.sublist(i, end));
      //     }
      //
      //     for (var i = 0; i < chunks.length; i += 1) {
      //       await _listBManager[lp].writeData(chunks[i]);
      //       sleep(Duration(milliseconds: queueSleepTimeMs));
      //     }
      //   }
      // }


    }

    for(int lp =0;lp<_ListPrinter.length;lp++){
      try{
        _runDelayed(3).then((dynamic v) async {
          await _listBManager[lp].disconnect();
          _isPrinting = false;
        });
      }catch(e){
        time_out = true;
      }
    }

    if(time_out){
      completer.complete(PosPrintResult.timeout);
    }else {
      completer.complete(PosPrintResult.success);
    }

    // Printing timeout
    _runDelayed(timeout).then((dynamic v) async {
      if (_isPrinting) {
        _isPrinting = false;
        completer.complete(PosPrintResult.timeout);
      }
    });

    return completer.future;
  }

  Future<PosPrintResult> printTicket(
      List<int> bytes, {
        int chunkSizeBytes = 20,
        int queueSleepTimeMs = 20,
      }) async {
    if (bytes.isEmpty) {
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    }
    return _ListPrinter != null?writeBytesList(
      bytes,
      chunkSizeBytes: chunkSizeBytes,
      queueSleepTimeMs: queueSleepTimeMs,
    ):writeBytes(
      bytes,
      chunkSizeBytes: chunkSizeBytes,
      queueSleepTimeMs: queueSleepTimeMs,
    );
  }
}