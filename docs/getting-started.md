# Getting Started

Get TWS IO up and running in minutes.

## Prerequisites

- **Train Sim World** (with External Interface API enabled)
- **Elixir 1.15+** and **Erlang/OTP 26+**
- **Hardware device** - Arduino or compatible microcontroller with [TWS Board firmware](https://github.com/albertorestifo/tws_board)

## Firmware Installation

Before using TWS IO, you need to flash the TWS Board firmware to your microcontroller.

1. Visit the [TWS Board repository](https://github.com/albertorestifo/tws_board)
2. Follow the installation instructions for your hardware
3. Flash the firmware to your device
4. Connect the device via USB

The firmware handles:
- Reading analog inputs (potentiometers, sliders)
- Communicating with TWS IO over USB serial
- Storing device configuration

## TWS IO Installation

### Clone the Repository

```bash
git clone https://github.com/albertorestifo/tws_io.git
cd tws_io
```

### Install Dependencies

```bash
mix deps.get
```

### Setup Database

```bash
mix ecto.setup
```

### Start the Server

```bash
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) in your browser.

## Quick Setup Guide

### Step 1: Configure Simulator Connection

1. Start Train Sim World
2. In TWS IO, click **Simulator** in the sidebar
3. The default URL is `http://localhost:31270`
4. Click **Auto-Detect API Key** (Windows) or enter manually
5. Click **Save** and verify connection status shows "Connected"

### Step 2: Create Hardware Configuration

1. Click **Configurations** in the sidebar
2. Click **New Configuration**
3. Name it (e.g., "My Throttle Controller")
4. Add inputs for each physical control:
   - Click **Add Input**
   - Set pin number, type (analog), and sensitivity
5. Save your configuration

### Step 3: Connect and Calibrate Hardware

1. Plug in your hardware device via USB
2. Click **Scan Devices** or wait for auto-discovery
3. Click **Apply to Device** on your configuration
4. For each input, click **Calibrate**:
   - Hold at minimum → record samples
   - Sweep full range
   - Hold at maximum → record samples

### Step 4: Create Train Configuration

1. Load a train in Train Sim World
2. In TWS IO, click **Trains**
3. The detected train appears - click **Create Configuration**
4. Add elements:
   - Click **Add Element**
   - Name it "Throttle" (or appropriate control)
   - Type: Lever
5. Click **Auto-Detect** to configure endpoints automatically

### Step 5: Bind Input to Lever

1. On your lever element, click **Bind Input**
2. Select your calibrated hardware input
3. Click **Map Notches** to configure notch boundaries
4. Follow the wizard to set input ranges for each notch

### Step 6: Test It Out!

1. Move your physical control
2. Watch the lever respond in Train Sim World
3. Adjust calibration or notch mapping if needed

## Next Steps

- Read the [Hardware Setup Guide](hardware-setup.md) for detailed device configuration
- See [Train Configuration](train-configuration.md) for advanced lever setup
- Check [Architecture](architecture.md) to understand the system design

## Troubleshooting

### Simulator Won't Connect

- Ensure Train Sim World is running
- Verify External Interface is enabled in TSW settings
- Check firewall isn't blocking port 31270
- On Windows, the API key is in `Documents/My Games/TrainSimWorld/CommAPIKey.txt`

### Device Not Found

- Check USB connection
- Verify device has compatible firmware
- Try different USB port
- Run manual device scan

### No Response from Train Controls

- Verify train configuration is active
- Check input binding is enabled
- Confirm calibration is complete
- Test API endpoints with the Explorer tool
