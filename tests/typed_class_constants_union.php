<?php
// a class constant's type may be any type php allows there: a union, a
// nullable or an intersection in a union, with several names in one statement
class Settings {
    const int|string ID = 1;
    const ?array DEFAULTS = null, OVERRIDES = null;
    const (Countable&Traversable)|null ITEMS = null;
    const static = 'keyword name';
}
var_dump(Settings::ID, Settings::OVERRIDES, Settings::static);
foreach (['ID', 'DEFAULTS', 'ITEMS'] as $c) echo $c, ': ', (new ReflectionClassConstant('Settings', $c))->getType(), "\n";
