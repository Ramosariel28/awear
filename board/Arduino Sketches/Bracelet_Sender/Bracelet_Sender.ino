/*
 * Project: ESP32-C3 Wireless Biometric Bracelet (HR, SpO2, Respiration, Body Temp, Stress/RMSSD)
 * Platform: Arduino IDE 2.3.7 | esp32 by Espressif Systems 3.3.5
 * Board: ESP32-C3 Dev Module / Generic / LOLIN C3 Mini (preferred)
 * 
 * Sensors:
 * 1. GY-MAX30102 (Pulse Oximeter)
 * 2. MPU6050 (Accelerometer/Gyro - Quality Control)
 * 3. MAX30205 (Body Temperature)
 *
 * * Hardware Connections (I2C Shared Bus):
 * ESP32-C3 GPIO 8  <--> MAX30102 SDA <--> MPU6050 SDA <--> MAX30205 SDA
 * ESP32-C3 GPIO 9  <--> MAX30102 SCL <--> MPU6050 SCL <--> MAX30205 SCL
 * ESP32-C3 3.3V    <--> MAX30102 VIN <--> MPU6050 VCC <--> MAX30205 VCC
 * ESP32-C3 GND     <--> MAX30102 GND <--> MPU6050 GND <--> MAX30205 GND
 * 
 * We are also connecting MAX30205 A0, A1, A2 to GND (Sets I2C address to 0x48 (standard))
 *
 * Dependencies:
 * - SparkFun MAX3010x Pulse and Proximity Sensor Library
 * - Adafruit MPU6050
 *
 * Features:
 * - Vital Statistics Measurement
 * - Receiver Pairing
 * - Deep Sleep Power Saving
 *
 * Available Commands:
 * COMMAND FORMAT: "AWEAR_IDENTIFY"
 * COMMAND FORMAT: "PAIR:AA:BB:CC:DD:EE:FF" "PAIR:FF:FF:FF:FF:FF:FF" "PAIR:08:92:72:85:83:78"
 * COMMAND FORMAT: "FLASH_MODE"
 */

#include <Wire.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <Preferences.h>
#include <ArduinoJson.h>

// SENSOR LIBRARIES
#include "MAX30105.h" // From SparkFun Library
#include "spo2_algorithm.h" // From SparkFun Library
#include "heartRate.h" // From SparkFun Library
#include <Adafruit_MPU6050.h> // From Adafruit Library
#include <Adafruit_Sensor.h> // From Adafruit Library

// ================= CONFIGURATION =================
// MAC Address of your Receiver
uint8_t receiverAddress[6] = {0x08, 0x92, 0x72, 0x85, 0x83, 0x78}; // {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}; Default to Broadcast (Placeholders)

#define WIFI_CHANNEL 1
#define I2C_SDA_PIN 8
#define I2C_SCL_PIN 9
#define MAX30205_ADDRESS 0x48
#define LED_PIN 10

// Timing & Thresholds
#define CAPTURE_WINDOW_MS   20000  // Duration of active sampling (20 sec)
#define SLEEP_DURATION_SEC  40     // Sleep time (Total cycle = 60 sec)
#define SAMPLING_RATE       400    // Hz. High rate needed for RMSSD precision
#define PULSE_WIDTH         411    // us. 18-bit resolution
#define ADC_RANGE           4096   // nA. Full scale range
#define MOTION_THRESHOLD    2.0    // rad/s. Gatekeeper Gyro threshold

// Biometrics Tuning (Finger vs Wrist)

// 1. MAX30102 LED Power
// 0x1F (Low) for Finger to avoid saturation.
// 0x7F (High) for Wrist to penetrate thicker skin.
#define SENSOR_LED_POWER 0x7F

// 2. Respiration Sensitivity (Baseline Wander)
// Finger: 10.0 (Clean signal, small waves)
// Wrist:  50.0 (Noisy signal, needs big waves to count)
#define RR_MIN_SIGNAL_RANGE 20.0 

