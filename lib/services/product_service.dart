import 'package:dio/dio.dart';
import 'package:flutter_production_test/main.dart';

class ProductService {
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
    return DioClient.dio.post('/getfinalpricefromlist', data: data);
  }

  static Future<Response> createCardPurchaseTransaction(Map<String, dynamic> data) {
    return DioClient.dio.post('/createcardpurchasetransaction', data: data);
  }

  static Future<Response> createUserCardPurchaseTransaction(Map<String, dynamic> data) {
    return DioClient.dio.post('/createusercardpurchasetransaction', data: data);
  }

  static Future<Response> createUserWalletPurchase(Map<String, dynamic> data) {
    return DioClient.dio.post('/createuserwalletpurchase', data: data);
  }

  static Future<Response> getWalletByUser(int user) {
    return DioClient.dio.get('/getwalletbyuser/$user');
  }

  static Future<Response> depositToWallet(Map<String, dynamic> data) {
    return DioClient.dio.post('/deposittowallet', data: data);
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

  static Future<Response> createErrorLog(Map<String, dynamic> data) {
    return DioClient.dio.post('/createerrorlog', data: data);
  }

  static Future<Response> getCriticalErrorLogs(String machineSerial, {String? sinceIso}) {
    final query = sinceIso != null ? '?since=${Uri.encodeComponent(sinceIso)}' : '';
    return DioClient.dio.get('/getcriticalerrorlogs/$machineSerial$query');
  }
}