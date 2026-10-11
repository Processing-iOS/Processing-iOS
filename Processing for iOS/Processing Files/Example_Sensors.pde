// Native iOS sensors. Define only the callbacks your sketch needs.
// Device axes: +X right, +Y toward the top, +Z out of the screen.
// Values stay in device coordinates when the interface rotates.
String[] names = { "Orientation (roll / pitch / yaw, rad)", "Gravity (g)",
  "Acceleration without gravity (g)", "Rotation rate (rad/s)",
  "Accelerometer including gravity (g)", "Raw gyroscope (rad/s)",
  "Magnetic field (microtesla)", "Relative altitude (m) / pressure (kPa)" };
String[] callbacks = { "orientationUpdated", "gravityUpdated", "userAccelerationUpdated",
  "rotationRateUpdated", "accelerometerUpdated", "gyroscopeUpdated",
  "magnetometerUpdated", "altimeterUpdated" };
String[] readings = new String[8];
String[] states = new String[8];
float roll = 0;

void setup() {
  size(screenWidth, screenHeight);
  for (int i = 0; i < 8; i++) {
    readings[i] = "";
    states[i] = "waiting";
  }
}

void draw() {
  background(18, 24, 34);
  fill(255);
  textSize(24);
  text("Device sensors", 20, 38);
  textSize(13);
  fill(160, 180, 200);
  text("Tilt or move your device to change the inputs.", 20, 63);

  pushMatrix();
  translate(width/2, 108);
  rotate(-roll);
  stroke(94, 220, 185);
  strokeWeight(3);
  line(-65, 0, 65, 0);
  noStroke();
  fill(94, 220, 185);
  ellipse(0, 0, 10, 10);
  popMatrix();

  float rowHeight = min(62, (height - 165) / 8.0);
  for (int i = 0; i < 8; i++) {
    float y = 158 + i * rowHeight;
    fill(160, 180, 200);
    textSize(12);
    text(names[i], 20, y);
    fill(255);
    textSize(15);
    text(states[i].equals("active") ? readings[i] : states[i], 20, y + 21);
  }
}

String vectorText(float x, float y, float z) {
  return nfs(x, 1, 2) + "   " + nfs(y, 1, 2) + "   " + nfs(z, 1, 2);
}

// Yaw is relative to the session's starting orientation, not compass north.
void orientationUpdated(float r, float p, float y) {
  roll = r;
  readings[0] = vectorText(r, p, y);
}
void gravityUpdated(float x, float y, float z) { readings[1] = vectorText(x, y, z); }
void userAccelerationUpdated(float x, float y, float z) { readings[2] = vectorText(x, y, z); }
void rotationRateUpdated(float x, float y, float z) { readings[3] = vectorText(x, y, z); }
void accelerometerUpdated(float x, float y, float z) { readings[4] = vectorText(x, y, z); }
void gyroscopeUpdated(float x, float y, float z) { readings[5] = vectorText(x, y, z); }
// Raw magnetic field includes nearby magnets; this is not a compass heading.
void magnetometerUpdated(float x, float y, float z) { readings[6] = vectorText(x, y, z); }
// Altitude starts at zero each time sensing starts; pressure is in kilopascals.
void altimeterUpdated(float altitude, float pressure) {
  readings[7] = nfs(altitude, 1, 2) + " m   /   " + nf(pressure, 1, 2) + " kPa";
}
// Missing hardware (including simulators) reports "unavailable" instead of zero.
void sensorStatusUpdated(String sensor, String status) {
  for (int i = 0; i < 8; i++) {
    if (callbacks[i].equals(sensor)) states[i] = status;
  }
}
