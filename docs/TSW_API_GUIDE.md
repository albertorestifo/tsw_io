# Train Sim World 6 External Interface API - Quick Reference Guide

## Overview

The TSW6 External Interface API allows external applications to read real-time simulation data and control train cab elements via JSON over TCP.

---

## Setup

### 1. Enable the API

Add `-HTTPAPI` to Steam launch options:

1. Right-click TSW6 in Steam
2. Select Properties
3. Go to General tab
4. Add `-HTTPAPI` to Launch Options

### 2. Get Your API Key

After launching the game once with the flag, find `CommAPIKey.txt`:

| Build Type      | Location                                                              |
| --------------- | --------------------------------------------------------------------- |
| **Release**     | `Documents\My Games\TrainSimWorld6\Saved\Config\CommAPIKey.txt`       |
| **Development** | `[Install Dir]\WindowsNoEditor\TS2Prototype\Saved\Config\CommAPIKey.txt` |

The key is a base64-encoded string like: `7I0HydlP4d4/66aQPrrHg43N4X5Y+6gCnRIjtIAOwA8=`

**Security Notes**:
- Never share your key with anyone
- Delete the file to regenerate if compromised
- The key can change at any time; read it dynamically in your application

### 3. Connection Details

| Setting      | Value                          |
| ------------ | ------------------------------ |
| **Host**     | `127.0.0.1` (localhost only by default) |
| **Port**     | `31270`                        |
| **Protocol** | HTTP over TCP (not HTTPS)      |

### 4. Enable Network Access (Optional)

To allow connections from other computers, add to `Saved\Config\WindowsNoEditor\engine.ini`:

```ini
[HTTPServer.Listeners]
DefaultBindAddress=0.0.0.0
```

---

## Authentication

All requests require the `DTGCommKey` header:

```
DTGCommKey: <your-key-from-CommAPIKey.txt>
```

### Response Codes

| Code | Meaning |
| ---- | ------- |
| 200  | Success |
| 403  | Invalid API key |

---

## API Endpoints

| Method | Path                              | Description                    |
| ------ | --------------------------------- | ------------------------------ |
| GET    | `/info`                           | List available commands        |
| GET    | `/list`                           | List all available nodes/paths |
| GET    | `/list/<path>`                    | List nodes under a specific path |
| GET    | `/get/<path>.<endpoint>`          | Read a value                   |
| PATCH  | `/set/<path>.<endpoint>?Value=X`  | Write a value                  |
| POST   | `/subscription/<path>?Subscription=ID` | Subscribe to endpoint    |
| GET    | `/subscription?Subscription=ID`   | Read subscription values       |
| DELETE | `/subscription?Subscription=ID`   | Remove subscription            |
| GET    | `/listsubscriptions`              | List active subscriptions      |

### Path Structure

- **Nodes** form the path hierarchy, separated by `/`
- **Endpoints** are data points, accessed with `.` after the node path

Example: `/get/CurrentDrivableActor/Throttle(Lever).InputValue`
- Node path: `CurrentDrivableActor/Throttle(Lever)`
- Endpoint: `InputValue`

---

## Example Requests

### Using curl

```bash
# Get current speed (returns meters/second)
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/get/CurrentDrivableActor.Function.HUD_GetSpeed"

# Response:
# {"Result": "Success", "Values": {"Speed (ms)": 4.54}}
```

```bash
# Get throttle notch position
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/get/CurrentDrivableActor/Throttle(Lever).Function.GetCurrentNotchIndex"

# Response:
# {"Result": "Success", "Values": {"ReturnValue": 4}}
```

```bash
# Set throttle position (PATCH method)
curl -X PATCH -H "DTGCommKey: <key>" \
  "http://localhost:31270/set/CurrentDrivableActor/Throttle(Lever).InputValue?Value=0.250"

# Response:
# {"Result": "Success"}
```

```bash
# List available controls on current vehicle
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/list/CurrentDrivableActor"
```

```bash
# Set weather cloudiness
curl -X PATCH -H "DTGCommKey: <key>" \
  "http://localhost:31270/set/WeatherManager.Cloudiness?Value=0.5"
```

---

## Key Nodes Reference

### CurrentDrivableActor

The player's currently driven vehicle. Contains all controls and simulation data.

**Common Controls:**
- `Throttle(Lever)` - Throttle control
- `TrainBrake(Lever)` - Train brake
- `DynamicBrake(Lever)` - Dynamic brake
- `Reverser(Lever)` - Direction control
- `Horn` - Horn control
- `Bell` - Bell control
- `Headlights` - Headlight control
- `Coupler_F` / `Coupler_R` - Front/rear couplers

