<?php
// DateInterval has an invert property and no invert() method
$i = new DateInterval('P1D');
$i->invert = 1;
var_dump($i->invert, method_exists($i, 'invert'));
class Span extends DateInterval {
    public function invert(bool $on = true): static { $this->invert = (int) $on; return $this; }
}
var_dump((new Span('PT1H'))->invert()->invert);
try { $i->invert(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
