<?php
// the static factories make the called class and refuse an abstract one;
// the procedural aliases always make the base class

abstract class MyDatePeriod extends DatePeriod {
    public abstract function foo();
}

abstract class MyDateTime extends DateTime {
    public abstract function foo();
}

abstract class MyDateTimeImmutable extends DateTimeImmutable {
    public abstract function foo();
}

foreach ([
    fn() => MyDatePeriod::createFromISO8601String('R5'),
    fn() => MyDateTime::createFromFormat('Y-m-d', '2025-01-01'),
    fn() => MyDateTime::createFromFormat('Y-m-d', 'bogus'),
    fn() => MyDateTime::createFromImmutable(new DateTimeImmutable()),
    fn() => MyDateTime::createFromInterface(new DateTimeImmutable()),
    fn() => MyDateTime::createFromTimestamp(0),
    fn() => MyDateTimeImmutable::createFromFormat('Y-m-d', '2025-01-01'),
    fn() => MyDateTimeImmutable::createFromMutable(new DateTime()),
    fn() => MyDateTimeImmutable::createFromInterface(new DateTime()),
    fn() => MyDateTimeImmutable::createFromTimestamp(0),
] as $f) {
    try {
        $f();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}

class Mine extends DateTime {
    public static function viaFunction() {
        return [get_class(date_create_from_format("Y-m-d", "2020-01-01")), get_class(date_create_immutable_from_format("Y-m-d", "2020-01-01")), get_class(static::createFromFormat("Y-m-d", "2020-01-01"))];
    }
}
var_dump(Mine::viaFunction());
var_dump(get_class(Mine::createFromTimestamp(5)), get_class(Mine::createFromInterface(new DateTime())));