**HUD Functions (read-only):**
- `Function.HUD_GetSpeed` - Speed in m/s
- `Function.HUD_GetBrakeGauge_1` - Brake pressure gauge 1
- `Function.HUD_GetBrakeGauge_2` - Brake pressure gauge 2
- `Function.HUD_GetAmmeter` - Ammeter reading
- `Function.HUD_GetIsSlipping` - Wheel slip indicator

**Simulation Data:**
- `Simulation/` - Deep simulation nodes (axles, wheels, brakes, cooling, etc.)

> **Note**: Control names vary between trains. Always use `/list` to discover available controls.

### WeatherManager

Control weather conditions. All values range from 0 to 1.

| Endpoint      | Description                                    |
| ------------- | ---------------------------------------------- |
| `Temperature` | Current temperature (affects rain vs snow)     |
| `Cloudiness`  | Cloud cover level                              |
| `Precipitation` | Rain/snow intensity                          |
| `Wetness`     | Ground wetness                                 |
| `GroundSnow`  | Settled snow amount                            |
| `PiledSnow`   | Piled snow amount                              |
| `FogDensity`  | Fog intensity (0-0.05 works best for subtlety) |
| `Reset`       | Reset weather to defaults                      |

### TimeOfDay

Read-only time and astronomical data.

| Endpoint              | Description                    |
| --------------------- | ------------------------------ |
| `LocalTime`           | Local time (ticks)             |
| `LocalTimeISO8601`    | Local time in ISO format       |
| `WorldTime`           | World/UTC time (ticks)         |
| `WorldTimeISO8601`    | World time in ISO format       |
| `GMTOffset`           | Timezone offset                |
| `DayPercentage`       | Progress through the day (0-1) |
| `SunriseTime`         | Sunrise time                   |
| `SolarNoonTime`       | Solar noon time                |
| `SunsetTime`          | Sunset time                    |
| `SunPositionAzimuth`  | Sun azimuth angle              |
| `SunPositionAltitude` | Sun altitude angle             |
| `MoonPositionAzimuth` | Moon azimuth angle             |
| `MoonPositionAltitude`| Moon altitude angle            |
| `OriginLatitude`      | Route origin latitude          |
| `OriginLongitude`     | Route origin longitude         |

### DriverAid

Track and route information ahead of the player.

**PlayerInfo** (`/get/DriverAid.PlayerInfo`):
- `geoLocation` - Current lat/long
- `currentTile` - Internal tile coordinates
- `playerProfileName` - Player name
- `cameraMode` - Current camera view
- `currentServiceName` - Active service/scenario

**TrackData** (`/get/DriverAid.TrackData`):
- `lastPlayerPosition` - Height, distance, tunnel info
- `trackHeights` - Array of upcoming track heights

**Data** (`/get/DriverAid.Data`):
- `signalSeen` - Is a signal visible ahead
- `distanceToSignal` - Distance to next signal
- `signalAspectClass` - Signal aspect (Stop, Clear, etc.)
- `bSignalIsPermissive` - Is signal permissive
- `speedLimit` - Current speed limit
- `nextSpeedLimit` - Upcoming speed limit
- `distanceToNextSpeedLimit` - Distance to limit change
- `gradient` - Current track gradient
- `trackMaxSpeed` - Track speed limit
- `serviceMaxSpeed` - Service speed limit
- `formationMaxSpeed` - Train formation speed limit

### VirtualRailDriver

Abstraction layer compatible with Rail Driver hardware. Simpler than direct control access.

```bash
# Enable Virtual Rail Driver (disables physical Rail Driver)
curl -X PATCH -H "DTGCommKey: <key>" \
  "http://localhost:31270/set/VirtualRailDriver.Enabled?Value=true"

# Set throttle via Virtual Rail Driver
curl -X PATCH -H "DTGCommKey: <key>" \
  "http://localhost:31270/set/VirtualRailDriver.Throttle?Value=0.5"
```

### CurrentFormation

Access all vehicles in the player's train consist.

```bash
# Get vehicle class at index 0
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/get/CurrentFormation/0.ObjectClass"

# Get vehicle location
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/get/CurrentFormation/0.LatLon"
```

> **Note**: Index 0 is not always the driven vehicle. In terminus turnarounds, the player may be driving from a different index.

### Timetable

Access all vehicles in the active scenario.

