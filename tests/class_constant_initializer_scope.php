<?php
// a class's constant expressions are evaluated in the class's scope: they
// may read its private constants, not another class's, and an exception out
// of one leaves that scope
class Vault { private const CODE = 7; public const DOUBLE = self::CODE * 2; public static $copy = self::CODE; }
echo Vault::DOUBLE, ' ', Vault::$copy, "\n";
enum Level: int { case Low = 1; private const BASE = 10; public const TOP = self::BASE + 5; }
echo Level::TOP, "\n";
interface Limits { const MAX = 100; const HALF = self::MAX / 2; }
echo Limits::HALF, "\n";
function declare_thief() {
    try {
        eval('class Thief { public const STOLEN = Vault::CODE; }');
        echo Thief::STOLEN, "\n";
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try { echo Vault::CODE; } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
declare_thief();
