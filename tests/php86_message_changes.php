<?php
// messages php 8.6 words differently: an empty sprintf argument number,
// ArrayObject's user sorts checked by the array functions, ArrayObject's
// iterator class, stream_filter_register's class, SplFileInfo's info class,
// http_build_query's nested objects, allowed_classes names with nul bytes,
// and readonly errors naming an anonymous class
function attempt($f) {
    try { $f(); } catch (Throwable $e) { echo get_class($e), ': ', str_replace("\0", '\0', $e->getMessage()), "\n"; }
}
set_error_handler(function ($no, $msg) { echo "[$no] $msg\n"; return true; });

attempt(fn() => sprintf('%$s', 'a'));
attempt(fn() => sprintf('%0$s', 'a'));
attempt(fn() => (new ArrayObject([2, 1]))->uasort('no_such_function'));
attempt(fn() => (new ArrayIterator([2, 1]))->uksort([1, 2]));
$ao = new ArrayObject([3, 1, 2]);
$ao->uasort(fn($a, $b) => $a <=> $b);
var_dump($ao->getArrayCopy());
class NotAnIterator {}
class MyIterator implements Iterator {
    function current(): mixed { return null; } function key(): mixed { return null; }
    function next(): void {} function rewind(): void {} function valid(): bool { return false; }
}
attempt(fn() => unserialize('O:11:"ArrayObject":4:{i:0;i:0;i:1;a:0:{}i:2;a:0:{}i:3;s:10:"MyIterator";}'));
abstract class AbstractFilter extends php_user_filter {}
attempt(fn() => stream_filter_register('f1', 'AbstractFilter'));
attempt(fn() => stream_filter_register('f2', 'Countable'));
attempt(fn() => stream_filter_register('f3', 'NoSuchFilterClass'));
var_dump(stream_filter_register('f4', 'php_user_filter'));
$info = new SplFileInfo(__FILE__);
attempt(fn() => $info->getPathInfo('notaniterator'));
attempt(fn() => $info->getPathInfo('NoSuchInfoClass'));
attempt(fn() => $info->getFileInfo('NoSuchInfoClass'));
attempt(fn() => $info->getFileInfo('stdClass'));
var_dump(get_class($info->getFileInfo('SplFileObject')));
$o = new stdClass;
$o->inner = new stdClass;
$o->inner->x = 1;
var_dump(http_build_query(['a' => $o]));
attempt(fn() => unserialize('a:0:{}', ['allowed_classes' => ["bad\0name"]]));
$ro = new class { public function __construct(public readonly int $p = 1) {} };
attempt(function () use ($ro) { $ro->p = 2; });