// 3. Respiration Peak Threshold
// Finger: 0.15 (15% of wave height)
// Wrist:  0.25 (25% of wave height to reject motion noise)
#define RR_PEAK_THRESHOLD_RATIO 0.15

// 4. Respiration Limits
// Finger: 3.0 (Allows deep, slow testing breaths)
// Wrist:  6.0 (Standard human lower limit)
#define RR_MIN_BPM 3.0
#define RR_MAX_BPM 60.0

// ================= DATA STRUCTURES =================
// Must match Receiver exactly
typedef struct __attribute__((packed)) struct_message {
  uint32_t packetId;     
  float heartRate;       
  int32_t spo2;
  float respiration;          
  float temperature;     
  float rmssd;           
  bool motionArtifact;
} struct_message;

struct_message outgoingData;
esp_now_peer_info_t peerInfo;

// ================= GLOBAL OBJECTS =================
Preferences preferences;
MAX30105 particleSensor;
Adafruit_MPU6050 mpu;

// Analysis Buffers
#define MAX_BEATS 60 // Max expected beats in capture window
unsigned long beatTimes[MAX_BEATS];
int beatCount = 0;

// SpO2 Buffers (Downsampled)
const int SPO2_WINDOW_SIZE = 100; // (safe for memory/math)
uint32_t irBuffer[SPO2_WINDOW_SIZE];
uint32_t redBuffer[SPO2_WINDOW_SIZE];

// Respiration Buffers
const int RR_WINDOW_SIZE = 160; 
uint32_t rrBuffer[RR_WINDOW_SIZE];
int rrBufferIndex = 0;

// Results storage
int32_t algo_spo2, algo_hr;
int8_t validSPO2, validHeartRate;
float skinTemperature = 0.0;
bool motionArtifactDetected = false;
float maxDetectedRotation = 0.0;

// RTC Memory (Persists in Deep Sleep)
RTC_DATA_ATTR int bootCounter = 0; 
RTC_DATA_ATTR uint32_t totalPacketsSent = 0; 

// ================= FORWARD DECLARATIONS =================
void enterDockedMode(); // The new "Config/Idle" Loop
void sendIdentityJSON();
void stopSensors();

// ================= CALLBACKS =================
void OnDataSent(const esp_now_send_info_t * info, esp_now_send_status_t status) {

  // Optional: Verify the ACK is from our intended receiver
  // const uint8_t* peer_mac = info->peer_addr;
    
  if (status == ESP_NOW_SEND_SUCCESS) {
    if(Serial) Serial.println("[PING] Success (ACK Received)");
    digitalWrite(LED_PIN, LOW); delay(20); digitalWrite(LED_PIN, HIGH); // Short blink for success
  } else {
    if(Serial) Serial.println("[PING] Fail (No ACK)");
    digitalWrite(LED_PIN, LOW); delay(200); digitalWrite(LED_PIN, HIGH); // Long blink for failure
  }
}

// ================= MAIN CYCLE FLOW =================
void setup() {

  Serial.begin(115200);

  // We wait up to 3 seconds for the computer to connect.
  // If no computer connects (Battery Mode), we move on.
  unsigned long startWait = millis();
  while (!Serial && (millis() - startWait < 3000)) {
    delay(10);
  }
  
  // Clear garbage from the line
  if(Serial) {
     delay(1000); 
     Serial.println("\n=== SYSTEM START ==="); 
  }
  // -----------------------------------------------------------------

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);
  
  // 1. Preferences
  loadPreferences(); // Load Saved MAC from Memory
  checkForCommand(); // Listen for Commands (Startup Phase)

  initRadio(); // 2. Radio Initialization
  initSensors(); // 3. Sensors Initialization

  bool success = runMeasurementLoop(); // 4. The Core Job: Measure Data ; stops on Docked Mode
  stopSensors(); // 5. Sensors Shutdown

  if (success) { // continue only if finished the job
    processBiometrics(); // 6. Data Processing
    transmitData(); // 7. Send Data
  }

  enterDeepSleep(); // 8. Goodnight

}

