<?php
// a backed enum case's value may read the enum's own constants
interface HasCodes {
    const BASE = 'b';
}
enum Code: string implements HasCodes {
    const PREFIX = 'x-';
    case A = self::PREFIX . 'a';
    case B = self::BASE;
    case C = HasCodes::BASE . 'c';
    case D = Code::PREFIX . 'd';
}
var_dump(Code::A->value, Code::B->value, Code::C, Code::D->value);
var_dump(Code::from('x-a'), Code::tryFrom('b'), count(Code::cases()));

enum Level: int {
    const STEP = 10;
    case Low = self::STEP;
    case High = self::STEP * 2;
    const TOP = self::High;
}
var_dump(Level::cases(), Level::TOP->value, Level::tryFrom(20));
var_dump(array_map(fn($c) => $c->value, Level::cases()));

enum Wrong: string {
    const N = 5;
    case X = self::N;
}
try {
    var_dump(Wrong::X);
} catch (TypeError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
enum Twice: int {
    const ONE = 1;
    case P = self::ONE;
    case Q = 1;
}
try {
    var_dump(Twice::from(1));
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

// a global constant in a case value is read when the cases are first used
enum Late: string {
    case A = LATE_VALUE;
}
define('LATE_VALUE', 'late');
var_dump(Late::A->value, Late::from('late'));
enum Missing: int {
    case X = NOT_DEFINED_ANYWHERE;
}
try {
    var_dump(Missing::X);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    var_dump((new ReflectionEnumBackedCase(Missing::class, 'X'))->getBackingValue());
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
