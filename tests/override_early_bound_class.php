<?php
// a class php binds while compiling has its #[\Override] checked before
// anything runs, even when a class declared above it extends it
interface I { public function i(): void; }
class C extends P implements I {}
class P {
    #[\Override]
    public function i(): void {}
}
echo "not reached\n";
