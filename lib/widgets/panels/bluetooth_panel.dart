import 'package:material_ui/material_ui.dart';

import '../../rust_gen/bluetooth/prompt.dart';
import '../../rust_gen/state.dart';
import '../alice_icon.dart';
import '../bluetooth_icons.dart';
import 'panel_shell.dart';

class BluetoothPanel extends StatefulWidget {
  const BluetoothPanel({
    super.key,
    required this.bluetooth,
    required this.onScan,
    required this.onConnect,
    required this.onDisconnect,
    required this.onPromptResponse,
  });

  final BluetoothSnapshot bluetooth;
  final Future<void> Function() onScan;
  final Future<void> Function(String address) onConnect;
  final Future<void> Function(String address) onDisconnect;
  final Future<void> Function(String token, PromptResponse response)
  onPromptResponse;

  @override
  State<BluetoothPanel> createState() => _BluetoothPanelState();
}

class _BluetoothPanelState extends State<BluetoothPanel> {
  bool _hasStartedScan = false;

  Future<void> _startScan() async {
    setState(() => _hasStartedScan = true);
    await widget.onScan();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.bluetooth.devices
        .where((d) => d.connected)
        .toList();
    final known = widget.bluetooth.devices
        .where((d) => d.paired && !d.connected)
        .toList();
    final knownAddresses = {
      ...connected.map((d) => d.address),
      ...known.map((d) => d.address),
    };
    final discovered = widget.bluetooth.scanResults.where(
      (d) => !knownAddresses.contains(d.address),
    );
    // Preserve the transport's most-recently-added order within each group.
    final nearby = [
      ...discovered.where(_hasDeviceName),
      ...discovered.where((device) => !_hasDeviceName(device)),
    ];
    final scanButton = FilledButton.icon(
      onPressed: widget.bluetooth.scanState == BluetoothScanState.scanning
          ? null
          : _startScan,
      icon: widget.bluetooth.scanState == BluetoothScanState.scanning
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const AliceIcon(BluetoothIcons.bluetooth, size: 16),
      label: Text(
        widget.bluetooth.scanState == BluetoothScanState.scanning
            ? 'Scanning'
            : 'Scan',
      ),
    );
    return Stack(
      children: [
        PanelShell(
          title: 'Bluetooth',
          crossAxisAlignment: CrossAxisAlignment.stretch,
          child: Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      _DeviceSection(
                        title: 'Known Devices',
                        devices: [...connected, ...known],
                        onConnect: widget.onConnect,
                        onDisconnect: widget.onDisconnect,
                      ),
                      if (_hasStartedScan)
                        _DeviceSection(
                          title: 'Nearby Devices',
                          devices: nearby,
                          onConnect: widget.onConnect,
                          onDisconnect: widget.onDisconnect,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(child: scanButton),
              ],
            ),
          ),
        ),
        if (widget.bluetooth.prompt case final prompt?)
          _BluetoothPromptDialog(
            prompt: prompt,
            onResponse: widget.onPromptResponse,
          ),
      ],
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.title,
    required this.devices,
    required this.onConnect,
    required this.onDisconnect,
  });
  final String title;
  final List<BluetoothDeviceSnapshot> devices;
  final Future<void> Function(String) onConnect;
  final Future<void> Function(String) onDisconnect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      _SectionTitle(title),
      if (devices.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('None')),
      for (final device in devices)
        _DeviceRow(
          device: device,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
        ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1,
    ),
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.onConnect,
    required this.onDisconnect,
  });
  final BluetoothDeviceSnapshot device;
  final Future<void> Function(String) onConnect;
  final Future<void> Function(String) onDisconnect;

  @override
  Widget build(BuildContext context) {
    final busy = device.operation != BluetoothOperationState.idle;
    final label = _deviceLabel(device);
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return ListTile(
      key: ValueKey('bluetooth-device-${device.address}'),
      leading: AliceIcon(_iconFor(device.presentation.category)),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device.address,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (device.error case final error?)
            Text(
              error.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: () => device.connected
                  ? onDisconnect(device.address)
                  : onConnect(device.address),
              child: Text(device.connected ? 'Disconnect' : 'Connect'),
            ),
    );
  }
}

String _normalizedAddress(String address) => address.replaceAll('-', ':');

bool _isUsableDeviceName(String? value, BluetoothDeviceSnapshot device) {
  final name = value?.trim();
  return name != null &&
      name.isNotEmpty &&
      _normalizedAddress(name).toUpperCase() !=
          _normalizedAddress(device.address).toUpperCase();
}

bool _hasDeviceName(BluetoothDeviceSnapshot device) =>
    _isUsableDeviceName(device.alias, device) ||
    _isUsableDeviceName(device.name, device);

String _deviceLabel(BluetoothDeviceSnapshot device) =>
    _isUsableDeviceName(device.alias, device)
    ? device.alias!.trim()
    : _isUsableDeviceName(device.name, device)
    ? device.name!.trim()
    // BlueZ normally emits canonical colon-delimited addresses. Normalize
    // dashed values from other transports before showing an address title.
    : _normalizedAddress(device.address);

