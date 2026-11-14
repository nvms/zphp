<?php
// a #[\Deprecated] or #[\NoDiscard] __call/__callStatic run for a missing
// method is named after that method, as php's call trampoline is; called by
// its own name it keeps its own
class Base {
    #[\Deprecated]
    #[\NoDiscard]
    function __call($name, $args) { return $name; }

    #[\Deprecated("use other()")]
    static function __callStatic($name, $args) { return $name; }
}
class Child extends Base {}

$o = new Child;
$o->missing();
$o->__call('direct', []);
Child::staticMissing();
Base::__callStatic('direct', []);
echo call_user_func([$o, 'viaCallback']), "\n";
$r = $o->used();
echo $r, "\n";
(void) $o->voided();
