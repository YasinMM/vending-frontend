import 'package:dio/dio.dart';
import 'package:flutter_production_test/main.dart';

class ProductService {
  // JSON content type, set per request rather than globally so that GET calls
  // stay CORS "simple" and do not need a preflight round trip.
  static const _json = 'application/json';

  static Future<Response> createMachineQRCode(Map<String, dynamic> data) {
    return DioClient.dio.post(
      '/machineqrcode',
      data: data,
      options: Options(contentType: _json),
    );
  }

  static Future<Response> getMachineQRCode(int serial) {
    return DioClient.dio.get('/machineqrcode/$serial');
  }

  static Future<Response> cancelMachineQRCode(int serial) {
    return DioClient.dio.post('/machineqrcode/$serial/cancel');
  }

  static Future<Response> getMachineProductList(String machineSerial) {
    return DioClient.dio.get('/getmachineproductslist/$machineSerial');
  }

  static Future<Response> getMachinePinnedDiscountList(String machineSerial) {
    return DioClient.dio.get('/getmachinepinneddiscountlist/$machineSerial');
  }

  static Future<Response> getUserMachineDiscountList(String machineSerial, int user) {
    return DioClient.dio.get('/getusermachinediscountlist/$machineSerial/user/$user');
  }

  static Future<Response> getFinalPriceFromList(Map<String, dynamic> data) {
    return DioClient.dio.post('/getfinalpricefromlist', data: data,
        options: Options(contentType: _json));
  }

  static Future<Response> createCardPurchaseTransaction(Map<String, dynamic> data) {
    return DioClient.dio.post('/createcardpurchasetransaction', data: data,
        options: Options(contentType: _json));
  }

  static Future<Response> createUserCardPurchaseTransaction(Map<String, dynamic> data) {
    return DioClient.dio.post('/createusercardpurchasetransaction', data: data,
        options: Options(contentType: _json));
  }

  static Future<Response> createUserWalletPurchase(Map<String, dynamic> data) {
    return DioClient.dio.post('/createuserwalletpurchase', data: data,
        options: Options(contentType: _json));
  }

  static Future<Response> getWalletByUser(int user) {
    return DioClient.dio.get('/getwalletbyuser/$user');
  }

  static Future<Response> depositToWallet(Map<String, dynamic> data) {
    return DioClient.dio.post('/deposittowallet', data: data,
        options: Options(contentType: _json));
  }

  static Future<Response> getErrorDictionaryList() {
    return DioClient.dio.get('/geterrordictionarylist');
  }

  static Future<Response> getMachineList() {
    return DioClient.dio.get('/getmachinelist');
  }

  static Future<Response> getSensorList({String? machineSerial}) {
    final query = machineSerial != null ? '?machine=$machineSerial' : '';
    return DioClient.dio.get('/getsensorlist$query');
  }

  /// Current consumable amounts of a machine (recalculated server-side from
  /// the consumable change records) plus the amount each product consumes.
  static Future<Response> getMachineConsumableList(String machineSerial) {
    return DioClient.dio.get(
      '/getmachineconsumablelist/$machineSerial',
    );
  }

  /// Latest batch of machine receipts for [machineSerial] that were created at
  /// or after [sinceIso]. A batch is the set of receipts sharing one serial,
  /// i.e. one finalized order.
  static Future<Response> getLatestReceiptBatch(
    String machineSerial, {
    required String sinceIso,
  }) {
    final query = Uri.encodeComponent(sinceIso);
    return DioClient.dio.get(
      '/getlatestreceiptbatch/$machineSerial?since=$query',
    );
  }

  static Future<Response> createErrorLog(Map<String, dynamic> data) {
    return DioClient.dio.post('/createerrorlog', data: data,
        options: Options(contentType: _json));
  }

  static Future<Response> createSensorData(Map<String, dynamic> data) {
    return DioClient.dio.post('/createsensordata', data: data,
        options: Options(contentType: _json));
  }

  static Future<Response> getCriticalErrorLogs(String machineSerial, {String? sinceIso}) {
    final query = sinceIso != null ? '?since=${Uri.encodeComponent(sinceIso)}' : '';
    return DioClient.dio.get('/getcriticalerrorlogs/$machineSerial$query');
  }
}