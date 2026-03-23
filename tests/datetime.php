<?php

// basic construction and formatting
$dt = new DateTime("2024-01-15 10:30:45");
echo $dt->format("Y-m-d H:i:s") . "\n";
echo $dt->format("l, F j, Y") . "\n";
echo $dt->format("g:i A") . "\n";

// getTimestamp
echo $dt->getTimestamp() . "\n";

// setTimestamp
$dt2 = new DateTime();
$dt2->setTimestamp(0);
echo $dt2->format("Y-m-d H:i:s") . "\n";

// modify
$dt3 = new DateTime("2024-06-15 12:00:00");
$dt3->modify("+3 days");
echo $dt3->format("Y-m-d") . "\n";
$dt3->modify("-1 hour");
echo $dt3->format("H:i") . "\n";

// diff
$a = new DateTime("2024-01-01 00:00:00");
$b = new DateTime("2024-01-11 06:30:00");
$diff = $a->diff($b);
echo $diff->days . "\n";
echo $diff->h . "\n";
echo $diff->i . "\n";

// setDate / setTime
$dt4 = new DateTime("2024-01-01 00:00:00");
$dt4->setDate(2025, 6, 15);
echo $dt4->format("Y-m-d") . "\n";
$dt4->setTime(14, 30, 15);
echo $dt4->format("H:i:s") . "\n";

// instanceof DateTimeInterface
echo ($dt instanceof DateTimeInterface) ? "true" : "false";
echo "\n";

// immutable modify returns new object
$imm = new DateTimeImmutable("2024-03-01 12:00:00");
$imm2 = $imm->modify("+1 day");
echo $imm->format("Y-m-d") . "\n";
echo $imm2->format("Y-m-d") . "\n";

// format specifiers
$dt5 = new DateTime("2024-02-29 00:00:00");
echo $dt5->format("t") . "\n";
echo $dt5->format("y") . "\n";
echo $dt5->format("n") . "\n";
echo $dt5->format("D, M j") . "\n";
