# SwiftBME280

Swift driver for the BME280 temperature/pressure/humidity sensor. Swift module name: **`BME280`**.

Depends on: `SwiftPlatform`, `SwiftI2C`, `SwiftSupport`

## Files

| File | Role |
|---|---|
| `src/BME280.swift` | Public `BME280` struct + file-scope RTC-cached calibration data |

## Public API

```swift
let bus = I2CMasterBus(i2cPort: I2C_NUM_0, sdaIoNum: GPIO_NUM_6, sclIoNum: GPIO_NUM_7)
let sensor = BME280(i2cMasterBus: bus)
try sensor.setup()
let (temperature, pressure, humidity) = try sensor.read()
// No explicit cleanup — deinit handles it.
// Declare bus before sensor so Swift destroys them in reverse order (sensor first) — required IDF order.
```

## Non-obvious patterns

**Pure-Swift component** — no C wrapper, no `module.modulemap`.

**Caller owns the bus** — `BME280.init(i2cMasterBus:)` registers a `Device` on the caller's bus. `BME280` is `~Copyable`; its `deinit` removes only the device — the bus is cleaned up separately by the caller's `I2CMasterBus` going out of scope.

**Calibration cached in RTC memory** — the file-scope `dig_*` variables and `magic` cookie are annotated `@section(".rtc.data") @used` so the BME280's factory calibration coefficients survive deep-sleep. On boot, `setup()` checks `calibrationDataValid` (the `magic == 0x0A11600D` cookie) and only re-reads calibration over I2C when the cache is invalid. These helpers MUST stay at file scope for the linker section attribute to take effect.

**I2C address 0x76** — the SDO-grounded address; SDO-VCC variant (`0x77`) is not currently supported.
