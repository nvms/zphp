<?php
// a native method's by-reference parameter given as a named argument is
// written back like a positional one
$f = new SplFileObject(__FILE__);
$wouldBlock = 5;
var_dump($f->flock(LOCK_SH, wouldBlock: $wouldBlock));
var_dump($wouldBlock);
$f->flock(LOCK_UN);

$positional = 5;
$f->flock(LOCK_SH, $positional);
var_dump($positional);
$f->flock(LOCK_UN);

function inner(SplFileObject $f) {
    $local = 'unset';
    $f->flock(operation: LOCK_SH, wouldBlock: $local);
    var_dump($local);
    $f->flock(LOCK_UN);
}
inner($f);
