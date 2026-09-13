import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActiveMachineNotifier extends Notifier<String> {
  @override
  String build() {
    return "test001";
  }

  void setMachine(String machine) {
    state = machine;
  }
}

final activeMachineProvider = NotifierProvider<ActiveMachineNotifier, String>(() {
  return ActiveMachineNotifier();
});