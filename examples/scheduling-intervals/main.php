<?php
// covers: DatePeriod iteration (start/interval/end + start/interval/count),
//   DateInterval::createFromDateString, business-day calc, range building

echo "=== weekly cadence by count ===\n";
$start = new DateTimeImmutable('2026-01-05'); // a Monday
$period = new DatePeriod($start, new DateInterval('P7D'), 4);
foreach ($period as $d) echo "  " . $d->format('Y-m-d D') . "\n";

echo "\n=== daily cadence to end date ===\n";
$end = new DateTimeImmutable('2026-01-10');
$period = new DatePeriod(new DateTimeImmutable('2026-01-05'), new DateInterval('P1D'), $end);
$dates = [];
foreach ($period as $d) $dates[] = $d->format('Y-m-d');
echo implode(", ", $dates) . "\n";
echo "count: " . count($dates) . "\n";

echo "\n=== exclude start option ===\n";
$period = new DatePeriod(
    new DateTimeImmutable('2026-02-01'),
    new DateInterval('P1D'),
    3,
    DatePeriod::EXCLUDE_START_DATE,
);
foreach ($period as $d) echo "  " . $d->format('Y-m-d') . "\n";

echo "\n=== interval from human strings ===\n";
$cases = ['1 day', '2 weeks', '3 months', '1 year 2 months 10 days', '4 hours 30 minutes'];
foreach ($cases as $c) {
    $i = DateInterval::createFromDateString($c);
    echo sprintf("  '%s' -> y=%d m=%d d=%d h=%d i=%d\n", $c, $i->y, $i->m, $i->d, $i->h, $i->i);
}

echo "\n=== count weekdays in a range ===\n";
function countWeekdays(DateTimeImmutable $from, DateTimeImmutable $to): int {
    $count = 0;
    $period = new DatePeriod($from, new DateInterval('P1D'), $to->modify('+1 day'));
    foreach ($period as $d) {
        $dow = (int)$d->format('N');
        if ($dow >= 1 and $dow <= 5) $count++;
    }
    return $count;
}
echo "weekdays Jan 1-31 2026: " . countWeekdays(new DateTimeImmutable('2026-01-01'), new DateTimeImmutable('2026-01-31')) . "\n";
echo "weekdays Feb 1-28 2026: " . countWeekdays(new DateTimeImmutable('2026-02-01'), new DateTimeImmutable('2026-02-28')) . "\n";

echo "\n=== monthly cadence with overflow ===\n";
$d = new DateTimeImmutable('2026-01-31');
$period = new DatePeriod($d, new DateInterval('P1M'), 4);
foreach ($period as $x) echo "  " . $x->format('Y-m-d') . "\n";

echo "\n=== two-leg trip duration ===\n";
$depart = new DateTimeImmutable('2026-06-01 09:00:00');
$arrive = new DateTimeImmutable('2026-06-02 17:30:00');
$diff = $depart->diff($arrive);
printf("travel: %d days %d hours %d minutes\n", $diff->d, $diff->h, $diff->i);
echo "total hours: " . round(($arrive->getTimestamp() - $depart->getTimestamp()) / 3600, 2) . "\n";

echo "\n=== ISO week numbers around year boundary ===\n";
$weeks = [
    '2025-12-29', '2025-12-31', '2026-01-01', '2026-01-04', '2026-01-05',
];
foreach ($weeks as $w) {
    $d = new DateTimeImmutable($w);
    echo sprintf("  %s -> ISO week %s (year %s)\n", $w, $d->format('W'), $d->format('o'));
}
