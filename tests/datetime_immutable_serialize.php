<?php
date_default_timezone_set('UTC');

// DateTimeImmutable
$d = new DateTimeImmutable('2024-06-15 10:30:00');
echo $d->format('Y-m-d H:i:s'), "\n";
$d2 = $d->modify('+1 day');
echo $d->format('Y-m-d'), " | ", $d2->format('Y-m-d'), "\n"; // immutable: $d unchanged
$d3 = $d->add(new DateInterval('P1M'));
echo $d->format('Y-m-d'), " | ", $d3->format('Y-m-d'), "\n";
$d4 = $d->setDate(2030, 1, 1);
echo $d4->format('Y-m-d'), "\n";
$d5 = $d->setTime(23, 59, 59);
echo $d5->format('H:i:s'), "\n";
$d6 = $d->setTimezone(new DateTimeZone('America/New_York'));
echo $d6->format('Y-m-d H:i:s T'), "\n";

// DateInterval format
$i = new DateInterval('P1Y2M3DT4H5M6S');
echo $i->format('%y/%m/%d %h:%i:%s'), "\n";
echo $i->format('%Y/%M/%D %H:%I:%S'), "\n"; // zero-padded
echo $i->format('%R%y'), "\n";   // sign
$i2 = new DateInterval('P0Y0M5D');
echo $i2->format('%a days'), "\n"; // %a is total days, only valid for diffs
$d1 = new DateTime('2024-01-15');
$d2 = new DateTime('2024-03-10');
$diff = $d1->diff($d2);
echo $diff->format('%a days, %r%y years %m months %d days'), "\n";
echo $diff->format('%R%a'), "\n";

// DateTimeImmutable::createFromFormat
$d = DateTimeImmutable::createFromFormat('!Y-m-d', '2024-12-25');
echo $d->format('Y-m-d H:i:s'), "\n";

// DateTimeImmutable::createFromMutable
$mt = new DateTime('2024-01-01');
$im = DateTimeImmutable::createFromMutable($mt);
echo get_class($im), ":", $im->format('Y-m-d'), "\n";

// DateTime::createFromImmutable
$im = new DateTimeImmutable('2024-06-15');
$mt = DateTime::createFromImmutable($im);
echo get_class($mt), ":", $mt->format('Y-m-d'), "\n";

// json_encode flags
echo json_encode(['key' => '<tag>'], JSON_HEX_TAG), "\n";
echo json_encode(['amp' => 'a&b'], JSON_HEX_AMP), "\n";
echo json_encode(['quote' => "'"], JSON_HEX_APOS), "\n";
echo json_encode(['quote' => '"'], JSON_HEX_QUOT), "\n";
echo json_encode(['url' => 'a/b/c'], JSON_UNESCAPED_SLASHES), "\n";
echo json_encode(['utf' => 'café'], JSON_UNESCAPED_UNICODE), "\n";

// serialize/unserialize edge cases
$a = [1, "hello", 3.14, null, true, false, ["nested" => 1]];
$s = serialize($a);
echo $s, "\n";
print_r(unserialize($s));

// recursive arrays via reference - skipped: zphp's serialize doesn't yet
// detect self-references and would infinite-recurse

// object serialization
class Pt { public int $x; public int $y; public function __construct(int $x, int $y) { $this->x = $x; $this->y = $y; } }
$o = new Pt(3, 4);
$s = serialize($o);
echo $s, "\n";
$o2 = unserialize($s);
echo $o2->x, ",", $o2->y, "\n";

// ucwords with custom delim
echo ucwords("hello-world foo_bar"), "\n";
echo ucwords("hello-world foo_bar", " -_"), "\n";
echo ucwords("hello-world.foo bar", " -._"), "\n";

// ucfirst/lcfirst on multibyte (byte-based, may break)
echo ucfirst("éclair"), "\n";
echo lcfirst("Éclair"), "\n";
echo mb_convert_case("éclair", MB_CASE_TITLE), "\n";

// str_split with multibyte
print_r(str_split("café", 1));   // byte-based
print_r(mb_str_split("café", 1));
print_r(mb_str_split("café", 2));

// bcmath
