<?php

// date_parse on common formats
$p = date_parse('2024-06-15 14:30:00');
echo "$p[year]-$p[month]-$p[day] $p[hour]:$p[minute]:$p[second]\n";
echo $p['error_count'] . "\n";

$p2 = date_parse('2024-01-01');
echo "$p2[year]-$p2[month]-$p2[day]\n";

// timezone_name_get
$tz = new DateTimeZone('UTC');
echo timezone_name_get($tz) . "\n";

$tz2 = new DateTimeZone('America/New_York');
echo timezone_name_get($tz2) . "\n";

// timezone_open / timezone_offset_get
$tz3 = timezone_open('UTC');
$dt = new DateTime('2024-06-01 12:00:00');
echo timezone_offset_get($tz3, $dt) . "\n";

// date_timezone_get / set
$dt2 = new DateTime('2024-06-01 12:00', new DateTimeZone('UTC'));
echo date_timezone_get($dt2)->getName() . "\n";
date_timezone_set($dt2, new DateTimeZone('America/New_York'));
echo date_timezone_get($dt2)->getName() . "\n";
