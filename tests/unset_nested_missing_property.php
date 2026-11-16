<?php
// unset() through a missing property fetches it as php's BP_VAR_UNSET does:
// the property is created as null without a warning
$a = new stdClass;
unset($a->b->c->d);
unset($a->b->c['d']);
var_dump($a);

readonly class R {}
$r = new R;
try {
    unset($r->q->r);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

$o = new stdClass;
$o->set = new stdClass;
$o->set->x = 1;
unset($o->set->x);
unset($o->other->x);
var_dump($o);
