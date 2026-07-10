# SwiftBME280

Pure-Swift driver for the Bosch BME280 temperature/pressure/humidity sensor, built on top of [SwiftI2C](../esp-swift-i2c). Swift module name: **`BME280`**.

Depends on: `SwiftPlatform`, `SwiftI2C`, `SwiftSupport`.

## Usage

```swift
import BME280

let bus = I2CMasterBus(i2cPort: I2C_NUM_0, sdaIoNum: GPIO_NUM_6, sclIoNum: GPIO_NUM_7)
let sensor = BME280(i2cMasterBus: bus)
try sensor.setup()
let (temperature, pressure, humidity) = try sensor.read()
// No explicit cleanup — deinit handles it.
// Declare bus before sensor so Swift destroys them in reverse order (sensor first) — required IDF order.
```

See [`CLAUDE.md`](CLAUDE.md) for full API details and non-obvious patterns.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
