<?php

// createFromTimestamp
$dt = DateTime::createFromTimestamp(1700000000);
echo $dt->format("Y-m-d") . "\n";

// diff components
$a = new DateTime("2024-01-01 10:00:00");
$b = new DateTime("2024-03-15 14:30:00");
$diff = $a->diff($b);
echo "days:" . $diff->days . "\n";
echo "h:" . $diff->h . "\n";
echo "i:" . $diff->i . "\n";

// setDate then format
$dt3 = new DateTime("2024-01-01");
$dt3->setDate(2025, 12, 31);
echo $dt3->format("Y-m-d") . "\n";

// setTime
$dt4 = new DateTime("2024-01-01 00:00:00");
$dt4->setTime(23, 59);
echo $dt4->format("H:i") . "\n";

// getTimestamp / setTimestamp roundtrip
$dt5 = new DateTime("2024-06-15 00:00:00");
$ts = $dt5->getTimestamp();
$dt6 = new DateTime();
$dt6->setTimestamp($ts);
echo $dt6->format("Y-m-d") . "\n";

// format specifiers
$dt7 = new DateTime("2024-02-15 09:05:30");
echo $dt7->format("Y") . "\n";
echo $dt7->format("m") . "\n";
echo $dt7->format("d") . "\n";
echo $dt7->format("H") . "\n";
echo $dt7->format("i") . "\n";
echo $dt7->format("s") . "\n";
echo $dt7->format("G") . "\n";
echo $dt7->format("N") . "\n";

// modify with days
$dt8 = new DateTime("2024-03-15 12:00:00");
$dt8->modify("+5 days");
echo $dt8->format("Y-m-d") . "\n";
$dt8->modify("-2 days");
echo $dt8->format("Y-m-d") . "\n";

// modify with months
$dt9 = new DateTime("2024-03-15 12:00:00");
$dt9->modify("+1 month");
echo $dt9->format("Y-m-d") . "\n";
$dt9->modify("-2 days");
echo $dt9->format("Y-m-d") . "\n";

// modify with years
$dt10 = new DateTime("2024-01-01 00:00:00");
$dt10->modify("+1 year");
$dt10->modify("+6 months");
echo $dt10->format("Y-m-d") . "\n";

// month overflow: jan 31 + 1 month = feb 29 (leap year 2024) or feb 28
$dt11 = new DateTime("2024-01-31 00:00:00");
$dt11->modify("+1 month");
echo $dt11->format("Y-m-d") . "\n";

// month underflow: march - 1 month
$dt12 = new DateTime("2024-03-15 00:00:00");
$dt12->modify("-1 month");
echo $dt12->format("Y-m-d") . "\n";

// year crossing: nov + 3 months
$dt13 = new DateTime("2024-11-15 00:00:00");
$dt13->modify("+3 months");
echo $dt13->format("Y-m-d") . "\n";
