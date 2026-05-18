<?php
// regression: class_implements returns the calling class's direct interfaces
// in forward declaration order, and parent-only interfaces in REVERSE
// declaration order (a PHP quirk). only covers the cases that real-world
// vendor code relies on; PHP's exact ordering with mixed direct+parent
// interfaces is version-dependent and not covered here
interface I1 {}
interface I2 {}
interface I3 {}

// direct only: forward declaration order
class Direct implements I1, I2, I3 {}
print_r(class_implements(Direct::class));

// inherited only (no direct): reverse declaration order
class Parent_ implements I1, I2, I3 {}
class Child_ extends Parent_ {}
print_r(class_implements(Child_::class));
