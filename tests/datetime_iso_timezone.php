<?php
$d = new DateTime("2024-12-31T23:59:59+02:00");
echo $d->format("c"), "\n";
echo $d->format("U"), "\n";

$d = new DateTime("2024-12-31T23:59:59-05:00");
echo $d->format("c"), "\n";

$d = new DateTime("2024-12-31T23:59:59+0200");
echo $d->format("c"), "\n";

$d = new DateTime("2024-12-31 23:59:59 +0200");
echo $d->format("c"), "\n";

$d = new DateTime("2024-12-31T23:59:59Z");
echo $d->format("c"), "\n";
echo $d->format("U"), "\n";

$d = new DateTime("2024-06-15T12:00:00+05:30");
echo $d->format("c"), "\n";
echo $d->format("P"), "\n";

$d = new DateTime("2024-06-15T12:00:00-08:00");
echo $d->format("c"), "\n";

$d = new DateTime("2024-01-01T00:00:00+00:00");
$d2 = new DateTime("2024-01-01T02:00:00+02:00");
echo $d->getTimestamp(), " ", $d2->getTimestamp(), "\n";
echo $d->getTimestamp() === $d2->getTimestamp() ? "same\n" : "diff\n";
