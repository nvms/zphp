<?php
// covers: IntlCalendar (locale-aware date arithmetic via ICU)

$c = IntlCalendar::createInstance('UTC', 'en_US');
$c->clear();
$c->set(IntlCalendar::FIELD_YEAR, 2030);
$c->set(IntlCalendar::FIELD_MONTH, 5);          // June (0-indexed)
$c->set(IntlCalendar::FIELD_DATE, 15);
$c->set(IntlCalendar::FIELD_HOUR_OF_DAY, 14);
$c->set(IntlCalendar::FIELD_MINUTE, 30);
$c->set(IntlCalendar::FIELD_SECOND, 0);

echo "y=", $c->get(IntlCalendar::FIELD_YEAR), "\n";
echo "m=", $c->get(IntlCalendar::FIELD_MONTH), "\n";
echo "d=", $c->get(IntlCalendar::FIELD_DATE), "\n";
echo "h=", $c->get(IntlCalendar::FIELD_HOUR_OF_DAY), "\n";
echo "dow=", $c->get(IntlCalendar::FIELD_DAY_OF_WEEK), "\n";
echo "millis=", $c->getTime(), "\n";

// date arithmetic
$c->add(IntlCalendar::FIELD_MONTH, 8);
echo "after +8mo y=", $c->get(IntlCalendar::FIELD_YEAR), " m=", $c->get(IntlCalendar::FIELD_MONTH), "\n";

$c->add(IntlCalendar::FIELD_DATE, -30);
echo "after -30d y=", $c->get(IntlCalendar::FIELD_YEAR), " m=", $c->get(IntlCalendar::FIELD_MONTH), " d=", $c->get(IntlCalendar::FIELD_DATE), "\n";

// roll: doesn't carry over to bigger fields
$c2 = IntlCalendar::createInstance('UTC', 'en_US');
$c2->clear();
$c2->set(IntlCalendar::FIELD_YEAR, 2030);
$c2->set(IntlCalendar::FIELD_MONTH, 11);   // december
$c2->set(IntlCalendar::FIELD_DATE, 15);
$c2->roll(IntlCalendar::FIELD_MONTH, 2);   // wraps to feb but year unchanged
echo "after roll y=", $c2->get(IntlCalendar::FIELD_YEAR), " m=", $c2->get(IntlCalendar::FIELD_MONTH), "\n";

// type + locale + first day of week
echo "type=", $c->getType(), "\n";
echo "fdow en_US=", $c->getFirstDayOfWeek(), "\n";

$c3 = IntlCalendar::createInstance('UTC', 'de_DE');
echo "fdow de_DE=", $c3->getFirstDayOfWeek(), "\n";

$c->setFirstDayOfWeek(IntlCalendar::DOW_MONDAY);
echo "fdow override=", $c->getFirstDayOfWeek(), "\n";

// actual bounds
echo "max month=", $c->getActualMaximum(IntlCalendar::FIELD_MONTH), "\n";
echo "max day in feb=", (function() {
    $cc = IntlCalendar::createInstance('UTC', 'en_US');
    $cc->clear();
    $cc->set(IntlCalendar::FIELD_YEAR, 2024); // leap
    $cc->set(IntlCalendar::FIELD_MONTH, 1);   // feb
    return $cc->getActualMaximum(IntlCalendar::FIELD_DATE);
})(), "\n";
echo "max day in mar=", (function() {
    $cc = IntlCalendar::createInstance('UTC', 'en_US');
    $cc->clear();
    $cc->set(IntlCalendar::FIELD_YEAR, 2024);
    $cc->set(IntlCalendar::FIELD_MONTH, 2);   // mar
    return $cc->getActualMaximum(IntlCalendar::FIELD_DATE);
})(), "\n";

// lenient
echo "lenient default=", $c->isLenient() ? 'y' : 'n', "\n";
$c->setLenient(false);
echo "lenient after=", $c->isLenient() ? 'y' : 'n', "\n";

// equality (two calendars set to identical wall time)
$a = IntlCalendar::createInstance('UTC', 'en_US');
$a->setTime($c->getTime());
echo "equals: ", $a->equals($c) ? 'y' : 'n', "\n";
$a->add(IntlCalendar::FIELD_DATE, 1);
echo "equals after add: ", $a->equals($c) ? 'y' : 'n', "\n";
