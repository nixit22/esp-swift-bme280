# SwiftBME280

SwiftBME280 is a pure-Swift driver for the Bosch BME280 temperature, pressure,
and humidity sensor, built on top of [SwiftI2C](../SwiftI2C).

## Features

- One-shot temperature, pressure, and relative-humidity readings.
- Factory calibration coefficients cached in RTC memory across deep-sleep cycles.
- Soft-reset support.
- ESP-IDF errors surfaced as Swift typed throws (`throws(Error)`).

## API

### `BME280`

```swift
let sensor = BME280(i2cMasterBus: bus)
```

| Method | Description |
|---|---|
| `init(i2cMasterBus:)` | Register the sensor on the given I2C master bus (address `0x76`, 100 kHz). |
| `setup()` | Validate cached calibration; soft-reset and re-read if invalid. |
| `reset()` | Soft-reset the sensor and re-read calibration coefficients. |
| `read() -> (temperature: Float, pressure: Float, humidity: Float)` | Trigger a forced-mode measurement and return °C / hPa / %RH. |

`BME280` is `~Copyable` — no explicit cleanup call is needed; the underlying I2C device is removed automatically in `deinit`. The bus itself is not touched.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