void loop() {
  // Unreachable in Deep Sleep architecture
}

// ================= INTERRUPT & DOCKED MODE HANDLER =================
// Returns TRUE if we stopped operations and entered Docked Mode
bool checkForCommand() {
  if (!Serial) return false; 
  if (!Serial.available()) return false;

  String cmd = Serial.readStringUntil('\n');
  cmd.trim();

  // --- CMD 1: IDENTIFY ---
  if (cmd == "AWEAR_IDENTIFY") {
    stopSensors(); // 1. Stop Everything (Immediate Interrupt)
    sendIdentityJSON(); // 2. Reply Immediately
    enterDockedMode(); // 3. Enter Docked Mode (Infinite Loop)
    return true; 
  }
  
  // --- CMD 2: PAIRING ---
  else if (cmd.startsWith("PAIR:")) {
    stopSensors(); // 1. Stop Everything
    parseAndSaveMac(cmd.substring(5)); // 2. Execute Pairing & Reply JSON ("PAIRED_OK")
    enterDockedMode(); // 3. Enter Docked Mode
    return true; 
  }
  
  // --- CMD 3: FLASH MODE ---
  else if (cmd == "FLASH_MODE") {
    stopSensors(); // 1. Stop Everything
    Serial.println("\n{\"status\": \"READY_TO_FLASH\"}"); // 2. Reply Immediately
    enterDockedMode(); // 3. Enter Docked Mode
    return true; 
  }

  return false; // No command matched
}

// THE "DOCKED" STATE
void enterDockedMode() {
  Serial.println("[INFO] Entering Docked Mode (Sensors Stopped)");
  
  // Visual Confirm: Double Blink
  digitalWrite(LED_PIN, LOW); delay(100); digitalWrite(LED_PIN, HIGH); delay(100);
  digitalWrite(LED_PIN, LOW); delay(100); digitalWrite(LED_PIN, HIGH);

  unsigned long disconnectStartTime = 0;
  bool isDisconnecting = false;

  // Infinite Loop
  while (true) {
    // A. DEBOUNCED DISCONNECT LOGIC (1 Second Tolerance)
    if (!Serial) {
      if (!isDisconnecting) { isDisconnecting = true; disconnectStartTime = millis(); }
      if (millis() - disconnectStartTime > 1000) ESP.restart(); 
    } else {
      isDisconnecting = false;
    }

    // B. LISTEN FOR NEW COMMANDS
    // (Allows you to Pair again or Check ID again without unplugging)
    if (Serial && Serial.available()) {
      String cmd = Serial.readStringUntil('\n');
      cmd.trim();

      if (cmd == "AWEAR_IDENTIFY") {
        sendIdentityJSON();
      }
      else if (cmd.startsWith("PAIR:")) {
        parseAndSaveMac(cmd.substring(5));
      }
      else if (cmd == "FLASH_MODE") {
        Serial.println("\n{\"status\": \"READY_TO_FLASH\"}");
      }
    }
    
    // C. Heartbeat Blink (Every 2s)
    static unsigned long lastBlink = 0;
    if (millis() - lastBlink > 2000) {
      digitalWrite(LED_PIN, LOW); delay(50); digitalWrite(LED_PIN, HIGH);
      lastBlink = millis();
    }
    delay(10);
  }
}

void sendIdentityJSON() {
  JsonDocument doc;
  doc["status"] = "Sender Ready";
  doc["device"] = "AWEAR_SENDER"; 
  doc["mac"] = WiFi.macAddress();
  
  char pairStr[18];
  snprintf(pairStr, sizeof(pairStr), "%02X:%02X:%02X:%02X:%02X:%02X",
     receiverAddress[0], receiverAddress[1], receiverAddress[2], 
     receiverAddress[3], receiverAddress[4], receiverAddress[5]);
  doc["paired_to"] = pairStr;
  
  serializeJson(doc, Serial);
  Serial.println();
}

// ================= MODULE 1: PREFERENCES & PAIRING =================
// We store the paired receiver's MAC on NVS (Non-Volatile Storage) of ESP32

