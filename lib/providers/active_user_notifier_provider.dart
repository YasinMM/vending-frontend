import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActiveUserNotifier extends Notifier<int> {
  @override
  int build() {
    return -1;
  }

  void setUser(int user) {
    state = user;
  }
}

final activeUserProvider = NotifierProvider<ActiveUserNotifier, int>(() {
  return ActiveUserNotifier();
});