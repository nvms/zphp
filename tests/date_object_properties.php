<?php
// date objects show date, timezone_type and timezone for every output purpose,
// and serialize, unserialize and __set_state round-trip them as php does
$tzs = ['UTC', 'Europe/Paris', '+05:30', 'EST', 'America/New_York'];
foreach ($tzs as $tz) {
    $d = new DateTime('2021-03-04 05:06:07.123456', new DateTimeZone($tz));
    print_r($d); echo "\n";
    var_export($d); echo "\n";
    echo json_encode($d), "\n";
    print_r((array)$d);
    print_r(get_object_vars($d));
    $s = serialize($d); echo $s, "\n";
    $u = unserialize($s); echo $u->format(DATE_RFC3339_EXTENDED), ' ', $u->getTimezone()->getName(), "\n";
    $z = new DateTimeZone($tz);
    print_r($z); echo serialize($z), "\n"; var_export($z); echo "\n";
    echo unserialize(serialize($z))->getName(), "\n";
}
$i = new DateTimeImmutable('2000-01-01 00:00:00', new DateTimeZone('UTC'));
echo serialize($i), "\n";
var_dump(DateTime::__set_state(['date' => '2020-02-02 10:00:00.000000', 'timezone_type' => 3, 'timezone' => 'Asia/Tokyo'])->format('c'));
var_dump(DateTimeImmutable::__set_state(['date' => '2020-02-02 10:00:00.000000', 'timezone_type' => 1, 'timezone' => '-03:00'])->format('c'));
try { DateTime::__set_state(['date' => 'x']); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
try { unserialize('O:8:"DateTime":0:{}'); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
class MyDate extends DateTime { public $extra = 'e'; private $secret = 's'; }
$m = new MyDate('2010-10-10 10:10:10', new DateTimeZone('UTC'));
echo serialize($m), "\n"; print_r($m); print_r(unserialize(serialize($m)));
print_r(new DateTimeZone('Europe/London'));