void loadPreferences() {
  preferences.begin("vital_cfg", true); // Read-only mode first
  size_t len = preferences.getBytesLength("peer_mac");
  if (len == 6) {
    preferences.getBytes("peer_mac", receiverAddress, 6);

    // Print current saved MAC
    if (Serial) {
      Serial.printf("\n[BOOT] Paired with Receiver: %02X:%02X:%02X:%02X:%02X:%02X\n", 
                    receiverAddress[0], receiverAddress[1], receiverAddress[2], 
                    receiverAddress[3], receiverAddress[4], receiverAddress[5]);
    }
  } else {
    // If no MAC is found
    if (Serial) Serial.println("\n[BOOT] No Saved Pair! Waiting for Serial config...");
  }
  preferences.end();
}

void parseAndSaveMac(String macStr) {
  uint8_t newMac[6];
  int values[6];
  // Parse hex string
  int parsed = sscanf(macStr.c_str(), "%x:%x:%x:%x:%x:%x", 
                      &values[0], &values[1], &values[2], 
                      &values[3], &values[4], &values[5]);
                      
  if (parsed == 6) {
    for(int i=0; i<6; i++) newMac[i] = (uint8_t)values[i];

    // Save to NVS
    preferences.begin("vital_cfg", false); // Read-Write mode
    preferences.putBytes("peer_mac", newMac, 6);
    preferences.end();

    // Update local variable
    memcpy(receiverAddress, newMac, 6);
    if (Serial) Serial.println("\n{\"status\": \"PAIRED_OK\"}");
    digitalWrite(LED_PIN, LOW); delay(1000); digitalWrite(LED_PIN, HIGH);
  } else {
    if (Serial) Serial.println("\n{\"status\": \"PAIR_FAIL\"}");
  }
}

// ================= MODULE 2: RADIO INITIALIZATION =================
void initRadio() {

  // 1. Initialize WiFi
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(1000);

  // 2. Set Channel
  esp_wifi_set_promiscuous(true);
  esp_wifi_set_channel(WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE);
  esp_wifi_set_promiscuous(false);

  // 3. Init ESP-NOW
  if (esp_now_init() != ESP_OK) {
    if(Serial) Serial.println("\n[ERR] ESP-NOW Init Failed");
    return;
  }
  
  // Register Send Callback
  esp_now_register_send_cb(OnDataSent);

  // 4. Register Peer
  memset(&peerInfo, 0, sizeof(peerInfo)); // 1. Clear struct (Remove garbage)
  memcpy(peerInfo.peer_addr, receiverAddress, 6); // 2. Copy MAC
  peerInfo.channel = WIFI_CHANNEL; // 3. Set Channel (Explicitly)
  peerInfo.encrypt = false; // 4. Disable Encryption (Reset LMK)
  peerInfo.ifidx = WIFI_IF_STA; // 5. Set Interface (Explicitly) (Required for ESP32-C3 / IDF 5.x)

  // 5. Add Peer
  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
     if(Serial) Serial.println("[ERR] Failed to add peer");
  } else {
     if(Serial) Serial.println("[OK] Radio Initialized & Peer Added");
  }
}

