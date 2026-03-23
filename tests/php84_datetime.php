<?php

// DateTime::createFromTimestamp
$dt = DateTime::createFromTimestamp(1700000000);
echo $dt->format("Y-m-d H:i:s") . "\n";
echo $dt->getTimestamp() . "\n";

// DateTimeImmutable::createFromTimestamp
$dti = DateTimeImmutable::createFromTimestamp(0);
echo $dti->format("Y-m-d H:i:s") . "\n";

// getMicrosecond
$dt2 = new DateTime("2024-01-01 00:00:00");
echo $dt2->getMicrosecond() . "\n";

// setMicrosecond returns $this
$dt3 = new DateTime("2024-06-15 12:00:00");
$dt3->setMicrosecond(500000);
echo $dt3->format("Y-m-d") . "\n";

// mb_ucfirst / mb_lcfirst
echo mb_ucfirst("hello world") . "\n";
echo mb_lcfirst("Hello World") . "\n";
echo mb_ucfirst("") . "\n";
echo mb_lcfirst("") . "\n";

// fpow
echo fpow(2.0, 10.0) . "\n";
echo fpow(3.0, 0.0) . "\n";
echo fpow(2.5, 2.0) . "\n";
