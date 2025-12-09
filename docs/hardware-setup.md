# Hardware Setup Guide

This guide covers connecting and configuring physical hardware devices with TWS IO.

## Firmware

Your hardware device needs the TWS Board firmware installed. See the [TWS Board repository](https://github.com/albertorestifo/tws_board) for installation instructions.

## Supported Hardware

TWS IO communicates with microcontroller-based devices via USB serial running the TWS Board firmware.

### Compatible Microcontrollers

- Arduino (Uno, Mega, Nano)
- ESP32 / ESP8266
- Teensy
- Any microcontroller with USB serial and ADC inputs

### Input Types

| Type | Description | Use Case |
|------|-------------|----------|
| Analog | 10-bit ADC (0-1023) | Potentiometers, throttle levers |
| Digital | On/Off state | Buttons, switches (coming soon) |

## Creating a Device Configuration

1. Navigate to **Configurations** in the sidebar
2. Click **New Configuration**
3. Enter a descriptive name (e.g., "Throttle Panel", "Reverser Controller")
4. Save the configuration

Each configuration receives a unique `config_id` that links it to physical hardware.

## Adding Input Pins

For each physical input on your device:

1. Open your configuration
2. Click **Add Input**
3. Configure:
   - **Pin Number** - The ADC pin on your microcontroller
   - **Input Type** - Analog (digital coming soon)
   - **Sensitivity** - Value change threshold (1-255, default 5)
4. Save the input

### Sensitivity Setting

The sensitivity value determines how much the input must change before sending an update. Lower values = more responsive but more network traffic.

| Value | Use Case |
|-------|----------|
| 1-3 | High precision requirements |
| 5 | Default, good balance |
| 10-20 | Noisy inputs, reduce chatter |

## Connecting Your Device

### Automatic Discovery

TWS IO automatically scans for devices every 60 seconds. Connected devices appear in the sidebar navigation.

### Manual Scan

Click the **Scan Devices** button to immediately discover connected devices.

### Device Status

| Status | Meaning |
|--------|---------|
| Connected | Device online and communicating |
| Disconnected | Device not responding |
| Unconfigured | No configuration applied |

## Applying Configuration to Device

Once your device is connected and configuration is ready:

1. Open the configuration
2. Click **Apply to Device**
3. Select the target device from the dropdown
4. The configuration is sent to the device

The device stores the `config_id` and begins streaming input values.

## Calibrating Inputs

Calibration maps raw ADC values to normalized 0.0-1.0 range.

### Starting Calibration

1. Find the input in your configuration
2. Click **Calibrate**
3. The calibration wizard opens

### Calibration Steps

**Step 1: Minimum Position**
- Move your input to its minimum position (e.g., throttle fully closed)
- Hold steady while samples are collected
- Click **Next** when complete

**Step 2: Full Sweep**
- Slowly move input through its entire range
- Move from minimum to maximum and back
- The system detects the full travel range
- Click **Next** when complete

**Step 3: Maximum Position**
- Move your input to its maximum position (e.g., throttle fully open)
- Hold steady while samples are collected
- Click **Finish** to save calibration

### Calibration Results

After calibration, you'll see:
- **Min Value** - Lowest detected ADC reading
- **Max Value** - Highest detected ADC reading
- **Detected Notches** - If your input has detents, they're automatically found

## Troubleshooting

### Device Not Appearing

1. Check USB cable connection
2. Verify device has correct firmware
3. Check device is not claimed by another application
4. Try a different USB port

### Erratic Input Values

1. Increase sensitivity setting to filter noise
2. Check for loose connections
3. Add hardware filtering (capacitor) if needed
4. Re-run calibration

### Configuration Won't Apply

1. Ensure device is connected
2. Check device isn't locked by another configuration
3. Verify firmware supports the protocol version

## Hardware Protocol Reference

For firmware developers implementing the TWS IO protocol:

### Message Format

```
[START_BYTE] [TYPE] [PAYLOAD...] [END_BYTE]
```

### Message Types

| Type | Direction | Payload |
|------|-----------|---------|
| 0x01 | Request | None |
| 0x01 | Response | Signature bytes |
| 0x02 | To Device | config_id (4 bytes) + pin + type + sensitivity |
| 0x03 | From Device | None (acknowledgment) |
| 0x04 | Both | None (heartbeat) |
| 0x05 | From Device | config_id (4 bytes) + pin + value (2 bytes signed) |

### Input Value Message

```
Byte 0: Message type (0x05)
Bytes 1-4: config_id (int32, little-endian)
Byte 5: Pin number
Bytes 6-7: Value (int16, little-endian, 0-1023 for analog)
```
