void setup() {
   size(screenWidth, screenHeight);
   background(255);
}

void touchStart(TouchEvent touchEvent) {
   drawTouches(touchEvent);
}

void touchMove(TouchEvent touchEvent) {
   drawTouches(touchEvent);
}

void touchEnd(TouchEvent touchEvent) {
   drawTouches(touchEvent);
}

void touchCancel(TouchEvent touchEvent) {
   drawTouches(touchEvent);
}

void drawTouches(TouchEvent touchEvent) {
   // touches contains only fingers that are still on the screen.
   // Always clear the canvas, including when the last finger lifts.
   background(255);
   noStroke();
   fill(180, 180, 100);
   for (int i = 0; i < touchEvent.touches.length; i++) {
      int x = touchEvent.touches[i].offsetX;
      int y = touchEvent.touches[i].offsetY;
      ellipse(x, y, 150, 150);
   }
}
