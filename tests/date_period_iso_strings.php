<?php
// DatePeriod reads ISO 8601 interval strings with timelib's interval scanner
$cases = [
    'R4/2012-07-01T00:00:00Z/P7D',
    'R2/20120701T000000Z/P1Y2M10DT2H30M',
    '2012-07-01T00:00:00Z/P1D/2012-07-05T00:00:00Z',
    'R3/2012-07-01T00:00:00Z/P0001-02-03T04:05:06',
    'R2/2012-07-01T24:00:00Z/PT36H',
    '  R1/2012-07-01T00:00:00Z/P1W  ',
    'R2/P1D',
    'R2/2012-07-01T00:00:00Z',
    'R2/2012-07-01T00:00:00Z/P',
    'R2/2012-07-01T00:00:00Z/PT',
    'R2/2012-07-01T00:00:00Z/P1X',
    'R2/2012-07-01/P1D',
    '',
    'R2/2012-07-01T00:00:00Z/P1D/garbage',
];
foreach ($cases as $c) {
    echo "[$c]\n";
    try {
        $p = DatePeriod::createFromISO8601String($c);
        echo get_class($p->start), ' ', $p->recurrences, ' ', var_export($p->getRecurrences(), true), ' ', $p->end?->format('c') ?? '-', "\n";
        foreach ($p as $d) echo '  ', get_class($d), ' ', $d->format('Y-m-d H:i:s P'), "\n";
    } catch (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
}
class MyPeriod extends DatePeriod {}
echo get_class(MyPeriod::createFromISO8601String('R1/2012-07-01T00:00:00Z/P1D')), "\n";
try { $p = new DatePeriod('R2/2012-07-01T00:00:00Z/P1D', DatePeriod::EXCLUDE_START_DATE); foreach ($p as $d) echo get_class($d), ' ', $d->format('c'), "\n"; } catch (Throwable $e) { echo $e->getMessage(), "\n"; }
try { new DatePeriod('nope'); } catch (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
