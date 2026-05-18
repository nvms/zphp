<?php
// regression: strtotime('monday') from a Monday returns TODAY at 00:00, not
// next Monday. PHP's bare-weekday and 'this <weekday>' semantics differ
// from 'next <weekday>' which always advances by at least 1 day
$mon = strtotime("2024-03-18 12:00:00");   // Mon
$tue = strtotime("2024-03-19 12:00:00");   // Tue
$fri = strtotime("2024-03-22 12:00:00");   // Fri

// bare weekday name
echo "monday from mon: " . date("Y-m-d D", strtotime("monday", $mon)) . "\n";   // today
echo "tuesday from mon: " . date("Y-m-d D", strtotime("tuesday", $mon)) . "\n"; // +1
echo "sunday from mon: " . date("Y-m-d D", strtotime("sunday", $mon)) . "\n";   // +6
echo "monday from tue: " . date("Y-m-d D", strtotime("monday", $tue)) . "\n";   // +6
echo "friday from fri: " . date("Y-m-d D", strtotime("friday", $fri)) . "\n";   // today

// this <weekday> - same semantics as bare
echo "this monday from mon: " . date("Y-m-d D", strtotime("this monday", $mon)) . "\n";
echo "this tuesday from mon: " . date("Y-m-d D", strtotime("this tuesday", $mon)) . "\n";

// next/last <weekday> always advances at least 1 occurrence
echo "next monday from mon: " . date("Y-m-d D", strtotime("next monday", $mon)) . "\n";   // +7
echo "last monday from mon: " . date("Y-m-d D", strtotime("last monday", $mon)) . "\n";   // -7
echo "next friday from fri: " . date("Y-m-d D", strtotime("next friday", $fri)) . "\n";   // +7
