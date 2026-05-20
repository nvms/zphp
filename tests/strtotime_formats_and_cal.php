<?php
// regression: strtotime gains four parse forms it previously returned the
// 1970 epoch / midnight for, plus cal_days_in_month is now defined.
date_default_timezone_set('UTC');

// bare time-of-day - keeps base's date, replaces the time
$base = mktime(0, 0, 0, 6, 15, 2024);
echo date('Y-m-d H:i:s', strtotime('14:30', $base)), "\n";
echo date('Y-m-d H:i:s', strtotime('9:05:30', $base)), "\n";
echo date('H:i', strtotime('2:30pm', $base)), "\n";

// ISO 8601 week date YYYY-Www-D (and bare YYYY-Www = Monday)
echo date('Y-m-d D', strtotime('2024-W10-1')), "\n";
echo date('Y-m-d D', strtotime('2024-W10-7')), "\n";
echo date('Y-m-d D', strtotime('2024-W01')), "\n";

// YYYY/MM/DD slash date
echo date('Y-m-d', strtotime('2024/03/15')), "\n";
echo date('Y-m-d', strtotime('2024/12/31')), "\n";

// "<weekday> this|next|last week" - weekday within base's ISO week
$wed = mktime(0, 0, 0, 1, 10, 2024); // Wednesday
echo date('Y-m-d D', strtotime('monday this week', $wed)), "\n";
echo date('Y-m-d D', strtotime('friday this week', $wed)), "\n";
echo date('Y-m-d D', strtotime('monday next week', $wed)), "\n";
echo date('Y-m-d D', strtotime('sunday last week', $wed)), "\n";

// cal_days_in_month
echo cal_days_in_month(CAL_GREGORIAN, 2, 2024), "\n";
echo cal_days_in_month(CAL_GREGORIAN, 2, 2023), "\n";
echo cal_days_in_month(CAL_GREGORIAN, 4, 2024), "\n";
echo cal_days_in_month(CAL_GREGORIAN, 12, 2024), "\n";
try { cal_days_in_month(CAL_GREGORIAN, 13, 2024); }
catch (\ValueError $e) { echo "ve: " . $e->getMessage() . "\n"; }
