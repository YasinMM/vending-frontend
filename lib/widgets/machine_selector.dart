import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/services/machine_preference_service.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A compact machine picker for the product page's top-right corner.
///
/// Lists every machine exposed by the backend, marks the active one, and
/// persists the selection so it is restored on the next browser load.
/// Changing the selection calls [onChanged] so the host page can reload the
/// whole order flow for the newly selected machine.
class MachineSelector extends ConsumerStatefulWidget {
  final ValueChanged<String> onChanged;

  const MachineSelector({super.key, required this.onChanged});

  @override
  ConsumerState<MachineSelector> createState() => _MachineSelectorState();
}

class _MachineSelectorState extends ConsumerState<MachineSelector> {
  List<String> _serials = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
    try {
      final response = await ProductService.getMachineList();
      if (!mounted) {
        return;
      }
      final data = response.data;
      final serials = <String>[];
      if (data is List) {
        for (final machine in data) {
          if (machine is Map && machine["serial"] != null) {
            serials.add(machine["serial"].toString());
          }
        }
      }
      setState(() {
        _serials = serials;
        _isLoading = false;
      });
    } on DioException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _select(String serial) async {
    if (serial == ref.read(activeMachineProvider)) {
      return;
    }
    ref.read(activeMachineProvider.notifier).setMachine(serial);
    // Persist so the same machine is preselected next time.
    await MachinePreferenceService.save(serial);
    if (!mounted) {
      return;
    }
    widget.onChanged(serial);
  }

  @override
  Widget build(BuildContext context) {
    final activeMachine = ref.watch(activeMachineProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.memory, size: 18, color: colorScheme.primary),
          const SizedBox(width: 6),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _serials.contains(activeMachine)
                    ? activeMachine
                    : null,
                hint: Text(activeMachine),
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                icon: const Icon(Icons.arrow_drop_down),
                onChanged: (serial) {
                  if (serial != null) {
                    _select(serial);
                  }
                },
                items: _serials
                    .map(
                      (serial) => DropdownMenuItem<String>(
                        value: serial,
                        child: Text(serial),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