AliceIconDescriptor _iconFor(BluetoothDeviceCategory category) =>
    switch (category) {
      BluetoothDeviceCategory.audio => BluetoothIcons.audio,
      BluetoothDeviceCategory.computer => BluetoothIcons.computer,
      BluetoothDeviceCategory.input => BluetoothIcons.input,
      BluetoothDeviceCategory.phone => BluetoothIcons.phone,
      BluetoothDeviceCategory.peripheral ||
      BluetoothDeviceCategory.gaming => BluetoothIcons.peripheral,
      BluetoothDeviceCategory.wearable => BluetoothIcons.wearable,
      BluetoothDeviceCategory.display => BluetoothIcons.display,
      BluetoothDeviceCategory.clock => AliceIcons.clock,
      BluetoothDeviceCategory.tag => BluetoothIcons.tag,
      BluetoothDeviceCategory.key => BluetoothIcons.key,
      BluetoothDeviceCategory.media => BluetoothIcons.media,
      BluetoothDeviceCategory.scanner => BluetoothIcons.scanner,
      BluetoothDeviceCategory.temperature => BluetoothIcons.temperature,
      BluetoothDeviceCategory.heart => BluetoothIcons.heart,
      BluetoothDeviceCategory.health => BluetoothIcons.health,
      BluetoothDeviceCategory.fitness => BluetoothIcons.fitness,
      BluetoothDeviceCategory.cycling => BluetoothIcons.cycling,
      BluetoothDeviceCategory.controls => BluetoothIcons.controls,
      BluetoothDeviceCategory.network => AliceIcons.ethernet,
      BluetoothDeviceCategory.sensor ||
      BluetoothDeviceCategory.measurement => BluetoothIcons.sensor,
      BluetoothDeviceCategory.light => BluetoothIcons.light,
      BluetoothDeviceCategory.fan => BluetoothIcons.fan,
      BluetoothDeviceCategory.climate => BluetoothIcons.climate,
      BluetoothDeviceCategory.heating => BluetoothIcons.heating,
      BluetoothDeviceCategory.access => AliceIcons.lock,
      BluetoothDeviceCategory.motorized => BluetoothIcons.motorized,
      BluetoothDeviceCategory.power => BluetoothIcons.power,
      BluetoothDeviceCategory.windowCovering => BluetoothIcons.display,
      BluetoothDeviceCategory.vehicle => BluetoothIcons.vehicle,
      BluetoothDeviceCategory.appliance ||
      BluetoothDeviceCategory.cookware => BluetoothIcons.cookware,
      BluetoothDeviceCategory.aircraft => BluetoothIcons.aircraft,
      BluetoothDeviceCategory.tools => BluetoothIcons.tools,
      BluetoothDeviceCategory.generic => BluetoothIcons.bluetooth,
    };

class _BluetoothPromptDialog extends StatefulWidget {
  const _BluetoothPromptDialog({
    required this.prompt,
    required this.onResponse,
  });
  final BluetoothPrompt prompt;
  final Future<void> Function(String, PromptResponse) onResponse;
  @override
  State<_BluetoothPromptDialog> createState() => _BluetoothPromptDialogState();
}

class _BluetoothPromptDialogState extends State<_BluetoothPromptDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.prompt;
    final needsInput =
        prompt.kind == BluetoothPromptKind.requestPinCode ||
        prompt.kind == BluetoothPromptKind.requestPasskey;
    final confirmation =
        prompt.kind == BluetoothPromptKind.requestConfirmation ||
        prompt.kind == BluetoothPromptKind.authorizeDevice ||
        prompt.kind == BluetoothPromptKind.authorizeService;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: AlertDialog(
            title: const Text('Bluetooth request'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prompt.deviceLabel),
                if (prompt.service != null) Text(prompt.service!),
                if (prompt.passkey != null) Text('Passkey: ${prompt.passkey}'),
                if (needsInput)
                  TextField(
                    controller: _input,
                    keyboardType:
                        prompt.kind == BluetoothPromptKind.requestPasskey
                        ? TextInputType.number
                        : TextInputType.text,
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => widget.onResponse(
                  prompt.token,
                  const PromptResponse.cancel(),
                ),
                child: const Text('Cancel'),
              ),
              if (confirmation)
                TextButton(
                  onPressed: () => widget.onResponse(
                    prompt.token,
                    const PromptResponse.deny(),
                  ),
                  child: const Text('Deny'),
                ),
              if (needsInput || confirmation)
                FilledButton(
                  onPressed: () => widget.onResponse(
                    prompt.token,
                    needsInput
                        ? (prompt.kind == BluetoothPromptKind.requestPasskey
                              ? PromptResponse.passkey(
                                  int.tryParse(_input.text) ?? 0,
                                )
                              : PromptResponse.pinCode(_input.text))
                        : const PromptResponse.accept(),
                  ),
                  child: Text(needsInput ? 'Submit' : 'Allow'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
