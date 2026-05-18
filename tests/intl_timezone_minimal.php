<?php
// regression: minimal IntlTimeZone class with createTimeZone/createDefault/
// getID/getRawOffset. previously the class was missing so any code that
// instantiates an IntlTimeZone (intl-extension users, date-tz wrappers)
// crashed with 'Call to undefined method'
$tz = IntlTimeZone::createTimeZone('America/New_York');
echo $tz->getID() . "\n";

$tz2 = IntlTimeZone::createTimeZone('UTC');
echo $tz2->getID() . "\n";

$tz3 = IntlTimeZone::createTimeZone('Europe/London');
var_dump($tz3 instanceof IntlTimeZone);
echo $tz3->getID() . "\n";

// raw offset returns int (zphp stubs as 0)
var_dump(is_int($tz->getRawOffset()));

// createDefault uses VM's default tz
$d = IntlTimeZone::createDefault();
echo strlen($d->getID()) > 0 ? 'has-default' : 'no-default';
echo "\n";
