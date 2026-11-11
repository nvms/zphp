<?php
// DateInterval and DatePeriod as php_date.c builds, checks, serializes and
// iterates them

function check(callable $c) {
    try {
        $r = $c();
        if (is_object($r)) {
            echo get_class($r), " ", json_encode($r instanceof DateInterval ? [$r->y, $r->m, $r->d, $r->h, $r->i, $r->s, $r->f, $r->invert, $r->days] : null), "\n";
        } else {
            var_dump($r);
        }
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

foreach (["P1Y2M3DT4H5M6S", "PT36H", "P2W", "", "P", "2008-05-11T15:30:00Z/2007-03-01T13:00:00Z", "2007-05-11T15:30:00Z/", "R5/2008-03-01T13:00:00Z/P1Y2M10DT2H30M", "P1.5D", "blah"] as $spec) {
    check(fn() => new DateInterval($spec));
}
check(fn() => DateInterval::createFromDateString("next weekday"));
check(fn() => DateInterval::createFromDateString("2020-01-01"));
check(fn() => DateInterval::createFromDateString("bogus"));
check(fn() => date_interval_create_from_date_string("bogus"));
check(fn() => date_interval_create_from_date_string("1 week 2 days"));

$iv = new DateInterval("P1Y2M3DT4H5M6S");
foreach (["%Y-%M-%D %H:%I:%S %F %R%a %r|%y-%m-%d %h:%i:%s %f", "%%", "%", "%q %a %", "100%"] as $f) {
    var_dump($iv->format($f), date_interval_format($iv, $f));
}
$diff = (new DateTime("2020-01-01 00:00:00.25"))->diff(new DateTime("2021-03-04 05:06:07.5"));
var_dump($diff->format("%a %R %y %m %d %h %i %s %f %F"));

// restoring
print_r(DateInterval::__set_state(["y" => 1, "d" => "5", "days" => false, "invert" => 1])); echo "\n";
print_r(DateInterval::__set_state([])); echo "\n";
print_r(DateInterval::__set_state(["y" => [], "h" => 2.7, "f" => 0.5, "days" => "12"])); echo "\n";
check(fn() => DateInterval::__set_state(["date_string" => "2023-01-16-foobar"]));
print_r(unserialize(serialize(DateInterval::createFromDateString("last day of next month")))); echo "\n";
print_r(unserialize('O:12:"DateInterval":2:{s:1:"y";i:3;s:3:"foo";s:3:"bar";}')); echo "\n";

class MyInterval extends DateInterval { public $extra = 1; function __construct() {} }
$mi = new MyInterval();
print_r($mi); echo "\n";
check(fn() => $mi->format("%d"));
check(fn() => serialize($mi));
check(fn() => (new DateTime("2020-01-01"))->add($mi));

// periods
$start = new DateTimeImmutable("2020-01-31 10:00:00.5", new DateTimeZone("Europe/Paris"));
foreach ([
    fn() => new DatePeriod($start, new DateInterval("P1M"), 3),
    fn() => new DatePeriod($start, DateInterval::createFromDateString("last day of next month"), 3, DatePeriod::EXCLUDE_START_DATE),
    fn() => new DatePeriod($start, new DateInterval("P1D"), new DateTime("2020-02-03 10:00:00.5"), DatePeriod::INCLUDE_END_DATE),
    fn() => new DatePeriod($start, new DateInterval("P1D"), new DateTime("2020-02-03 10:00:00.4"), DatePeriod::INCLUDE_END_DATE),
    fn() => new DatePeriod($start, new DateInterval("PT12H"), "3"),
    fn() => @new DatePeriod("R2/2012-07-01T00:00:00Z/P7D"),
    fn() => DatePeriod::createFromISO8601String("R2/2012-07-01T00:00:00Z/P7D", DatePeriod::INCLUDE_END_DATE),
    fn() => DatePeriod::createFromISO8601String("2012-07-01T00:00:00Z/P7D/2012-07-20T00:00:00Z"),
] as $make) {
    try {
        $p = $make();
        echo get_class($p), " ", $p->getRecurrences() ?? "null", " ", $p->getStartDate()->format("c"), " ", $p->getEndDate()?->format("c") ?? "-", " ", get_class($p->getDateInterval()), "\n";
        foreach ($p as $k => $d) echo "  $k ", get_class($d), " ", $d->format("Y-m-d H:i:s.u T"), "\n";
        $it = $p->getIterator();
        echo "  ", get_class($it), " ", $it->key(), " ", $it->current()->format("Y-m-d"), "\n";
        $it->next();
        echo "  ", $it->valid() ? $it->current()->format("Y-m-d") : "done", "\n";
        $it->rewind();
        echo "  ", $it->key(), " ", $it->current()->format("Y-m-d"), "\n";
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

foreach ([
    fn() => new DatePeriod(),
    fn() => new DatePeriod(1, 2, 3),
    fn() => new DatePeriod($start, new DateInterval("P1D"), 0),
    fn() => new DatePeriod($start, new DateInterval("P1D"), 2147483639),
    fn() => new DatePeriod($start, new DateInterval("P1D"), 2147483638),
    fn() => @new DatePeriod("bogus"),
    fn() => @new DatePeriod("P1D"),
    fn() => DatePeriod::createFromISO8601String("R5"),
    fn() => DatePeriod::__set_state(["start" => null, "end" => new DateTime(), "current" => null, "interval" => new DateInterval("P1D"), "recurrences" => 2, "include_start_date" => false, "include_end_date" => true]),
    fn() => DatePeriod::__set_state([]),
] as $make) check($make);

$p = new DatePeriod($start, DateInterval::createFromDateString("+1 hour"), 1);
print_r($p); echo "\n";
$u = unserialize(serialize($p));
var_dump($u == $p, get_class($u->getDateInterval()));
foreach (["start", "current", "end", "interval", "recurrences", "include_start_date", "include_end_date"] as $f) {
    try { $p->$f = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    try { $r = &$p->$f; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    try { unset($p->$f); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}

class MyPeriod extends DatePeriod { public int $mine; function __construct() {} }
$mp = (new ReflectionClass("MyPeriod"))->newInstanceWithoutConstructor();
var_dump(isset($mp->start), empty($mp->recurrences), property_exists($mp, "end"), $mp->getRecurrences(), $mp->getEndDate());
check(fn() => $mp->getStartDate());
check(fn() => serialize($mp));
try {
    foreach (new MyPeriod() as $d) {}
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
