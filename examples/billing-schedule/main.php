<?php
// covers: DatePeriod iteration (recurrence count, end-date bound,
//   EXCLUDE_START_DATE), DateInterval (spec construction, format,
//   createFromDateString), DateTime add / diff, DateTimeImmutable
//   immutability, and PHP's month-overflow date arithmetic

function plans(): array
{
    return [
        ['Monthly', '2024-01-15', 'P1M', 6],
        ['Quarterly', '2024-02-29', 'P3M', 4],
        ['Weekly', '2024-03-04', 'P1W', 5],
    ];
}

echo "== billing schedules ==\n";
foreach (plans() as [$name, $start, $spec, $cycles]) {
    $period = new DatePeriod(new DateTime($start), new DateInterval($spec), $cycles);
    $dates = [];
    foreach ($period as $d) {
        $dates[] = $d->format('Y-m-d');
    }
    echo $name, ' (', count($dates), ' charges): ', implode(', ', $dates), "\n";
}

echo "== trial then billing (exclude start) ==\n";
$signup = new DateTime('2024-05-10');
$trialEnd = (clone $signup)->add(new DateInterval('P14D'));
echo 'signup ', $signup->format('Y-m-d'), ', trial ends ', $trialEnd->format('Y-m-d'), "\n";
$billing = new DatePeriod(
    $trialEnd,
    new DateInterval('P1M'),
    new DateTime('2024-09-01'),
    DatePeriod::EXCLUDE_START_DATE,
);
foreach ($billing as $d) {
    echo '  charge on ', $d->format('Y-m-d'), "\n";
}

echo "== proration ==\n";
$cycleStart = new DateTime('2024-06-01');
$cycleEnd = new DateTime('2024-07-01');
$joined = new DateTime('2024-06-19');
echo 'cycle is ', $cycleStart->diff($cycleEnd)->days, ' days; ';
echo $joined->diff($cycleEnd)->days, " days remaining when joined\n";

echo "== interval arithmetic ==\n";
$iv = DateInterval::createFromDateString('1 month 15 days');
echo 'parsed interval: ', $iv->format('%m months, %d days'), "\n";

$base = new DateTimeImmutable('2024-01-31');
$shifted = $base->add(new DateInterval('P1M'));
echo 'immutable base ', $base->format('Y-m-d'), ' stays put; shifted to ', $shifted->format('Y-m-d'), "\n";

$span = (new DateTime('2024-01-01'))->diff(new DateTime('2025-04-20'));
echo 'total span: ', $span->format('%y years, %m months, %d days'), "\n";

echo "done\n";
