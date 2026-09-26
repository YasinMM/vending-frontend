import 'package:flutter_production_test/services/machine_preference_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The machine used when nothing has been stored yet (or storage failed).
const String kDefaultMachineSerial = "test001";

class ActiveMachineNotifier extends Notifier<String> {
  @override
  String build() {
    // Restores the machine the user picked last time. The cache is hydrated
    // once before the first frame, so this is populated by the time any page
    // reads the provider.
    return MachinePreferenceService.cached ?? kDefaultMachineSerial;
  }

  void setMachine(String machine) {
    state = machine;
  }
}

final activeMachineProvider = NotifierProvider<ActiveMachineNotifier, String>(() {
  return ActiveMachineNotifier();
});