// ================= MODULE 3: SENSORS INITIALIZATION =================
void initSensors() {

  // I2C BUS INITIALIZATION
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(400000);

  // SENSOR INITIALIZATION: MAX30102
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    if (Serial) Serial.println("\n[ERR] MAX30102 Missing");
  }

  // Setup parameters: Brightness, SampleAverage, LedMode, SampleRate, PulseWidth, ADCRange
  // SampleAverage = 1 (No averaging) is CRITICAL for accurate PRV/RMSSD analysis
  particleSensor.setup(60, 1, 2, SAMPLING_RATE, PULSE_WIDTH, ADC_RANGE); 
  particleSensor.setPulseAmplitudeRed(SENSOR_LED_POWER); // 0x1F for finger, 0x7F for wrist
  particleSensor.setPulseAmplitudeIR(SENSOR_LED_POWER); // 0x1F for finger, 0x7F for wrist
  particleSensor.setPulseAmplitudeGreen(0);

  // SENSOR INITIALIZATION: MPU6050
  if (!mpu.begin()) {
    if (Serial) Serial.println("\n[ERR] MPU6050 Missing");
  }
  mpu.enableSleep(false); // Explicitly Wake up

  // Setup MPU for generic motion detection
  mpu.setAccelerometerRange(MPU6050_RANGE_2_G);
  mpu.setGyroRange(MPU6050_RANGE_250_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  // SENSOR INITIALIZATION: MAX30205 (MANUAL WAKEUP)
  Wire.beginTransmission(MAX30205_ADDRESS);
  Wire.write(0x01); // Select Config Register
  Wire.write(0x00); 
  if (Wire.endTransmission() == 0) {
  } else {
      if (Serial) Serial.println(F("\n[ERR] MAX30205 Missing"));
  }
  
  delay(500); // Stabilization time
}

// ================= MODULE 4: MEASUREMENT =================
bool runMeasurementLoop() {
  if (Serial) Serial.println("\n[TASK] Starting Capture (20s)...");
  
  // Reset Cycle Variables
  unsigned long windowStart = millis();
  long lastDotTime = 0;
  long lastMotionCheck = 0;
  long lastBeatTime = 0;
  long irValue = 0;
  long redValue = 0;
  long irThreshold = 10000;

  int sampleCounter = 0;
  int bufferIndex = 0;
  rrBufferIndex = 0;

  beatCount = 0;
  motionArtifactDetected = false;
  maxDetectedRotation = 0.0;

  while (millis() - windowStart < CAPTURE_WINDOW_MS) {

    // --- CHECK FOR INTERRUPTS ---
    if (checkForCommand()) {
       // If true, it means we need to abort this loop immediately.
       if (Serial) Serial.println("\n[INFO] Measurement Aborted by Command.");
       return false; // ABORT
    }

    particleSensor.check(); // Poll the sensor

    // -- Sub-Task: Motion QC Check (Every 200ms) --
    if (millis() - lastMotionCheck > 200) {
       sensors_event_t a, g, temp;
       mpu.getEvent(&a, &g, &temp);

       // Check magnitude of rotation (X, Y, or Z axis)
       // If the wrist twists, blood flow changes, ruining RMSSD.
       float currentRotation = abs(g.gyro.x) + abs(g.gyro.y) + abs(g.gyro.z);

       if (currentRotation > maxDetectedRotation) maxDetectedRotation = currentRotation;
       
       if (currentRotation > MOTION_THRESHOLD) {
          motionArtifactDetected = true;
          if (Serial) Serial.print(F("M")); // Print "M" if user moved
       }

       // B. VISUAL FEEDBACK: Print a dot '.' every second
       if (millis() - lastDotTime > 1000) {
           if (Serial) Serial.print(F("."));
           lastDotTime = millis();
       }
       lastMotionCheck = millis();
    }

    // -- Sub-Task: SpO2, Respiration, & Beat Collection --
    while (particleSensor.available()) {
      redValue = particleSensor.getFIFORed(); // Capture Red
      irValue = particleSensor.getFIFOIR();   // Capture IR
      particleSensor.nextSample(); // Advance FIFO
      sampleCounter++;

      // SPO2 Downsampling (Every 16th sample)
      if (sampleCounter % 16 == 0 && bufferIndex < SPO2_WINDOW_SIZE) {
        redBuffer[bufferIndex] = redValue;
        irBuffer[bufferIndex] = irValue;
        bufferIndex++;
      }

      // Respiration Downsampling (Every 50th sample)
      if (sampleCounter % 50 == 0 && rrBufferIndex < RR_WINDOW_SIZE) {
         rrBuffer[rrBufferIndex] = irValue; // IR is better for baseline wander
         rrBufferIndex++;
       }

      // High-Speed Beat Detect for RMSSD
      if (irValue > irThreshold && checkForBeat(irValue)) {
        long t = millis();
        long delta = t - lastBeatTime;
        lastBeatTime = t;

        // Filter noise: 20 BPM (3000ms) to 255 BPM (235ms)
        if (delta > 235 && delta < 3000 && beatCount < MAX_BEATS) {
          beatTimes[beatCount++] = t;
        }
      }
    }
    delay(0); // Critical: Yield to keep Watchdog happy
  }

  //  -- Sub-Task: Read Temparature (Manual I2C Read) --
  //  We read after the loop to avoid I2C Conflict
  Wire.beginTransmission(MAX30205_ADDRESS);
  Wire.write(0x00); // Temp Register
  if (Wire.endTransmission() == 0) {
    Wire.requestFrom(MAX30205_ADDRESS, 2);
    if (Wire.available() >= 2) {
      uint8_t msb = Wire.read();
      uint8_t lsb = Wire.read();
      int16_t rawValue = (msb << 8) | lsb; // Combine bytes: 16-bit integer
      skinTemperature = rawValue * 0.00390625; // Conversion factor for MAX30205 is 0.00390625°C per LSB
    }
  }

  return true; // Finished full 20s successfully
}

