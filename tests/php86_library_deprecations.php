<?php
// php 8.6's deprecations and stricter argument checks in the library:
// objects where arrays are meant, define()'s third argument, is_a() with a
// string, reflection writes and calls on the wrong object, session handlers
// without create_sid() or validateId(), constants named _, let or is, and nul
// bytes in environment, stat and query strings
ob_start();
set_error_handler(function ($no, $msg, $file, $line) {
    echo "[$no] $msg\n";
    return true;
});
function attempt($f) {
    try { $f(); } catch (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
}

$o = new stdClass;
$o->a = 1;
array_walk($o, function (&$v) { $v++; });
array_walk_recursive($o, function (&$v) { $v++; });
var_dump($o->a);
var_dump(http_build_query($o));
$m = new stdClass;
$m->s = 'text';
$nested = ['x' => 'y', 'o' => $m];
var_dump(mb_convert_variables('UTF-8', 'UTF-8', $m, $nested));
var_dump(get_class(deflate_init(ZLIB_ENCODING_DEFLATE, new ArrayObject([]))));
var_dump(get_class(inflate_init(ZLIB_ENCODING_DEFLATE, new ArrayObject([]))));
$fp = fopen('php://memory', 'w+');
var_dump(is_resource(stream_filter_append($fp, 'zlib.deflate', STREAM_FILTER_WRITE, new ArrayObject(['level' => 1]))));

var_dump(define('PHP86_DEFINED', 1, false), PHP86_DEFINED);
var_dump(is_a('stdClass', 'stdClass'), is_subclass_of('ArrayObject', 'Countable', false), is_a('ArrayObject', 'Countable', true));

class RA { public $x = 0; public static function s($v = 1) { return $v; } }
class RB { public $x = 0; }
$b = new RB;
(new ReflectionProperty('RA', 'x'))->setValue($b, 1);
(new ReflectionProperty('RA', 'x'))->setRawValue($b, 2);
var_dump($b->x);
var_dump((new ReflectionMethod('RA', 's'))->invoke(new RA, 3));
var_dump((new ReflectionMethod('RA', 's'))->invokeArgs(new RA, [4]));
var_dump((new ReflectionMethod('RA', 's'))->invoke(null, 5));

class PartialHandler implements SessionHandlerInterface {
    function open($p, $n): bool { return true; }
    function close(): bool { return true; }
    function read($i): string|false { return ''; }
    function write($i, $d): bool { return true; }
    function destroy($i): bool { return true; }
    function gc($m): int|false { return 0; }
}
class FullHandler extends PartialHandler implements SessionIdInterface, SessionUpdateTimestampHandlerInterface {
    function create_sid(): string { return 'x'; }
    function validateId($id): bool { return true; }
    function updateTimestamp($id, $data): bool { return true; }
}
var_dump(session_set_save_handler(new PartialHandler, false));
var_dump(session_set_save_handler(new FullHandler, false));

define('_', 1);
define('LET', 2);
define('N\is', 3);
define('N\IS', 4);
var_dump(constant('_'), LET);

attempt(fn() => getenv("A\0B"));
attempt(fn() => putenv("A\0B=1"));
attempt(fn() => stat("a\0b"));
attempt(fn() => is_file("a\0b"));
attempt(fn() => filesize("a\0b"));
attempt(fn() => file_exists("a\0b"));
attempt(fn() => is_dir("a\0b"));
attempt(fn() => filemtime("a\0b"));
attempt(function () { parse_str("a\0b=1", $out); });

class RT { const T = true; const F = false; }
echo new ReflectionClassConstant('RT', 'T'), new ReflectionClassConstant('RT', 'F');
const PHP86_TRUE = true;
echo new ReflectionConstant('PHP86_TRUE');

eval('class NsConst { const namespace = 1; } interface NsConstI { const NAMESPACE = 2; }');
eval('function readonly() {} function LET() {}');
eval('class is {}');
echo "done\n";
