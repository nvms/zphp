<?php
// regression: a function/constructor parameter default that is a *compound*
// constant expression (`CONST | CONST`, `CONST + N`, `CONST . "x"`, `-CONST`)
// folded to null - evalConstExpr could only fold when both operands were
// already concrete ints. such defaults are now deferred and evaluated at the
// call site.

define('BASE', 10);
const PREFIX = 'app_';

class Flags {
    const READ = 1;
    const WRITE = 2;
    const EXEC = 4;
}

// bitwise-OR of class constants - the canonical flags pattern
function withFlags($f = Flags::READ | Flags::WRITE | Flags::EXEC) { return $f; }
echo withFlags(), "\n";          // 7
echo withFlags(2), "\n";         // 2

// arithmetic on a global constant
function plus($x = BASE + 5) { return $x; }
function minus($x = BASE - 3) { return $x; }
function times($x = BASE * 4) { return $x; }
function neg($x = -BASE) { return $x; }
function shift($x = BASE << 2) { return $x; }
echo plus(), " ", minus(), " ", times(), " ", neg(), " ", shift(), "\n";

// string concat involving a constant
function label($s = PREFIX . 'name') { return $s; }
function chain($s = PREFIX . 'v' . BASE) { return $s; }
echo label(), " ", chain(), "\n";

// concat with an escaped single-quoted literal
function ns($s = PREFIX . '\\Sub') { return $s; }
echo ns(), "\n";                 // app_\Sub

// constructor-promoted parameter with a compound default (the Symfony pattern)
class Extractor {
    const ALLOW_GET = 1 << 0;
    const ALLOW_SET = 1 << 1;
    const ALLOW_CALL = 1 << 2;
    public function __construct(
        private int $flags = self::ALLOW_GET | self::ALLOW_SET,
    ) {}
    public function flags(): int { return $this->flags; }
}
echo (new Extractor)->flags(), "\n";       // 3
echo (new Extractor(7))->flags(), "\n";    // 7
echo (new Extractor(0))->flags(), "\n";    // 0

// class constant whose value is a compound expression of another constant
class Limits {
    const A = 100;
    const B = self::A * 3;
    const C = self::A | 0xF;
}
echo Limits::B, " ", Limits::C, "\n";      // 300 111

// method default referencing a self constant in a compound expression
class Service {
    const TIMEOUT = 30;
    public function run($t = self::TIMEOUT + 1) { return $t; }
}
echo (new Service)->run(), " ", (new Service)->run(5), "\n";

// nested compound default
function nested($x = (Flags::READ | Flags::WRITE) + BASE) { return $x; }
echo nested(), "\n";             // 13

// compound expression inside an array default
function arr($a = [Flags::READ | Flags::EXEC, BASE * 2]) { return implode(',', $a); }
echo arr(), "\n";                // 5,20

// a default that is purely concrete float arithmetic
function fl($x = 1.5 + 2) { return $x; }
echo fl(), "\n";                 // 3.5