// ================= MODULE 5: SENSORS SHUTDOWN =================
void stopSensors() {
  // CRITICAL: Kill the sensors NOW to save battery during math/radio tasks
  
  particleSensor.shutDown(); // 1. MAX30102 Shutdown
  mpu.enableSleep(true); // 2. MPU6050 Shutdown

  // 3. Manual MAX30205 Shutdown (OS Bit)
  Wire.beginTransmission(MAX30205_ADDRESS);
  Wire.write(0x01);
  Wire.write(0x01); // OS bit (One-shot / Shutdown)
  Wire.endTransmission();

}

// ================= MODULE 6b: RESPIRATION ALGORITHM =================
float getRespirationRate(uint32_t *data, int count) {
  
  if (count < 80) return 0.0; // We need at least 10 seconds of data (80 samples) to detect anything useful
  
  // 1. Smooth the Data (Standard Moving Average)
  float smoothed[count]; 
  int window = 8; 
  float globalMax = 0;
  float globalMin = 999999.0;

  for (int i = 0; i < count; i++) {
    float sum = 0;
    int items = 0;
    for (int j = i - window/2; j <= i + window/2; j++) {
      if (j >= 0 && j < count) {
        sum += (float)data[j]; // Raw values
        items++;
      }
    }
    smoothed[i] = sum / items;
    
    // Track Global Min/Max for Threshold Sizing
    if (smoothed[i] > globalMax) globalMax = smoothed[i];
    if (smoothed[i] < globalMin) globalMin = smoothed[i];
  }

  // 3. Adaptive Threshold Calculation
  float signalRange = globalMax - globalMin;
  if (signalRange < RR_MIN_SIGNAL_RANGE) return 0.0; // ~5.0 for fingers, ~50.0 for wrist
  float threshold = signalRange * RR_PEAK_THRESHOLD_RATIO; // 10% for finger. 25% for wrist

  // 3. Peak-Valley State Machine
  int breathCount = 0;
  bool lookingForPeak = true; // Start by looking for a rise (Inhale)
  float localMin = smoothed[0];
  float localMax = smoothed[0];

  for (int i = 1; i < count; i++) {
    float val = smoothed[i];

    if (lookingForPeak) {
      // Logic: We are in a valley, looking for a rise
      if (val < localMin) localMin = val; // Found a deeper valley, update anchor

      if (val > localMin + threshold) {
        // We rose significantly! Count it.
        breathCount++;
        lookingForPeak = false; // Now switch to looking for the exhale (fall)
        localMax = val; // Reset the peak anchor
      }
    } 
    else {
      // Logic: We are at a peak, looking for a fall
      if (val > localMax) localMax = val; // Found a higher peak, update anchor

      if (val < localMax - threshold) {
        // We fell significantly! 
        lookingForPeak = true; // Ready for next breath
        localMin = val; // Reset the valley anchor
      }
    }
  }

  // 5. CALCULATE RR
  // Formula: (Breaths / Seconds) * 60
  float durationSeconds = (float)count / 8.0; // 8Hz sampling rate
  float rr = (breathCount / durationSeconds) * 60.0;

  // Clamp limits (3 BPM to 60 BPM)
  if (rr < RR_MIN_BPM || rr > RR_MAX_BPM) return 0.0; // 3 to include slow breaths, capping at 60 BPM (Hyperventilation)

  return rr;
}

