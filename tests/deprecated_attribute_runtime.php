<?php
// php builds a #[\Deprecated] attribute when its deprecation fires: the
// message may name constants defined later or itself, a scalar becomes a
// string, and a trait warns where it is used
define('REASON', 'use ' . strtolower('NEWER') . '()');

#[\Deprecated(REASON, since: SINCE)]
function old_api() {}
const SINCE = '2.' . 1;

#[\Deprecated(1234)]
function numbered() {}

#[\Deprecated(SELF_REFERENCE)]
const SELF_REFERENCE = 'names itself';

#[\Deprecated]
const PLAIN_DEPRECATED = 'plain';
#[\Deprecated(PLAIN_DEPRECATED)]
const USES_PLAIN = 1;

class Box {
    #[\Deprecated(self::OLD)]
    const OLD = 'from the class';
    #[\Deprecated(message: 'the ' . self::class . ' way')]
    function method() {}
}

#[\Deprecated('stop using it', since: '3.0')]
trait OldTrait {}
trait Wrapper { use OldTrait; }
class UsesOld { use OldTrait; }
class UsesWrapper { use Wrapper; }

old_api();
numbered();
echo SELF_REFERENCE, "\n";
echo USES_PLAIN, "\n";
echo Box::OLD, "\n";
(new Box)->method();

$d = new Deprecated(42);
var_dump($d->message);
try { $d->__construct('again'); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { new Deprecated([]); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
