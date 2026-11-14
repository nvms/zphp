<?php
// a reference to a property of something that isn't an object is php's
// "Attempt to modify property" Error, and `= &` binds tighter than the
// operators after it

$a = true;
$s = 'kept';
try { $s = &$a->p; } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($s);
try { $s = &$undefined->p; } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(isset($undefined));
$n = null;
try { $s = &$n->p; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $s = &$a->p->q; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$name = 'p';
try { $s = &$a->$name; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $d->d = &$d; } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($d);
try { $u->d = &$d + 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }

$x = 5;
$o = new stdClass;
var_dump(($o->p = &$x) + 1);
$o->p++;
var_dump($x);
$y = &$x . "!";
var_dump($y);
