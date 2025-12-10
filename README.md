<p align="center">
  <img src="icon.png" alt="tsw_io" width="128" height="128">
</p>

<h1 align="center">tsw_io</h1>

<p align="center">
  <strong>Bridge your custom hardware to Train Sim World</strong>
</p>

<p align="center">
  <a href="#what-you-can-do">What You Can Do</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#roadmap">Roadmap</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Train_Sim_World-6-blue" alt="TSW6">
  <img src="https://img.shields.io/badge/License-CC%20BY--NC-green" alt="License">
</p>

---

## What You Can Do

tsw_io lets you integrate standard Arduino-based hardware controls to Train Sim World.
Build your own train cab with actual throttle levers, brake handles, and switches, without worrying about the programming.

- **Flash Arduino boards** directly from the app with pre-built firmware
- **Calibrate your controls** with a guided step-by-step process
- **Auto-detect trains** and load saved configurations automatically
- **Map any control** to simulator inputs using the built-in API explorer

---

## Getting Started

### Requirements

- Train Sim World 6 with External Interface API enabled. See [How to Enable the TSW API](#how-to-enable-the-tsw-api).
- An Arduino-compatible micro-controller. See [Supported Hardware](#supported-hardware).

### Installation

Download the latest release for Windows from the [Releases page](https://github.com/albertorestifo/tsw_io/releases).

### Setup and usage

See the video tutorial (WIP).

---

## Roadmap

This is an overview of the planned features, which I'll work on as I find the time:

**Output Support**

- LED indicators driven by simulator state
- 7-segment displays

**More Input Types**

- Digital inputs for buttons and switches
- Matrix support for button panels

**Platform & Features**

- Import/Export train configuration
- Shared repository of train configurations

---

## Development

```bash
# Clone and setup
git clone https://github.com/albertorestifo/tsw_io.git
cd tsw_io
mix deps.get
mix ecto.setup

# Run the server
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000)

See the [docs](docs/) folder for architecture and development guides.

---

## How to Enable the TSW API

Train Sim World 6 includes an External Interface API that allows third-party applications to communicate with the simulator. To enable it:

### 1. Add the Launch Flag

1. Right-click Train Sim World 6 in Steam
2. Select **Properties**
3. In the **General** tab, find **Launch Options**
4. Add `-HTTPAPI`

### 2. Launch the game

The game must be launched to generate the API key for the first time.
tws_io will automatically detect the API key when started.

---

## Supported Hardware

tsw_io supports the following Arduino-compatible boards:

| Board                         | MCU        | Analog Inputs | Digital I/O |
| ----------------------------- | ---------- | ------------- | ----------- |
| Arduino Uno                   | ATmega328P | 6             | 14          |
| Arduino Nano                  | ATmega328P | 8             | 14          |
| Arduino Nano (Old Bootloader) | ATmega328P | 8             | 14          |
| Arduino Leonardo              | ATmega32U4 | 12            | 20          |
| Arduino Micro                 | ATmega32U4 | 12            | 20          |
| Arduino Mega 2560             | ATmega2560 | 16            | 54          |
| SparkFun Pro Micro            | ATmega32U4 | 12            | 18          |

**Recommended boards:**

- **Arduino Nano** - Compact and affordable, great for simple setups with a few levers
- **Arduino Mega 2560** - Best for complex builds with many inputs
- **SparkFun Pro Micro** - Small form factor with native USB

All boards can be flashed directly from tsw_io without any additional software.

---

## License

[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) - Free to use and modify for non-commercial purposes.

For commercial licensing, contact [alberto@restifo.dev](mailto:alberto@restifo.dev).

---

## Acknowledgment

This project was inspired by [MobiFlight](https://www.mobiflight.com/en/index.html).
