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

import I2C
import Platform

private let log = Logger(tag: "BME280")

private enum Registers: UInt8 {
    case calibrationData = 0x88
    case humidityCalibrationData1 = 0xA1
    case humidityCalibrationData2 = 0xE1
    case chipID = 0xD0
    case reset = 0xE0
    case ctrlHum = 0xF2
    case status = 0xF3
    case ctrlMeas = 0xF4
    case config = 0xF5
    case data = 0xF7
}

public struct BME280: ~Copyable {

    private let device: I2CMasterBus.Device

    /// Aborts on failure — intended for boot-time static allocation.
    public init(i2cMasterBus: borrowing I2CMasterBus) {
        do {
            self.device = try i2cMasterBus.addDevice(deviceAddress: 0x76, sclSpeedHz: 100_000)
        } catch {
            log.e("BME280 init failed: \(error.name)")
            fatalError()
        }
    }

    public func setup() throws(Error) {
        log.d("Setting up BME280")
        if !calibrationDataValid {
            log.d("No cached calibration data")
            try reset()
        }
    }

    public func reset() throws(Error) {
        log.d("Resetting BME280 and reading calibration data")
        try device.transmit(data: [Registers.reset.rawValue, 0xB6], timeoutMs: 100)
        vTaskDelay(.init(ms: 100))
        let calibrationData1 = try device.transmitReceive(
            transmitData: [Registers.calibrationData.rawValue], receiveLength: 26, timeoutMs: 100)
        let calibrationData2 = try device.transmitReceive(
            transmitData: [Registers.humidityCalibrationData2.rawValue], receiveLength: 7, timeoutMs: 100)
        setCalibrationData(data1: calibrationData1, data2: calibrationData2)
    }

    public func read() throws(Error) -> (temperature: Float, pressure: Float, humidity: Float) {
        log.d("Reading BME280 sensor data")
        // Configure humidity oversampling (x1)
        try device.transmit(data: [Registers.ctrlHum.rawValue, 0x01], timeoutMs: 100)
        // Configure temperature and pressure oversampling (x1) and forced mode
        try device.transmit(data: [Registers.ctrlMeas.rawValue, 0x25], timeoutMs: 100)
        // Wait for measurement: max ~10.4 ms for x1 oversampling. 12 ms
        // ensures >=2 ticks at the 100 Hz default CONFIG_FREERTOS_HZ.
        vTaskDelay(.init(ms: 12))

        // Read all sensor data (pressure, temperature, humidity) - 8 bytes
        let data = try device.transmitReceive(transmitData: [Registers.data.rawValue], receiveLength: 8, timeoutMs: 100)

        // Parse raw values (20-bit for pressure and temperature, 16-bit for humidity)
        let adc_P = (Int32(data[0]) << 12) | (Int32(data[1]) << 4) | (Int32(data[2]) >> 4)
        let adc_T = (Int32(data[3]) << 12) | (Int32(data[4]) << 4) | (Int32(data[5]) >> 4)
        let adc_H = (Int32(data[6]) << 8) | Int32(data[7])

        // Apply compensation formulas (from BME280 datasheet)
        // Temperature compensation
        var var1 = (Double(adc_T) / 16384.0 - Double(dig_T1) / 1024.0) * Double(dig_T2)
        var var2 =
            ((Double(adc_T) / 131072.0 - Double(dig_T1) / 8192.0)
                * (Double(adc_T) / 131072.0 - Double(dig_T1) / 8192.0)) * Double(dig_T3)
        let t_fine = var1 + var2
        let temperature = Float(t_fine / 5120.0)

        // Pressure compensation
        var1 = (t_fine / 2.0) - 64000.0
        var2 = var1 * var1 * Double(dig_P6) / 32768.0
        var2 = var2 + var1 * Double(dig_P5) * 2.0
        var2 = (var2 / 4.0) + (Double(dig_P4) * 65536.0)
        var1 = (Double(dig_P3) * var1 * var1 / 524288.0 + Double(dig_P2) * var1) / 524288.0
        var1 = (1.0 + var1 / 32768.0) * Double(dig_P1)

        var pressure: Float = 0.0
        if var1 != 0.0 {
            var p = 1048576.0 - Double(adc_P)
            p = (p - (var2 / 4096.0)) * 6250.0 / var1
            var1 = Double(dig_P9) * p * p / 2147483648.0
            var2 = p * Double(dig_P8) / 32768.0
            p = p + (var1 + var2 + Double(dig_P7)) / 16.0
            pressure = Float(p / 100.0)  // Convert to hPa
        }

        // Humidity compensation
        var v_x1_u32r = t_fine - 76800.0
        v_x1_u32r =
            (Double(adc_H) - (Double(dig_H4) * 64.0 + Double(dig_H5) / 16384.0 * v_x1_u32r))
            * (Double(dig_H2) / 65536.0
                * (1.0 + Double(dig_H6) / 67108864.0 * v_x1_u32r
                    * (1.0 + Double(dig_H3) / 67108864.0 * v_x1_u32r)))
        v_x1_u32r = v_x1_u32r * (1.0 - Double(dig_H1) * v_x1_u32r / 524288.0)

        let humidity = Float(max(0.0, min(100.0, v_x1_u32r)))

        return (temperature: temperature, pressure: pressure, humidity: humidity)
    }
}

