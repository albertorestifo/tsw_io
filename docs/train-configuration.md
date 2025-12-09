# Train Configuration Guide

This guide covers setting up train configurations and binding hardware inputs to simulator controls.

## Understanding Train Configurations

Each train in Train Sim World has unique cab elements (throttle, reverser, brakes). TWS IO stores configurations that map your hardware to these elements.

### Train Identifier

Trains are identified by a prefix derived from the simulator's formation data. For example:

```
Formation: ["Class_BR_DR4_08_A", "Class_BR_DR4_08_B", ...]
Identifier: "Class_BR_DR4"
```

When you drive this train in the simulator, TWS IO automatically activates the matching configuration.

## Creating a Train Configuration

### From Auto-Detection

1. Start Train Sim World with your desired train loaded
2. Navigate to **Trains** in TWS IO
3. The detected train appears with a **Create Configuration** option
4. Click to create a configuration pre-filled with the train identifier

### Manual Creation

1. Navigate to **Trains**
2. Click **New Train**
3. Enter:
   - **Name** - Friendly name (e.g., "BR Class 66")
   - **Identifier** - Must match simulator's ObjectClass prefix
4. Save the train

## Adding Cab Elements

### Element Types

| Type | Description | Examples |
|------|-------------|----------|
| Lever | Analog control with notches | Throttle, Reverser, Dynamic Brake |
| Button | Momentary input (coming soon) | Horn, Bell, Sander |
| Switch | Toggle input (coming soon) | Headlights, Wipers |

### Creating a Lever Element

1. Open your train configuration
2. Click **Add Element**
3. Enter element name (e.g., "Throttle", "Reverser")
4. Select type: **Lever**
5. Save the element

## Configuring Lever Endpoints

Each lever needs API endpoints to communicate with the simulator.

### Auto-Detection

1. With the train loaded in simulator, click **Auto-Detect** on the lever
2. TWS IO queries the simulator for available controls
3. Endpoints are automatically configured:
   - Value endpoint (read/write current position)
   - Notch count and index endpoints
   - Min/max value endpoints

### Manual Configuration

Click the **Settings** icon on the lever to manually configure:

| Field | Description | Example |
|-------|-------------|---------|
| Value Endpoint | Read/write lever position | `/CurrentDrivableActor/Throttle(Lever).InputValue` |
| Min Endpoint | Minimum value | `/CurrentDrivableActor/Throttle(Lever).Min` |
| Max Endpoint | Maximum value | `/CurrentDrivableActor/Throttle(Lever).Max` |
| Notch Count | Number of notches | `/CurrentDrivableActor/Throttle(Lever).Notches` |
| Notch Index | Current notch | `/CurrentDrivableActor/Throttle(Lever).NotchesIndex` |

## Notch Configuration

Many train controls have discrete positions (notches). TWS IO supports both continuous and notched controls.

### Notch Types

| Type | Behavior | Use Case |
|------|----------|----------|
| Gate | Fixed value, snaps to position | Reverser (Forward/Neutral/Reverse) |
| Linear | Interpolates between boundaries | Throttle notches, dynamic brake |

### Auto-Detecting Notches

1. Click **Auto-Detect** on a configured lever
2. TWS IO reads notch data from the simulator
3. Notch positions and types are automatically set

### Notch Mapping Wizard

Maps hardware input ranges to lever notches:

1. Click **Map Notches** on a lever with bound input
2. The wizard guides you through each notch boundary:
   - Move your physical input to the notch boundary position
   - Click **Record** to save the input value
   - Repeat for all notch boundaries
3. Save when complete

The wizard validates:
- No gaps between notches
- Full input range covered (0.0 to 1.0)
- Boundaries don't overlap

## Binding Hardware Inputs

Connect calibrated hardware inputs to lever elements.

### Prerequisites

Before binding:
1. Hardware device configured and connected
2. Input calibrated (has min/max values)
3. Lever element created with endpoints

### Binding Process

1. Find the lever element in your train configuration
2. Click **Bind Input**
3. Select from available calibrated inputs
4. The binding is created and enabled

### Binding Status

| Status | Meaning |
|--------|---------|
| Bound | Input connected to lever |
| Unbound | No input assigned |
| Disabled | Binding exists but inactive |

## Real-Time Operation

### Automatic Train Detection

When you load a train in the simulator:

1. TWS IO polls the simulator every 15 seconds
2. Detects the current formation's identifier
3. Matches against stored train configurations
4. Activates bindings for the matched train

### Manual Train Activation

Click **Set Active** on any train to manually activate its bindings.

### Value Flow

When operating:

```
Hardware Input → Calibration → Notch Mapping → Simulator API
     ↓               ↓              ↓              ↓
  0-1023         0.0-1.0       Notch Value    Lever Moves
```

## API Explorer

For debugging, use the built-in API Explorer:

1. Click the **API Explorer** icon on a lever
2. Enter an API path to query
3. View live values from the simulator

Common paths to explore:
- `/CurrentDrivableActor.Info` - List available controls
- `/CurrentDrivableActor/Throttle(Lever).InputValue` - Current throttle
- `/CurrentDrivableActor.Function.HUD_GetSpeed` - Current speed

## Troubleshooting

### Train Not Detected

1. Verify simulator is running with External Interface enabled
2. Check TWS IO simulator connection status
3. Ensure train identifier matches exactly

### Lever Not Responding

1. Confirm input is bound and enabled
2. Check calibration is complete
3. Verify endpoint paths are correct
4. Test with API Explorer

### Wrong Notch Selected

1. Re-run notch mapping wizard
2. Verify notch boundaries don't overlap
3. Check input calibration accuracy
