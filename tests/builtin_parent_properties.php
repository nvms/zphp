<?php
// a subclass of DateInterval or DatePeriod lists its own properties, then the
// built-in parent's fields, and serializes and restores both; a DateTime far
// beyond year 9999 survives serialization
class Span extends DateInterval { public $label = 'span'; }
class Range extends DatePeriod {
    public function __construct(DateTimeInterface $start, DateInterval $interval, int $recurrences, public ?bool $flag = null) {
        parent::__construct($start, $interval, $recurrences);
    }
}
$s = new Span('P1DT2H');
print_r(array_keys(get_object_vars($s)));
print_r($s);
$copy = unserialize(serialize($s));
echo $copy->label, ' ', $copy->format('%d %h'), "\n";
$r = new Range(new DateTimeImmutable('2020-01-01', new DateTimeZone('UTC')), new DateInterval('PT5S'), 2, flag: true);
print_r(array_keys(get_object_vars($r)));
echo serialize($r), "\n";
$back = unserialize(serialize($r));
var_dump($back->flag);
foreach ($back as $d) echo $d->format('H:i:s'), "\n";
foreach ([PHP_INT_MAX >> 20, PHP_INT_MIN >> 20] as $ts) {
    $d = new DateTime('@' . $ts);
    echo serialize($d), "\n", unserialize(serialize($d))->format('Y-m-d H:i:s'), "\n";
}
