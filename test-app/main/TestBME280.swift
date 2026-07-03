// Copyright (c) 2026 Nicolas Christe
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import BME280
import GPIO
import I2C
import Platform

func testBME280(logger: Logger) {
    do {
        let bus = I2CMasterBus(
            i2cPort: I2C_NUM_0,
            sdaIoNum: GPIO_NUM_4,
            sclIoNum: GPIO_NUM_5)
        let sensor = BME280(i2cMasterBus: bus)
        try sensor.setup()
        let (temperature, pressure, humidity) = try sensor.read()
        logger.i("BME280: temperature=\(temperature) C, pressure=\(pressure) Pa, humidity=\(humidity) %")
        // sensor and bus freed by deinit (sensor before bus — reverse declaration order)
    } catch {
        logger.e("BME280: failed: \(error.name)")
    }
}
