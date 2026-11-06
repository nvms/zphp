<?php
// date intervals and periods show the properties php shows, serialize in its
// format, and periods iterate and count recurrences as php does
$i = new DateInterval('P1Y2M3DT4H5M6S');
print_r($i); var_export($i); echo "\n", json_encode($i), "\n", serialize($i), "\n";
print_r(get_object_vars($i));
$d = (new DateTime('2020-01-01', new DateTimeZone('UTC')))->diff(new DateTime('2021-03-05 06:07:08.5', new DateTimeZone('UTC')));
print_r($d); echo serialize($d), "\n";
$s = DateInterval::createFromDateString('3 days ago');
print_r($s); echo serialize($s), "\n"; var_export($s); echo "\n";
$u = unserialize(serialize($i)); echo $u->format('%y %m %d %h %i %s'), "\n";
$u = unserialize(serialize($s)); echo $u->format('%d'), ' ', $u->date_string ?? '-', "\n";
$p = new DatePeriod(new DateTime('2020-01-01', new DateTimeZone('UTC')), new DateInterval('P1D'), 2);
print_r($p); echo serialize($p), "\n";
foreach (unserialize(serialize($p)) as $x) echo $x->format('Y-m-d'), "\n";
var_export(DateInterval::__set_state(['y' => 1, 'm' => 0, 'd' => 0, 'h' => 0, 'i' => 0, 's' => 0, 'f' => 0.0, 'invert' => 0, 'days' => false, 'from_string' => false])); echo "\n";
$s = new DateTime('2020-01-01', new DateTimeZone('UTC'));
$p = new DatePeriod($s, new DateInterval('P1D'), 2);
var_dump($p->recurrences, $p->getRecurrences(), $p->include_start_date, $p->current);
foreach ($p as $d) echo $d->format('Y-m-d'), "\n";
print_r($p->current);
$e = new DatePeriod($s, new DateInterval('P1D'), new DateTime('2020-01-04', new DateTimeZone('UTC')), DatePeriod::EXCLUDE_START_DATE | DatePeriod::INCLUDE_END_DATE);
var_dump($e->recurrences, $e->getRecurrences(), $e->include_start_date, $e->include_end_date);
foreach ($e as $d) echo $d->format('Y-m-d'), "\n";

try { $p->start = null; } catch (Error $x) { echo $x->getMessage(), "\n"; }
$u = unserialize(serialize($e)); foreach ($u as $d) echo $d->format('Y-m-d'), "\n";
var_export($e); echo "\n";
$r = DatePeriod::__set_state(['start' => $s, 'current' => null, 'end' => null, 'interval' => new DateInterval('P2D'), 'recurrences' => 3, 'include_start_date' => true, 'include_end_date' => false]);
foreach ($r as $d) echo $d->format('Y-m-d'), "\n";
try { DatePeriod::__set_state([]); } catch (Error $x) { echo get_class($x), ': ', $x->getMessage(), "\n"; }
print_r(get_object_vars($p));
$rc = new ReflectionClass('DatePeriod'); foreach ($rc->getProperties() as $pr) echo $pr->getName(), ' ', $pr->getType(), ' ', $pr->isReadOnly() ? 'ro' : 'rw', "\n";
$s = new DateTimeImmutable('2020-01-01 10:00', new DateTimeZone('Europe/Paris'));
foreach ([0, -1] as $r) { try { new DatePeriod($s, new DateInterval('P1D'), $r); } catch (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; } }
$p = new DatePeriod($s, new DateInterval('P1D'), 1);
var_dump($p->getStartDate() === $p->getStartDate(), get_class($p->getStartDate()), get_class($p->start));
foreach ($p as $k => $d) echo $k, ' ', get_class($d), ' ', $d->format('c'), "\n";
class MyDT extends DateTime {}
$q = new DatePeriod(new MyDT('2020-01-01'), new DateInterval('PT12H'), 2, DatePeriod::EXCLUDE_START_DATE);
foreach ($q as $d) echo get_class($d), ' ', $d->format('c'), "\n";
echo get_class($q->start), ' ', get_class($q->current), "\n";
var_dump(DatePeriod::createFromISO8601String('R2/2012-07-01T00:00:00Z/P7D')->getRecurrences());
$c = clone $p; var_dump($c->recurrences);
