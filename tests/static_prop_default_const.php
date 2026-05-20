<?php
// regression: a static property default that references a class constant
// (self::CONST, parent::CONST, ClassName::CONST, a global const, an enum
// case value) now resolves. previously the static-property default was
// compiled as bytecode that ran BEFORE the class_decl opcode registered the
// class, so 'self::CONST' evaluated against a not-yet-existing class and
// folded to empty/null. static-prop defaults are now emitted after class_decl
// (and after the constants block), mirroring how class constants are handled.
class Config {
    const START = 10;
    const LABEL = 'cfg';
    public static int $count = self::START;
    public static int $doubled = self::START;  // runtime ops on it below
    public static string $name = self::LABEL;
    public static array $pair = [self::START, self::LABEL];
    public static int $plain = 5;
}
echo Config::$count, "\n";
echo Config::$name, "\n";
print_r(Config::$pair);
echo Config::$plain, "\n";

// parent:: in a static prop default
class Base { const V = 100; }
class Derived extends Base {
    public static int $fromParent = parent::V;
    public static int $fromSelf = self::V;  // inherited constant
}
echo Derived::$fromParent, " ", Derived::$fromSelf, "\n";

// cross-class constant
class Other { const N = 7; }
class Consumer {
    public static int $borrowed = Other::N;
}
echo Consumer::$borrowed, "\n";

// global constant + enum case
const APP_LIMIT = 250;
enum Size: int { case Large = 3; }
class Limits {
    public static int $max = APP_LIMIT;
    public static int $size = Size::Large->value;
}
echo Limits::$max, " ", Limits::$size, "\n";

// static prop stays mutable after the const-derived default
Config::$count = 99;
echo Config::$count, "\n";
