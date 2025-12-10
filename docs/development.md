# Development Guide

Guide for developers contributing to TWS IO.

## Development Setup

### Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- Node.js (for asset compilation)
- SQLite3

### Optional: Firmware Upload Support

To use the firmware upload feature during development, you need to install avrdude:

**macOS:**
```bash
brew install avrdude
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install avrdude
```

**Linux (Fedora):**
```bash
sudo dnf install avrdude
```

**Windows:**
Download from [avrdudes/avrdude releases](https://github.com/avrdudes/avrdude/releases) and add to your PATH.

The desktop app bundles avrdude automatically, so end users don't need to install it separately.

### Using mise (Recommended)

The project includes `.mise.toml` for version management:

```bash
mise install
mise exec -- mix deps.get
mise exec -- mix ecto.setup
mise exec -- mix phx.server
```

### Standard Setup

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

## Project Structure

```
lib/
├── tsw_io/                    # Core business logic
│   ├── application.ex         # OTP application
│   ├── repo.ex                # Ecto repository
│   ├── hardware.ex            # Hardware context
│   ├── train.ex               # Train context
│   ├── simulator.ex           # Simulator context
│   ├── hardware/              # Hardware domain modules
│   ├── train/                 # Train domain modules
│   ├── simulator/             # Simulator domain modules
│   └── serial/                # Serial communication
│
├── tsw_io_web/                # Web layer
│   ├── router.ex              # Routes
│   ├── endpoint.ex            # Phoenix endpoint
│   ├── live/                  # LiveView modules
│   └── controllers/           # Traditional controllers
│
priv/
├── repo/migrations/           # Database migrations
└── static/                    # Static assets

test/                          # Test files
```

## Coding Guidelines

### Type Safety

Always pattern match on structs in function arguments:

```elixir
# Good
def process(%MyStruct{} = struct) do
  # ...
end

# Bad
def process(struct) do
  # ...
end
```

### Float Precision

Round float values to 2 decimal places for hardware/calibration values:

```elixir
# Good
value = Float.round(raw_value, 2)

# Bad - may have precision artifacts
value = raw_value  # -0.20000000298023224
```

### Protocol Messages

Handle atom-to-integer conversion in encode/decode functions:

```elixir
# Good - atom in struct, conversion in encode/decode
defmodule MyMessage do
  defstruct [:type]  # type is :analog or :digital

  def encode(%__MODULE__{type: :analog}), do: {:ok, <<0x00>>}
  def encode(%__MODULE__{type: :digital}), do: {:ok, <<0x01>>}
end
```

## Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/tsw_io/train_test.exs

# Run with coverage
mix test --cover
```

### Test Environment

Tests run with GenServers disabled (no real hardware/simulator connections). Mock modules using Mimic:

```elixir
use Mimic

setup :verify_on_exit!

test "my test" do
  expect(TswIo.Simulator.Client, :get, fn _path -> {:ok, %{}} end)
  # ...
end
```

## Database

### Creating Migrations

```bash
mix ecto.gen.migration add_my_table
```

### Running Migrations

```bash
mix ecto.migrate
```

### Reset Database

```bash
mix ecto.reset
```

## Code Quality

### Formatting

```bash
mix format
```

### Dialyzer (Static Analysis)

```bash
mix dialyzer
```

### Pre-commit Hook

Run all checks:

```bash
mix precommit
```

## Architecture Decisions

### GenServer Services

Long-running processes are implemented as GenServers:

- `Serial.Connection` - Device connections
- `Simulator.Connection` - API health monitoring
- `Train.Detection` - Active train polling
- `Train.LeverController` - Input-to-simulator mapping
- `Hardware.ConfigurationManager` - Input value broadcasting

### PubSub Events

Components communicate via Phoenix.PubSub:

```elixir
# Subscribe
Phoenix.PubSub.subscribe(TswIo.PubSub, "topic")

# Broadcast
Phoenix.PubSub.broadcast(TswIo.PubSub, "topic", {:event, data})
```

### Contexts

Business logic is organized into contexts:

- `TswIo.Hardware` - Device and input management
- `TswIo.Train` - Train configuration and bindings
- `TswIo.Simulator` - TSW API communication

## Adding New Features

### New Input Type

1. Add type to `Input` schema
2. Update `Configure` message encoding
3. Add UI support in configuration editor
4. Update calibration if needed

### New Element Type

1. Add type to `Element` schema
2. Create config schema (like `LeverConfig`)
3. Add UI components for configuration
4. Implement value mapping logic

### New Protocol Message

1. Create module in `lib/tsw_io/serial/protocol/`
2. Implement `TswIo.Serial.Protocol.Message` behaviour
3. Register in message type registry
4. Handle in `Serial.Connection`

## Debugging

### LiveView Inspector

Phoenix LiveDashboard available at `/dev/dashboard`

### API Explorer

Built-in API explorer in train configuration UI for testing simulator endpoints.

### Serial Debug

Enable verbose serial logging:

```elixir
# In config/dev.exs
config :tsw_io, :serial_debug, true
```

## Building the Desktop App

The desktop application is built using Tauri with a Burrito-packaged Elixir backend. The app bundles avrdude for firmware upload functionality.

### Building for macOS (Local Development)

Pre-built releases are only provided for Windows. To build for macOS (Apple Silicon) locally:

#### Prerequisites

- [mise](https://mise.jdx.dev/) - for managing tool versions
- xz - install with `brew install xz`
- curl - for downloading avrdude (usually pre-installed)

#### Build

```bash
# Install dependencies via mise
mise install

# Run the build script
./scripts/build-macos.sh
```

The build script will:
1. Build the Elixir backend with Burrito
2. Download avrdude for macOS ARM64
3. Build the Tauri application with all binaries bundled

The built `.dmg` and `.app` will be in `tauri/src-tauri/target/aarch64-apple-darwin/release/bundle/`.

### Bundled Components

The desktop app bundles:
- **tsw_io_backend** - The Elixir application (Burrito release)
- **avrdude** - AVR programmer for firmware uploads
- **avrdude.conf** - Configuration file for avrdude

## Deployment

### Production Build

```bash
MIX_ENV=prod mix release
```

### Running in Production

```bash
_build/prod/rel/tsw_io/bin/tsw_io start
```

### Configuration

Set environment variables:

```bash
SECRET_KEY_BASE=<generated-key>
DATABASE_PATH=/path/to/database.db
PHX_HOST=localhost
PORT=4000
```
