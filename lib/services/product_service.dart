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


}