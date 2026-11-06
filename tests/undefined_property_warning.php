<?php
// reading a property the object doesn't have warns and reads null; isset, ??,
// @ and __get don't warn
class Plain {}
class Magic { public function __get($n) { return "magic $n"; } }
$p = new Plain;
var_dump($p->missing);
var_dump($p->missing['k'] ?? 'default', isset($p->missing), @$p->missing);
echo (new Magic)->anything, "\n";
$o = new stdClass;
$o->set = 1;
var_dump($o->set, $o->unset);
unset($o->set);
var_dump($o->set);
$n = null;
var_dump($n?->x);
set_error_handler(function ($no, $str) { echo "handler: $str\n"; return true; });
var_dump($p->viaHandler);
