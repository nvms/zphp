<?php
// date objects check their arguments and their own initialization the way
// php_date.c does: DateObjectError for a subclass that skipped the parent
// constructor, TypeErrors from argument parsing, and the procedural aliases

class MyDateTime extends DateTime { function __construct() {} }
class MyImmutable extends DateTimeImmutable { function __construct() {} }
class MyZone extends DateTimeZone { function __construct() {} }
class MyInterval extends DateInterval { function __construct() {} }

function check(callable $c) {
    try {
        $r = $c();
        echo is_object($r) ? get_class($r) . " " . ($r instanceof DateTimeInterface ? $r->format("Y-m-d H:i:s.u e") : "") : var_export($r, true), "\n";
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$mdt = new MyDateTime();
$mdi = new MyImmutable();
$mtz = new MyZone();
$miv = new MyInterval();
$dt = new DateTime("2021-03-04 05:06:07.891011", new DateTimeZone("Europe/Paris"));
$di = new DateTimeImmutable("2021-03-04 05:06:07", new DateTimeZone("America/New_York"));
$iv = new DateInterval("P1DT2H");
$tz = new DateTimeZone("Asia/Tokyo");

foreach ([
    fn() => $mdt->format("Y"), fn() => date_format($mdt, "Y"), fn() => $mdt->modify("+1 day"),
    fn() => date_modify($mdt, "+1 day"), fn() => $mdt->add($iv), fn() => $mdt->sub($iv),
    fn() => $mdt->getTimezone(), fn() => date_timezone_get($mdt), fn() => $mdt->setTimezone($tz),
    fn() => $mdt->getOffset(), fn() => date_offset_get($mdt), fn() => $mdt->setTime(1, 2),
    fn() => $mdt->setDate(2020, 1, 1), fn() => $mdt->setISODate(2020, 1), fn() => $mdt->setTimestamp(0),
    fn() => $mdt->getTimestamp(), fn() => date_timestamp_get($mdt), fn() => $mdt->getMicrosecond(),
    fn() => $mdt->diff($dt), fn() => $dt->diff($mdt), fn() => date_diff($dt, $mdt),
    fn() => serialize($mdt), fn() => DateTime::createFromInterface($mdt), fn() => DateTimeImmutable::createFromMutable($mdt),
    fn() => $mdi->modify("+1 day"), fn() => $mdi->add($iv), fn() => $mdi->setTimestamp(0), fn() => $mdi->format("Y"),
    fn() => DateTime::createFromImmutable($mdi), fn() => $mtz->getName(), fn() => $mtz->getOffset($dt),
    fn() => $tz->getOffset($mdt), fn() => timezone_name_get($mtz), fn() => $mtz->getLocation(),
    fn() => $mtz->getTransitions(), fn() => serialize($mtz), fn() => $dt->add($miv), fn() => $dt->sub($miv),
    fn() => new DateTime("now", $mtz), fn() => $mdt == $dt, fn() => $mtz == $tz,
    fn() => $dt < $mdt,
] as $c) check($c);

// argument parsing
foreach ([
    fn() => date_add($di, $iv), fn() => date_sub($di, $iv), fn() => date_modify($di, "+1 day"),
    fn() => date_timestamp_set($di, 0), fn() => date_date_set($di, 2020, 1, 1), fn() => date_time_set($di, 1, 2),
    fn() => date_isodate_set($di, 2020, 1), fn() => date_timezone_set($di, $tz), fn() => timezone_offset_get($dt, $dt),
    fn() => timezone_offset_get(new stdClass, $dt), fn() => $tz->getOffset(5), fn() => $dt->setTime("a", 1),
    fn() => $dt->setDate(2020, 1.5, 1), fn() => $dt->setTimestamp("12"), fn() => $dt->add("P1D"),
    fn() => DateTime::createFromImmutable($dt), fn() => DateTimeImmutable::createFromMutable($di),
    fn() => strtotime("now", $dt), fn() => date("Y", "x"), fn() => mktime("x"), fn() => new DateTime([]),
    fn() => new DateTime("now", "UTC"), fn() => date_create("bogus string"), fn() => new DateTimeZone([]),
    fn() => DateTime::createFromFormat("Y", "2020\0"), fn() => DateTime::__set_state(5),
] as $c) check($c);

// what the aliases and the immutable methods give back
check(fn() => date_add(clone $dt, $iv));
check(fn() => date_sub(clone $dt, DateInterval::createFromDateString("next weekday")));
check(fn() => date_modify(clone $dt, "+1 bogus"));
check(fn() => $di->setTime(25, 61, 61, 1000001));
check(fn() => $di->setDate(2021, 2, 31));
check(fn() => $di->setISODate(2021, 53, 7));
check(fn() => $di->setTimestamp(86400 * 365));
check(fn() => $di->setMicrosecond(999999));
check(fn() => $di->setMicrosecond(1000000));
check(fn() => $dt->setMicrosecond(-1));
check(fn() => $di->setTimezone($tz));
check(fn() => date_timezone_set(clone $dt, new DateTimeZone("-03:30")));
check(fn() => $di->sub(DateInterval::createFromDateString("last day of next month")));

class Child extends DateTime {}
class ChildImmutable extends DateTimeImmutable {}
check(fn() => Child::createFromInterface($di));
check(fn() => ChildImmutable::createFromMutable($dt));
check(fn() => Child::createFromImmutable($di));
check(fn() => ChildImmutable::createFromInterface($dt));
check(fn() => Child::createFromFormat("Y-m-d|", "2020-02-03"));
check(fn() => DateTime::createFromTimestamp(1234567890));
check(fn() => DateTimeImmutable::createFromTimestamp(1234567890.25));
check(fn() => DateTimeImmutable::createFromTimestamp(-1.5));
check(fn() => ChildImmutable::createFromTimestamp("17"));
check(fn() => DateTime::createFromTimestamp(1e30));
check(fn() => DateTime::createFromTimestamp(NAN));
var_dump(serialize(DateTime::createFromTimestamp(0)));

// comparisons
var_dump($dt == clone $dt, $dt < $di, $dt > $di, $dt == new DateTimeImmutable("@" . $dt->getTimestamp()));
var_dump(new DateTimeZone("Europe/Paris") == new DateTimeZone("Europe/Paris"), new DateTimeZone("+01:00") == new DateTimeZone("+0100"));
check(fn() => new DateTimeZone("+01:00") == new DateTimeZone("Europe/Paris"));
check(fn() => new DateTimeZone("EST") < new DateTimeZone("EST"));
var_dump(new DateTimeZone("+02:00") > new DateTimeZone("-02:00"), new DateTimeZone("+02:00") < new DateTimeZone("-02:00"));
var_dump($iv == new DateInterval("P1DT2H"), $iv < $iv);
