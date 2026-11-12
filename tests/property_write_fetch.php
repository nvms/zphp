<?php
function foo() { return null; }
foreach ([
    fn() => $undef1->a = 42,
    fn() => $undef2->a['hello'] = 42,
    fn() => $undef3->a->b = 42,
    fn() => $undef4->a[] = 1,
    fn() => foo()->a = 1,
    fn() => foo()->a->b = 2,
    fn() => foo()->a->b += 2,
] as $i => $f) {
    try { $f(); } catch (Error $e) { echo "$i: ", $e->getMessage(), "\n"; }
}
$o = new stdClass;
try { $o->a->b = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($o);
$o->x = new stdClass;
$o->x->y->z = 5;
var_dump($o);
class C { public $list = []; public ?C $next = null; }
$c = new C;
$c->list[] = 1;
$c->next = new C;
$c->next->list['k'] = 2;
var_dump($c);
try { $c->next->next->list[] = 3; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$s = "str";
try { $s->a->b = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
