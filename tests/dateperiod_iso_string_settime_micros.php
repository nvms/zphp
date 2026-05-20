<?php
// regression: (1) DatePeriod accepts the ISO 8601 recurring-interval string
// form 'R<n>/<start>/<interval>'. previously the constructor required three
// object args and silently produced an empty period for the string form.
// R<n> yields n+1 occurrences (the start plus n recurrences). (2)
// DateTime::setTime() honors the 4th microseconds argument; the 'u' format
// specifier reads it back. setTime with <4 args resets sub-seconds to 0
$p = new DatePeriod('R3/2024-01-01T00:00:00Z/P1D');
$dates = [];
foreach ($p as $d) $dates[] = $d->format('Y-m-d');
print_r($dates);
echo "recurrences: " . $p->getRecurrences() . "\n";
echo "start: " . $p->getStartDate()->format('Y-m-d') . "\n";
echo "interval-days: " . $p->getDateInterval()->format('%d') . "\n";

// hourly recurrence
$ph = new DatePeriod('R2/2024-01-01T00:00:00Z/PT6H');
foreach ($ph as $d) echo "h: " . $d->format('H:i') . "\n";

// setTime microseconds
$d = new DateTime('2024-01-01');
$d->setTime(10, 30, 45, 500000);
echo $d->format('H:i:s.u') . "\n";
$d->setTime(8, 15, 0, 123456);
echo $d->format('H:i:s.u') . "\n";
$d->setTime(6, 0);
echo $d->format('H:i:s.u') . "\n";
