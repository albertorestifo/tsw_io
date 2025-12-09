# TWS IO

**Bridge your custom hardware to Train Sim World**

TWS IO connects physical control panels, throttle levers, and custom hardware to Train Sim World's External Interface API. Build immersive train cab experiences with real hardware controls.

![Elixir](https://img.shields.io/badge/Elixir-1.15+-purple)
![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange)
![License](https://img.shields.io/badge/License-CC%20BY--NC-blue)

---

## Features

### Hardware Integration

- **Plug & Play Device Discovery** - Automatically detects USB-connected hardware devices
- **Multi-Device Support** - Connect multiple controllers simultaneously
- **Analog Input Calibration** - Guided wizard calibrates potentiometers and lever inputs
- **Notch Detection** - Automatically identifies detent positions during calibration
- **Real-Time Streaming** - Low-latency input value transmission

### Train Configuration

- **Auto-Detection** - Automatically identifies the train you're driving in the simulator
- **Lever Endpoint Discovery** - Reads available controls directly from the simulator API
- **Notch Mapping Wizard** - Guided setup maps physical input ranges to simulator notches
- **Multiple Train Profiles** - Configure different hardware mappings per train type

### Simulator Integration

- **Train Sim World 6 API** - Native integration with TSW's External Interface
- **Automatic API Key Detection** - Reads configuration from Windows install (manual entry also supported)
- **Connection Health Monitoring** - Automatic reconnection on connection loss
- **Live Train Detection** - Switches configurations when you change trains

### User Experience

- **Modern Web Interface** - Responsive Phoenix LiveView UI
- **Real-Time Updates** - See input values change as you move controls
- **Configuration Persistence** - SQLite database stores all settings
- **API Explorer** - Debug tool for testing simulator endpoints

---

## Quick Start

### Prerequisites

- Train Sim World (with External Interface API enabled)
- Elixir 1.15+ and Erlang/OTP 26+
- Hardware device with [TWS Board firmware](https://github.com/albertorestifo/tws_board)

### Installation

```bash
# Clone the repository
git clone https://github.com/albertorestifo/tws_io.git
cd tws_io

# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Start the server
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) to access the web interface.

### Basic Setup

1. **Connect to Simulator** - Configure API URL and key in Simulator settings
2. **Add Hardware** - Create a device configuration and define your input pins
3. **Calibrate Inputs** - Run the calibration wizard for each analog input
4. **Configure Train** - Create a train profile and auto-detect lever endpoints
5. **Bind Controls** - Link calibrated inputs to train levers
6. **Map Notches** - Use the wizard to set input ranges for each notch position

See the [Getting Started Guide](docs/getting-started.md) for detailed instructions.

---

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Quick setup guide |
| [Hardware Setup](docs/hardware-setup.md) | Device configuration and calibration |
| [Train Configuration](docs/train-configuration.md) | Train profiles and input binding |
| [Architecture](docs/architecture.md) | System design and data flow |
| [Development](docs/development.md) | Contributing and development setup |

---

## How It Works

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Hardware   │     │   TWS IO     │     │  Train Sim   │
│   Device     │────►│   Server     │────►│    World     │
│              │ USB │              │ API │              │
└──────────────┘     └──────────────┘     └──────────────┘
```

1. **Hardware sends input values** via USB serial protocol
2. **TWS IO normalizes values** using calibration data (0-1023 → 0.0-1.0)
3. **Notch mapping converts** to simulator values based on configured ranges
4. **API calls update** the train controls in real-time

---

## Roadmap

### Planned Features

#### Firmware Management
- [ ] **Firmware Upload** - Flash firmware directly from the web interface
- [ ] **OTA Updates** - Over-the-air firmware updates for connected devices
- [ ] **Firmware Version Display** - Show current firmware version per device

#### Output Support
- [ ] **LED Control** - Drive indicator LEDs from simulator state
- [ ] **Display Output** - Send speed, pressure, and other values to hardware displays
- [ ] **Haptic Feedback** - Motor control for force feedback effects

#### Extended Input Types
- [ ] **Digital Inputs** - Button and switch support
- [ ] **Rotary Encoders** - Infinite rotation inputs for knobs
- [ ] **Matrix Keyboards** - Multi-button panel support

#### Platform & Integration
- [ ] **Train Sim World 5 Support** - Backwards compatibility
- [ ] **Desktop Application** - Standalone executable (no Elixir install required)
- [ ] **Configuration Import/Export** - Share train profiles with the community

#### Advanced Features
- [ ] **Input Curves** - Custom response curves for analog inputs
- [ ] **Macros** - Trigger sequences of actions from single inputs
- [ ] **Multiplayer Sync** - Share hardware state in multiplayer sessions

---

## Tech Stack

- **[Elixir](https://elixir-lang.org/)** - Functional language built on the Erlang VM
- **[Phoenix](https://www.phoenixframework.org/)** - Web framework with real-time capabilities
- **[Phoenix LiveView](https://hexdocs.pm/phoenix_live_view)** - Server-rendered interactive UI
- **[Ecto](https://hexdocs.pm/ecto)** - Database wrapper and query language
- **[SQLite](https://www.sqlite.org/)** - Embedded database for configuration storage
- **[circuits_uart](https://hex.pm/packages/circuits_uart)** - Serial communication library

---

## Contributing

Contributions are welcome! Please read the [Development Guide](docs/development.md) before submitting pull requests.

```bash
# Run tests
mix test

# Format code
mix format

# Run all checks
mix precommit
```

---

## License

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) (Creative Commons Attribution-NonCommercial).

You are free to use, modify, and share this software for non-commercial purposes with attribution.

**For commercial use**, please contact [alberto@restifo.dev](mailto:alberto@restifo.dev).

---

## Acknowledgments

- Train Sim World team for the External Interface API
- The Elixir and Phoenix communities
- All contributors and testers

---

*Built with Elixir and Phoenix LiveView*
