<?php
// a case's name and value are readonly, and an enum takes no other property
enum Suit: string { case Hearts = 'H'; }
function bump(&$v) { $v = 'X'; }
$h = Suit::Hearts;
$attempts = [
    fn () => $h->name = 'Other',
    fn () => $h->value = 'Y',
    fn () => $h->extra = 1,
    function () use ($h) { unset($h->name); },
    fn () => bump($h->value),
];
foreach ($attempts as $f) {
    try { $f(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
var_dump($h->name, $h->value);
class Point {
    public function __construct(public readonly int $x = 1) {}
    function viaReference() { try { bump($this->x); } catch (Error $e) { echo $e->getMessage(), "\n"; } }
}
(new Point)->viaReference();
