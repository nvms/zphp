<?php
// self::, parent:: and static:: where no class scope is active are php's
// "Cannot access" Error; a class that doesn't exist is "not found" before
// the method name is even looked at
$checks = [
    fn () => static::x,
    fn () => parent::x,
    fn () => self::x,
    fn () => new static,
    fn () => static::x(),
    fn () => static::$i,
    fn () => self::{"foo" . "bar"}(),
    fn () => Missing::{"foo" . "bar"}(),
    fn () => Missing::run(),
];
foreach ($checks as $check) {
    try {
        $check();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
