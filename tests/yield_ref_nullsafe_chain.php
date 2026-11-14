<?php
// a by-reference generator can't yield a nullsafe chain: php refuses the
// script when it compiles it
function &ok($object) {
    yield $object->y;
}
function &test($object) {
    yield $object->y?->y;
}
