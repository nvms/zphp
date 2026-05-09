<?php
// array_diff_key vs array_diff_assoc
print_r(array_diff_key(["a"=>1,"b"=>2,"c"=>3], ["b"=>9,"d"=>4]));
print_r(array_diff_assoc(["a"=>1,"b"=>2,"c"=>3], ["a"=>1,"b"=>9]));
print_r(array_diff_assoc([0=>"a", 1=>"b", 2=>"c"], [0=>"a", 1=>"b"]));

// array_intersect_key
print_r(array_intersect_key(["a"=>1,"b"=>2,"c"=>3], ["b"=>9,"c"=>0]));
print_r(array_intersect_key(["a"=>1], ["b"=>1])); // empty

// array_merge vs +
print_r(array_merge([1,2,3], [4,5,6])); // 0..5 renumbered
print_r([1,2,3] + [4,5,6,7]); // 0..3 - only 7 added
print_r(array_merge(["a"=>1], ["a"=>2, "b"=>3])); // a=2 (later wins)
print_r(["a"=>1] + ["a"=>2, "b"=>3]); // a=1 (first wins)

// list() too few - skipped, PHP emits Undefined-array-key warning that zphp can't replicate

// foreach by reference
$arr = [1, 2, 3];
foreach ($arr as &$v) $v *= 10;
unset($v);
print_r($arr);

// foreach modifying $arr inside
$arr = [1, 2, 3];
foreach ($arr as $k => $v) {
    $arr[$k] = $v + 100;
}
print_r($arr);

// foreach: PHP foreach over copy of original
$arr = [1, 2, 3];
foreach ($arr as $k => $v) {
    $arr[] = 999;
    if ($k > 5) break;
}
print_r($arr);

// usleep return type
$r = usleep(1);
var_dump($r); // null
$r = sleep(0);
var_dump($r); // 0

// microtime
$t = microtime(true);
echo gettype($t), ":", $t > 0 ? "pos" : "neg", "\n";

$s = microtime();
echo gettype($s), ":", count(explode(' ', $s)), "\n"; // string with two parts

// hrtime
$h = hrtime(true);
echo gettype($h), ":", $h > 0 ? "pos" : "neg", "\n";
$h2 = hrtime();
echo gettype($h2), ":", count($h2), "\n"; // array

// date format
$ts = mktime(14, 30, 0, 6, 15, 2024);
echo date("Y-m-d H:i:s", $ts), "\n";
echo date("y-m-d", $ts), "\n"; // 2-digit year
echo date("L", mktime(0, 0, 0, 1, 1, 2024)), "\n"; // 1 (leap)
echo date("L", mktime(0, 0, 0, 1, 1, 2023)), "\n"; // 0
echo date("L", mktime(0, 0, 0, 1, 1, 2000)), "\n"; // 1
echo date("L", mktime(0, 0, 0, 1, 1, 1900)), "\n"; // 0

// checkdate
var_dump(checkdate(2, 29, 2024));
var_dump(checkdate(2, 29, 2023));
var_dump(checkdate(13, 1, 2024)); // bad month
var_dump(checkdate(0, 1, 2024)); // bad month
var_dump(checkdate(1, 32, 2024)); // bad day
var_dump(checkdate(4, 31, 2024)); // April has 30 days

// mktime various args
echo mktime(0, 0, 0, 1, 1, 1970), "\n"; // unix epoch
echo mktime(1, 2, 3, 6, 15, 2024), "\n";

// getdate
$d = getdate(mktime(14, 30, 45, 6, 15, 2024));
echo $d['year'], "-", $d['mon'], "-", $d['mday'], " ", $d['hours'], ":", $d['minutes'], ":", $d['seconds'], "\n";
echo $d['weekday'], ",", $d['month'], "\n";

// date_diff between
$a = new DateTime("2020-01-15");
$b = new DateTime("2024-06-30");
$d = $a->diff($b);
echo $d->y, "y ", $d->m, "m ", $d->d, "d ", $d->days, " total\n";

// strtotime variations
echo date("Y-m-d", strtotime("2024-06-15")), "\n";
echo date("Y-m-d", strtotime("2024-06-15 +5 days")), "\n";
echo date("Y-m-d", strtotime("first day of next month", mktime(0,0,0,6,15,2024))), "\n";
echo date("Y-m-d", strtotime("now", mktime(0,0,0,6,15,2024))), "\n";

// DateTimeImmutable
$d = new DateTimeImmutable("2024-06-15");
$e = $d->add(new DateInterval("P1M"));
echo $d->format("Y-m-d"), "|", $e->format("Y-m-d"), "\n"; // d unchanged

// DateTime::createFromFormat
$d = DateTime::createFromFormat("d/m/Y", "15/06/2024");
echo $d->format("Y-m-d"), "\n";

// invalid format → false
$d = DateTime::createFromFormat("Y", "abc");
var_dump($d);

// DateInterval::format
$i = new DateInterval("P2Y3M5DT4H");
echo $i->format("%Y-%M-%D %H:%I"), "\n";
echo $i->format("%y year %m month %d day"), "\n";

// DateTime modify
$d = new DateTime("2024-06-15");
$d->modify("+1 day");
echo $d->format("Y-m-d"), "\n";
$d->modify("first day of next month");
echo $d->format("Y-m-d"), "\n";
$d->modify("-1 second");
echo $d->format("Y-m-d H:i:s"), "\n";

// DateTime::format escapes
$d = new DateTime("2024-06-15");
echo $d->format("\Y\e\a\\r: Y"), "\n"; // Year: 2024
