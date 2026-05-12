<?php
// covers: DateTime arithmetic with DateInterval (add/sub/modify),
//   diff() with %a/%d/%h/%i/%s, immutable variants, comparison operators,
//   format specifiers, fromFormat parsing

echo "=== fixed reference dates ===\n";
$start = new DateTimeImmutable('2026-01-15 10:00:00');
$end   = new DateTimeImmutable('2026-03-30 17:45:00');

$diff = $start->diff($end);
echo "days: $diff->days\n";
echo "y/m/d/h/i/s: $diff->y/$diff->m/$diff->d/$diff->h/$diff->i/$diff->s\n";
echo "invert (start>end): " . $diff->invert . "\n";

// reverse should invert
$diff2 = $end->diff($start);
echo "reverse invert: " . $diff2->invert . "\n";

echo "\n=== add/sub via DateInterval ===\n";
$d = new DateTimeImmutable('2026-05-11');
$plus = $d->add(new DateInterval('P10D'));
echo "+10 days: " . $plus->format('Y-m-d') . "\n";
$minus = $d->sub(new DateInterval('P3M'));
echo "-3 months: " . $minus->format('Y-m-d') . "\n";
$big = $d->add(new DateInterval('P1Y2M3DT4H'));
echo "+1y2m3d4h: " . $big->format('Y-m-d H:i:s') . "\n";

echo "\n=== modify shorthand ===\n";
$now = new DateTimeImmutable('2026-05-11 12:00:00');
echo "tomorrow: " . $now->modify('+1 day')->format('Y-m-d') . "\n";
echo "next monday: " . $now->modify('next monday')->format('Y-m-d D') . "\n";
echo "first of month: " . $now->modify('first day of this month')->format('Y-m-d') . "\n";
echo "last of month: " . $now->modify('last day of this month')->format('Y-m-d') . "\n";

echo "\n=== format specifiers ===\n";
$dt = new DateTimeImmutable('2026-05-11 14:30:45');
$specs = ['Y', 'y', 'm', 'n', 'd', 'j', 'H', 'h', 'i', 's', 'D', 'l', 'N', 'w', 'W', 'z', 'L', 'U', 'c', 'r'];
foreach ($specs as $s) {
    echo sprintf("  %s -> %s\n", $s, $dt->format($s));
}

echo "\n=== parse via createFromFormat ===\n";
$formats = [
    ['Y-m-d',    '2026-05-11'],
    ['d/m/Y',    '11/05/2026'],
    ['Y-m-d H:i', '2026-05-11 09:30'],
    ['U',        '1717070400'],
    ['Y-m-d\TH:i:sP', '2026-05-11T14:30:00+02:00'],
];
foreach ($formats as [$f, $s]) {
    $r = DateTimeImmutable::createFromFormat($f, $s);
    echo "  format='$f' input='$s' -> " . ($r ? $r->format('c') : "FAILED") . "\n";
}

echo "\n=== timestamps and comparison ===\n";
$a = new DateTimeImmutable('2026-05-11 10:00:00');
$b = new DateTimeImmutable('2026-05-11 10:00:01');
echo "a < b: " . ($a < $b ? "yes" : "no") . "\n";
echo "a == a: " . ($a == new DateTimeImmutable('2026-05-11 10:00:00') ? "yes" : "no") . "\n";
echo "a->getTimestamp(): " . $a->getTimestamp() . "\n";

echo "\n=== weekday math ===\n";
$d = new DateTimeImmutable('2026-05-11');
echo "May 11, 2026 is: " . $d->format('l') . "\n";
$friday = $d->modify('Friday this week');
echo "this week's friday: " . $friday->format('Y-m-d D') . "\n";

echo "\n=== DateTime (mutable) vs Immutable ===\n";
$m = new DateTime('2026-01-01');
$ret = $m->modify('+1 day');
echo "mutable modify returns same object: " . ($ret === $m ? "yes" : "no") . "\n";
echo "value: " . $m->format('Y-m-d') . "\n";

$im = new DateTimeImmutable('2026-01-01');
$ret = $im->modify('+1 day');
echo "immutable modify returns NEW: " . ($ret !== $im ? "yes" : "no") . "\n";
echo "original: " . $im->format('Y-m-d') . " new: " . $ret->format('Y-m-d') . "\n";
