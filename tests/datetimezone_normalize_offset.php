<?php
// regression: DateTimeZone normalizes fixed-offset names to '+HH:MM' /
// '-HH:MM' form (PHP's canonical representation). previously zphp stored
// the input verbatim so 'GMT+5'->getName() returned 'GMT+5' instead of
// '+05:00'. also adds 'GMT+N' parsing and timezone_open() validation
echo (new DateTimeZone('+05:00'))->getName() . "\n";
echo (new DateTimeZone('-08:30'))->getName() . "\n";
echo (new DateTimeZone('GMT+5'))->getName() . "\n";       // -> '+05:00'
echo (new DateTimeZone('GMT-3:30'))->getName() . "\n";    // -> '-03:30'

// passthrough for named zones + bare UTC/GMT
echo (new DateTimeZone('UTC'))->getName() . "\n";
echo (new DateTimeZone('GMT'))->getName() . "\n";
echo (new DateTimeZone('America/New_York'))->getName() . "\n";

// timezone_open validates - emits warning + returns false on bad name
$r = timezone_open('Not/A/Zone');
var_dump($r);
