// A mirrored selfie preview, using ordinary sketch transforms.
let camera;

function setup() {
  createCanvas(windowWidth, windowHeight);
  camera = new CameraView("front");
}

function draw() {
  background(18, 24, 34);
  fill(255);
  noStroke();
  textSize(24);
  text("Camera input", 20, 40);
  // Flip only the camera image; keep the title readable.
  push();
  translate(width, 0);
  scale(-1, 1);
  camera.draw(20, 80, width - 40, height - 100);
  pop();
}