// Calibration data stored in RTC memory
@section(".rtc.data") @used private var magic: UInt32 = 0
@section(".rtc.data") @used private var dig_T1: UInt16 = 0
@section(".rtc.data") @used private var dig_T2: Int16 = 0
@section(".rtc.data") @used private var dig_T3: Int16 = 0
@section(".rtc.data") @used private var dig_P1: UInt16 = 0
@section(".rtc.data") @used private var dig_P2: Int16 = 0
@section(".rtc.data") @used private var dig_P3: Int16 = 0
@section(".rtc.data") @used private var dig_P4: Int16 = 0
@section(".rtc.data") @used private var dig_P5: Int16 = 0
@section(".rtc.data") @used private var dig_P6: Int16 = 0
@section(".rtc.data") @used private var dig_P7: Int16 = 0
@section(".rtc.data") @used private var dig_P8: Int16 = 0
@section(".rtc.data") @used private var dig_P9: Int16 = 0
@section(".rtc.data") @used private var dig_H2: Int16 = 0
@section(".rtc.data") @used private var dig_H4: Int16 = 0
@section(".rtc.data") @used private var dig_H5: Int16 = 0
@section(".rtc.data") @used private var dig_H1: UInt8 = 0
@section(".rtc.data") @used private var dig_H3: UInt8 = 0
@section(".rtc.data") @used private var dig_H6: Int8 = 0

private var calibrationDataValid: Bool {
    return magic == 0x0A11600D
}

private func setCalibrationData(data1: [UInt8], data2: [UInt8]) {
    // Read little-endian 16-bit values
    let b0 = UInt16(data1[0])
    let b1 = UInt16(data1[1])
    dig_T1 = b0 | (b1 << 8)

    let b2 = UInt16(data1[2])
    let b3 = UInt16(data1[3])
    dig_T2 = Int16(bitPattern: b2 | (b3 << 8))

    let b4 = UInt16(data1[4])
    let b5 = UInt16(data1[5])
    dig_T3 = Int16(bitPattern: b4 | (b5 << 8))

    let b6 = UInt16(data1[6])
    let b7 = UInt16(data1[7])
    dig_P1 = b6 | (b7 << 8)

    let b8 = UInt16(data1[8])
    let b9 = UInt16(data1[9])
    dig_P2 = Int16(bitPattern: b8 | (b9 << 8))

    let b10 = UInt16(data1[10])
    let b11 = UInt16(data1[11])
    dig_P3 = Int16(bitPattern: b10 | (b11 << 8))

    let b12 = UInt16(data1[12])
    let b13 = UInt16(data1[13])
    dig_P4 = Int16(bitPattern: b12 | (b13 << 8))

    let b14 = UInt16(data1[14])
    let b15 = UInt16(data1[15])
    dig_P5 = Int16(bitPattern: b14 | (b15 << 8))

    let b16 = UInt16(data1[16])
    let b17 = UInt16(data1[17])
    dig_P6 = Int16(bitPattern: b16 | (b17 << 8))

    let b18 = UInt16(data1[18])
    let b19 = UInt16(data1[19])
    dig_P7 = Int16(bitPattern: b18 | (b19 << 8))

    let b20 = UInt16(data1[20])
    let b21 = UInt16(data1[21])
    dig_P8 = Int16(bitPattern: b20 | (b21 << 8))

    let b22 = UInt16(data1[22])
    let b23 = UInt16(data1[23])
    dig_P9 = Int16(bitPattern: b22 | (b23 << 8))

    dig_H1 = data1[25]

    let h2_lsb = UInt16(data2[0])
    let h2_msb = UInt16(data2[1])
    dig_H2 = Int16(bitPattern: h2_lsb | (h2_msb << 8))

    dig_H3 = data2[2]
    // dig_H4 and dig_H5 are 12-bit signed values split across bytes
    let h4_msb = UInt16(data2[3])
    let h4_lsb = UInt16(data2[4] & 0x0F)
    let rawH4: UInt16 = (h4_msb << 4) | h4_lsb
    let h5_msb = UInt16(data2[5])
    let h5_lsb = UInt16(data2[4] >> 4)
    let rawH5: UInt16 = (h5_msb << 4) | h5_lsb

    // Sign-extend 12-bit values to 16-bit signed
    if (rawH4 & 0x0800) != 0 {
        dig_H4 = Int16(bitPattern: rawH4 | 0xF000)
    } else {
        dig_H4 = Int16(bitPattern: rawH4)
    }
    if (rawH5 & 0x0800) != 0 {
        dig_H5 = Int16(bitPattern: rawH5 | 0xF000)
    } else {
        dig_H5 = Int16(bitPattern: rawH5)
    }
    dig_H6 = Int8(bitPattern: data2[6])
    magic = 0x0A11600D
}
