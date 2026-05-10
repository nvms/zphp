<?php
// DateTime arithmetic
$d = new DateTime("2024-06-15 12:00:00");
$d->modify("+1 hour");
echo $d->format("Y-m-d H:i:s"), "\n";

$d->modify("+30 minutes");
echo $d->format("Y-m-d H:i:s"), "\n";

$d->modify("+1 month");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2024-01-31");
$d->modify("+1 month");
echo $d->format("Y-m-d"), "\n"; // 2024-03-02 (Feb has fewer days, overflows)

// DateTime comparison operators
$a = new DateTime("2024-01-01");
$b = new DateTime("2024-06-01");
$c = new DateTime("2024-01-01");
var_dump($a < $b);
var_dump($a > $b);
var_dump($a == $c);
var_dump($a < $c);
var_dump($a <=> $b);
var_dump($a <=> $c);

// DateInterval invert
$a = new DateTime("2024-06-15");
$b = new DateTime("2024-01-15");
$diff = $a->diff($b);
echo $diff->invert, "\n"; // 1 (a > b)

$diff2 = $b->diff($a);
echo $diff2->invert, "\n"; // 0

// DateInterval format with sign
$a = new DateTime("2024-06-15");
$b = new DateTime("2024-01-15");
echo $a->diff($b)->format("%R%a days"), "\n"; // -151 days (or +5 months)
echo $b->diff($a)->format("%R%a days"), "\n"; // +151

// DatePeriod
$start = new DateTime("2024-01-01");
$end = new DateTime("2024-01-05");
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, $end);
foreach ($period as $d) echo $d->format("Y-m-d"), "|";
echo "\n";

// DatePeriod with iteration count
$period = new DatePeriod($start, $interval, 3);
foreach ($period as $d) echo $d->format("Y-m-d"), "|";
echo "\n";

// sprintf %e format
echo sprintf("[%e]", 1234567.89), "\n"; // [1.234568e+6]
echo sprintf("[%.2e]", 1234567.89), "\n"; // [1.23e+6]
echo sprintf("[%E]", 1234567.89), "\n"; // [1.234568E+6]

// sprintf %a unknown - PHP throws ValueError
try { sprintf("[%a]", 1.5); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

// SplStack push/pop empty
$s = new SplStack();
try { $s->pop(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt\n"; }
$s->push(1);
echo $s->pop(), "\n";
try { $s->pop(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt\n"; }
try { $s->top(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt\n"; }

// SplQueue dequeue empty
$q = new SplQueue();
try { $q->dequeue(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt\n"; }
$q->enqueue("a");
$q->enqueue("b");
echo $q->dequeue(), "|", $q->dequeue(), "\n";
try { $q->dequeue(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt\n"; }

// SplDoublyLinkedList edge
$l = new SplDoublyLinkedList();
try { $l->shift(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt-shift\n"; }
try { $l->pop(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt-pop\n"; }
try { $l->bottom(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt-bot\n"; }
try { $l->top(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt-top\n"; }

// SplFixedArray bounds
$fa = new SplFixedArray(3);
try { echo $fa[-1]; } catch (\OutOfBoundsException $e) { echo "oob-neg\n"; }
try { echo $fa[3]; } catch (\OutOfBoundsException $e) { echo "oob-high\n"; }

// DateTime mutability
$d = new DateTime("2024-06-15");
$ref = $d;
$d->modify("+1 day");
echo $d->format("Y-m-d"), "|", $ref->format("Y-m-d"), "\n"; // both 2024-06-16

$di = new DateTimeImmutable("2024-06-15");
$ref = $di;
$di2 = $di->modify("+1 day");
echo $di->format("Y-m-d"), "|", $ref->format("Y-m-d"), "|", $di2->format("Y-m-d"), "\n";

// DateTime::createFromImmutable
$di = new DateTimeImmutable("2024-06-15");
$dm = DateTime::createFromImmutable($di);
echo get_class($dm), ":", $dm->format("Y-m-d"), "\n";

// DateTime::createFromMutable
$dm = new DateTime("2024-06-15");
$di = DateTimeImmutable::createFromMutable($dm);
echo get_class($di), ":", $di->format("Y-m-d"), "\n";