```bash
# List all vehicle IDs
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/list/Timetable"

# Get specific vehicle info by GUID
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/get/Timetable/<GUID>.ObjectClass"
```

---

## Subscriptions

Efficiently poll multiple values in a single request.

### Creating Subscriptions

```bash
# Subscribe to multiple endpoints with the same subscription ID
curl -X POST -H "DTGCommKey: <key>" \
  "http://localhost:31270/subscription/CurrentDrivableActor.Function.HUD_GetSpeed?Subscription=1"

curl -X POST -H "DTGCommKey: <key>" \
  "http://localhost:31270/subscription/CurrentDrivableActor.Function.HUD_GetBrakeGauge_1?Subscription=1"

curl -X POST -H "DTGCommKey: <key>" \
  "http://localhost:31270/subscription/CurrentDrivableActor.Function.HUD_GetAmmeter?Subscription=1"
```

### Reading Subscriptions

```bash
curl -H "DTGCommKey: <key>" \
  "http://localhost:31270/subscription?Subscription=1"
```

Response:
```json
{
  "RequestedSubscriptionID": 1,
  "Entries": [
    {
      "Path": "CurrentDrivableActor.Function.HUD_GetSpeed",
      "NodeValid": true,
      "Values": {"Speed (ms)": 5.97}
    },
    {
      "Path": "CurrentDrivableActor.Function.HUD_GetBrakeGauge_1",
      "NodeValid": true,
      "Values": {"WhiteNeedle (Pa)": 720444.4375, "RedNeedle (Pa)": 0}
    }
  ]
}
```

### Removing Subscriptions

```bash
curl -X DELETE -H "DTGCommKey: <key>" \
  "http://localhost:31270/subscription?Subscription=1"
```

### Best Practices

1. **Startup cleanup**: DELETE your subscription IDs first (ignore errors), then create fresh
2. **Group by poll rate**: Use different subscription IDs for different update frequencies
3. **Subscriptions don't persist**: Must be recreated each game session

---

## Control Value Ranges

Controls use normalized 0-1 values. Query metadata to understand the mapping:

| Endpoint                          | Returns                        |
| --------------------------------- | ------------------------------ |
| `Function.GetMinimumInputValue`   | Minimum value (usually 0)      |
| `Function.GetMaximumInputValue`   | Maximum value (usually 1)      |
| `Function.GetNotchCount`          | Number of discrete notches     |

### Calculating Notch Values

```
notch_value = notch_index / (notch_count - 1)
```

**Example: ES44C4 Throttle**
- Notch count: 9 (positions 0-8)
- Notch 1 = 1/8 = 0.125
- Notch 4 = 4/8 = 0.5
- Notch 8 = 8/8 = 1.0

Values between notches will "fall" to the nearest notch position.

### Input vs Output Values

- **InputValue**: What you set (0-1 normalized)
- **OutputValue**: Real-world equivalent (e.g., notch number, percentage)

---

## Response Format

### Success Response

```json
{
  "Result": "Success",
  "Values": {
    "Speed (ms)": 4.54
  }
}
```

### Error Responses

**Invalid API Key (403)**:
```json
{
  "errorCode": "dtg.comm.InvalidKey",
  "errorMessage": "API Key for request doesn't match CommAPIKey.txt in the game config directory."
}
```

**Invalid Path**:
```json
{
  "Result": "Error",
  "Message": "Node failed to return valid data."
}
```

**Subscription Not Found**:
```json
{
  "errorCode": "dtg.comm.NoSuchSubscription",
  "errorMessage": "Could not find requested subscription ID"
}
```

---

## Important Notes

### Performance
- No server-side rate limiting
- Excessive requests will impact game FPS
- Use subscriptions for frequent polling
- Evaluate request rates vs performance impact

### Control Interaction
- API calls reflect/affect current train state
- Keyboard/controller input can override API-set positions
- Consider periodic re-capture of control positions
- Values set via API are immediately reflected in-game

### Vehicle Variations
- Each train has unique control names and structures
- Always use `/list` to discover available controls
- Some controls exist on some trains but not others
- Simulation depth varies by vehicle

### Data Units
- Speed: meters per second (m/s)
- Pressure: Pascals (Pa)
- Angles: degrees
- Distances: meters (in DriverAid)
- Most controls: 0-1 normalized

---

## Testing Tools

### curl
Command-line tool for quick API testing.
- Download: https://curl.se/windows/

### Postman
GUI tool for exploring and testing the API.
- Download: https://www.postman.com/downloads/
- Add `DTGCommKey` in Headers tab
- Add parameters in Params tab
