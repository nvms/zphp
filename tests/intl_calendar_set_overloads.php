<?php
// regression: IntlCalendar::set() supports PHP's positional overloads
// set(year, month, day) | set(y,m,d,h,i) | set(y,m,d,h,i,s) in addition to
// the 2-arg set(field, value). previously zphp only handled the 2-arg form,
// so passing 3 args silently treated 2024 as a field index and got nowhere.
// also adds FIELD_DAY_OF_MONTH (the canonical PHP name for ICU's UCAL_DATE=5);
// FIELD_DATE was registered but PHP code reaches for FIELD_DAY_OF_MONTH
$c = IntlCalendar::createInstance('UTC');
$c->set(2024, 2, 15, 10, 30);
echo $c->get(IntlCalendar::FIELD_YEAR) . "/" . $c->get(IntlCalendar::FIELD_MONTH) . "/" . $c->get(IntlCalendar::FIELD_DAY_OF_MONTH) . "\n";
echo $c->get(IntlCalendar::FIELD_HOUR_OF_DAY) . ":" . $c->get(IntlCalendar::FIELD_MINUTE) . "\n";

$c = IntlCalendar::createInstance('UTC');
$c->set(2024, 2, 15, 10, 30, 45);
echo $c->get(IntlCalendar::FIELD_HOUR_OF_DAY) . ":" . $c->get(IntlCalendar::FIELD_MINUTE) . ":" . $c->get(IntlCalendar::FIELD_SECOND) . "\n";

$c = IntlCalendar::createInstance('UTC');
$c->set(IntlCalendar::FIELD_YEAR, 2030);
echo $c->get(IntlCalendar::FIELD_YEAR) . "\n";

$c = IntlCalendar::createInstance('UTC');
$c->set(2024, 2, 15);
echo $c->get(IntlCalendar::FIELD_YEAR) . "/" . $c->get(IntlCalendar::FIELD_MONTH) . "/" . $c->get(IntlCalendar::FIELD_DAY_OF_MONTH) . "\n";

echo "alias: " . (IntlCalendar::FIELD_DAY_OF_MONTH === IntlCalendar::FIELD_DATE ? "y\n" : "n\n");
