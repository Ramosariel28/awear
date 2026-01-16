/*
 * Project: ESP32-C3 Wireless Biometric Receiver (Dongle)
 * Role: ESP-NOW Gateway -> Serial JSON
 * Board: ESP32-C3 SuperMini
 * Input: Binary Struct (Air)
 * Output: JSON String (Serial)
 * Dependency: ArduinoJson by Benoit Blanchon
 */

#include <esp_now.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <ArduinoJson.h>

// ================= CONFIGURATION =================
#define LED_PIN 8         // SuperMini Blue LED (Active LOW)
#define WIFI_CHANNEL 1    // MUST match Sender

// ================= DATA STRUCTURE =================
// STRICT MATCH: This must be identical to the Sender's struct
typedef struct __attribute__((packed)) struct_message {
  uint32_t packetId;     
  float heartRate;       
  int32_t spo2;
  float respiration;          
  float temperature;     
  float rmssd;           
  bool motionArtifact;   
} struct_message;

struct_message incomingData;

// ================= CALLBACK =================
void OnDataRecv(const esp_now_recv_info_t * info, const uint8_t *data, int len) {
  
  // 1. Validate Packet Size
  if (len != sizeof(incomingData)) {
    // If packet size is wrong, ignore it (don't print garbage to Serial)
    return;
  }

  // 2. Unpack Binary Data
  memcpy(&incomingData, data, sizeof(incomingData));

  // 3. Visual Feedback (Flash LED)
  digitalWrite(LED_PIN, LOW);  // ON
  delay(5); 
  digitalWrite(LED_PIN, HIGH); // OFF

  // 4. Extract Sender's MAC address
  // info->src_addr is a 6-byte array. We format it into a string "XX:XX:XX..."
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X",
           info->src_addr[0], info->src_addr[1], info->src_addr[2], 
           info->src_addr[3], info->src_addr[4], info->src_addr[5]);
  
  // 5. Serialize to JSON
  JsonDocument doc;

  // -- Identity --
  doc["sender"] = macStr;             // e.g. "08:92:72:85:83:78"
  doc["rssi"] = info->rx_ctrl->rssi;  // Signal strength

  // -- Payload Data --
  doc["id"] = incomingData.packetId;
  doc["hr"] = incomingData.heartRate;
  doc["oxy"] = incomingData.spo2;
  doc["rr"] = incomingData.respiration;
  doc["temp"] = incomingData.temperature;
  doc["stress"] = incomingData.rmssd;
  doc["motion"] = incomingData.motionArtifact; // true/false

  // 5. Print to Serial
  // "serializeJson" prints minimal string: {"id":1,"hr":72.5...}
  // "println" adds the newline char '\n' which Flutter uses as a delimiter.
  serializeJson(doc, Serial);
  Serial.println(); 
}

// ================= SETUP =================
void setup() {
  // 1. Init Serial
  Serial.begin(921600);
  
  // Wait slightly for USB, but don't block forever
  unsigned long start = millis();
  while(!Serial && millis() - start < 2000);

  // 2. Init LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH); // OFF

  // 3. Wi-Fi Config (No Sleep Mode)
  WiFi.mode(WIFI_STA);
  esp_wifi_set_ps(WIFI_PS_NONE); // Critical: Don't sleep, or we miss packets
  esp_wifi_set_protocol(WIFI_IF_STA, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N | WIFI_PROTOCOL_LR); // Set Protocol to allow Long Range (optional, but helps sensitivity)
  esp_wifi_set_max_tx_power(84); // Force Max Safe Power (20dBm)

  // 4. Force Channel
  esp_wifi_set_promiscuous(true);
  esp_wifi_set_channel(WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE);
  esp_wifi_set_promiscuous(false);

  // 5. Init ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("{\"error\": \"ESP-NOW Init Failed\"}"); // JSON Error format
    return;
  }

  // 6. Register Callback
  esp_now_register_recv_cb(OnDataRecv);

  // Send "Boot" message once (in JSON format so App doesn't crash on boot)
  printStatus();

}

// ================= HELPER: PRINT STATUS =================
void printStatus() {

  JsonDocument doc;
  doc["status"] = "Receiver Ready";
  doc["device"] = "AWEAR_RECEIVER"; // <--- The Secret ID
  doc["channel"] = WIFI_CHANNEL;
  doc["mac"] = WiFi.macAddress();
  serializeJson(doc, Serial);
  Serial.println();
}

// ================= LOOP (THE NEW PART) =================
void loop() {
  // Instead of sleeping, we listen for commands from the Computer/Flutter App
  
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim(); // Remove whitespace/newlines

    // 1. HANDSHAKE COMMAND
    // If Flutter sends "AWEAR_IDENTIFY", we reply nicely
    if (cmd == "AWEAR_IDENTIFY") {
      printStatus();
      
      // Visual Confirm: Blink 2 times fast
      digitalWrite(LED_PIN, LOW); delay(50); digitalWrite(LED_PIN, HIGH); delay(50);
      digitalWrite(LED_PIN, LOW); delay(50); digitalWrite(LED_PIN, HIGH);
    }
  }
  
  // No delay() here! We want to be responsive.
  // The ESP32 OS handles idle time automatically.
}