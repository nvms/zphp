<?php
// abstract static methods keep their static flag, so making one non static
// in a subclass is php's fatal error
abstract class Factory { abstract public static function create(): static; }
echo "declaring\n";
if (true) {
    class Widget extends Factory { public function create(): static { return $this; } }
}
echo "not reached\n";
