<?php
// regression: the DD-MM-YYYY date format (dashes, day-first) parses in both
// strtotime() and the DateTime constructor. zphp previously returned false
// from strtotime and threw DateMalformedStringException from new DateTime().
date_default_timezone_set('UTC');

foreach (['25-12-2024', '05-06-2024', '01-01-2000', '31-12-1999', '15-03-2024'] as $d) {
    echo str_pad($d, 14), ' => ', date('Y-m-d', strtotime($d)), "\n";
}

// with a time component
echo date('Y-m-d H:i:s', strtotime('25-12-2024 14:30:45')), "\n";

// the DateTime constructor accepts it too
echo (new DateTime('25-12-2024'))->format('Y-m-d'), "\n";
echo (new DateTime('05-06-2024'))->format('Y-m-d'), "\n";
echo (new DateTimeImmutable('31-12-1999'))->format('Y-m-d'), "\n";
echo (new DateTime('25-12-2024 09:15:00'))->format('Y-m-d H:i:s'), "\n";

// YYYY-MM-DD (ISO) is still parsed as year-first, not day-first
echo date('Y-m-d', strtotime('2024-12-25')), "\n";
echo (new DateTime('2024-06-15'))->format('Y-m-d'), "\n";

// a clearly day-first value (day > 12) is unambiguous
echo (new DateTime('20-07-2024'))->format('Y-m-d'), "\n";