// ================= MODULE 6: ANALYSIS =================

void processBiometrics() {
  // 1. RMSSD (Stress) Calculation
  double sumSquaredDiffs = 0;
  int validDiffCount = 0;
  for (int i = 0; i < beatCount - 1; i++) {
    long diff = (beatTimes[i+1] - beatTimes[i]) - (beatTimes[i+2] - beatTimes[i+1]);
    if (i + 1 < beatCount - 1) {
       sumSquaredDiffs += (diff * diff);
       validDiffCount++;
    }
  }
  double rmssd = (validDiffCount > 0) ? sqrt(sumSquaredDiffs / validDiffCount) : 0;
  outgoingData.rmssd = (float)rmssd;

  // 2. Heart Rate Calculation
  float avgBPM = 0;
  if (beatCount >= 2) {
    long totalTime = beatTimes[beatCount-1] - beatTimes[0];
    avgBPM = (float)(beatCount - 1) / (totalTime / 60000.0);
  }
  outgoingData.heartRate = avgBPM;

  // 3. SpO2 Algorithm
  maxim_heart_rate_and_oxygen_saturation(irBuffer, SPO2_WINDOW_SIZE, redBuffer, &algo_spo2, &validSPO2, &algo_hr, &validHeartRate);
  
  if (validSPO2 == 1 && algo_spo2 > 50 && algo_spo2 <= 100) {
    outgoingData.spo2 = algo_spo2;
  } else {
    outgoingData.spo2 = 0;
  }

  outgoingData.respiration = getRespirationRate(rrBuffer, rrBufferIndex); // 4. Respiration Algorithm
  outgoingData.temperature = skinTemperature + 5.0; // 5. Add 5.0 degrees to convert Skin Temp to Approx Body Temp
 
  outgoingData.packetId = totalPacketsSent;
  outgoingData.motionArtifact = motionArtifactDetected; 
  
}

// ================= MODULE 7: TRANSMISSION =================
void transmitData() {
  if (Serial) {
    Serial.println("\n\n[TASK] Sending Data");
    Serial.printf("ID: %d | HR: %.1f | SpO2: %d | RR: %.1f | Temp: %.2f | RMSSD: %.2f | Mot: %d\n", 
      outgoingData.packetId,
      outgoingData.heartRate,
      outgoingData.spo2,
      outgoingData.respiration,
      outgoingData.temperature,
      outgoingData.rmssd,
      outgoingData.motionArtifact);
  }

  esp_err_t result = esp_now_send(receiverAddress, (uint8_t *) &outgoingData, sizeof(outgoingData));
  
  if (result == ESP_OK) {
    totalPacketsSent++;
    digitalWrite(LED_PIN, LOW); delay(50); digitalWrite(LED_PIN, HIGH); // BLINK SUCCESS (Short Flash)

  } else {
    if(Serial) Serial.println("\n[ERR] Send Function Failed");
    digitalWrite(LED_PIN, LOW); delay(200); digitalWrite(LED_PIN, HIGH); // BLINK FAIL (Long Flash)
  }

  delay(200); // Wait for ACK callback before sleep
}

// ================= MODULE 8: DEEP SLEEP =================
void enterDeepSleep() {
  if (Serial) {
    Serial.println("\n[PWR] Entering Deep Sleep...");
    Serial.flush(); // Ensure logs finish printing
  }
  
  esp_sleep_enable_timer_wakeup(SLEEP_DURATION_SEC * 1000000ULL); // Schedule Wakeup
  esp_deep_sleep_start(); // Sleep
}