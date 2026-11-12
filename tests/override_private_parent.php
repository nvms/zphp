<?php
// a parent's private method is no method to override, and the error is a
// compile-time fatal at the method's line
class Base {
    private function secret(): void {}
}
class Child extends Base {
    #[\Override]
    public function secret(): void {}
}
echo "never runs\n";
