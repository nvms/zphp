<?php
// a trait method may be aliased to a keyword name
trait Ops { function list() { return 'list'; } function run() { return 'run'; } }
class Uses { use Ops { Ops::list as public foreach; list as catch; run as protected; } }
echo (new Uses)->foreach(), ' ', (new Uses)->catch(), "\n";
var_dump((new ReflectionMethod('Uses', 'run'))->isProtected());
