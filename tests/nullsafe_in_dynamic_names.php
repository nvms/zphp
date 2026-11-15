<?php
// a nullsafe chain inside a dynamic property name ends there, and an empty
// static property name is undeclared
class Test { public static $x = 5; }
$null = null;
try { var_dump(Test::${$null?->foo}); } catch (Error $e) { echo $e->getMessage(), "\n"; }
$n = "x"; var_dump(Test::${$n});
try { Test::${$null?->foo}->bar; } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(isset(Test::${$null?->foo}));
try { var_dump((new stdClass)->{null?->x}->y ?? "none"); } catch (Error $e) { echo $e->getMessage(), "\n"; }
$o = new stdClass;
$o->{""} = 1;
var_dump($o->{null?->x});
