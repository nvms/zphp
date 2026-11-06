<?php
// internal functions, methods and constants php marks #[\Deprecated] warn on
// use, naming what declares them; reflection reports them
error_reporting(E_ALL);
set_error_handler(function ($level, $message) {
    echo "[$level] $message\n";
    return true;
});

utf8_encode("a");
lcg_value();
mt_srand(1, MT_RAND_PHP);
$r = new ReflectionProperty('Exception', 'message');
$r->setAccessible(true);
$s = new SplObjectStorage;
$o = new stdClass;
$s->attach($o);
var_dump($s->contains($o));
$s->detach($o);
class MyStorage extends SplObjectStorage {}
(new MyStorage)->attach($o);
echo E_STRICT, "\n", DATE_RFC7231, "\n", DateTime::RFC7231, "\n", DateTimeImmutable::RFC7231, "\n";
echo constant('E_STRICT'), "\n";

var_dump(
    (new ReflectionFunction('utf8_encode'))->isDeprecated(),
    (new ReflectionFunction('strlen'))->isDeprecated(),
    (new ReflectionMethod('SplObjectStorage', 'attach'))->isDeprecated(),
    (new ReflectionMethod('SplObjectStorage', 'offsetSet'))->isDeprecated(),
    (new ReflectionClassConstant('DateTimeInterface', 'RFC7231'))->isDeprecated(),
    (new ReflectionClassConstant('DateTimeInterface', 'ATOM'))->isDeprecated(),
    (new ReflectionConstant('E_STRICT'))->isDeprecated(),
    (new ReflectionConstant('E_ALL'))->isDeprecated(),
);

// user constants declared deprecated on interfaces and parents
interface Base { #[\Deprecated(message: "use NEWER")] const OLD = 1; }
interface Child extends Base {}
class Impl implements Child {}
class P { #[\Deprecated(since: "2.0")] const X = 2; const Y = 3; }
class Q extends P {}
echo Base::OLD, Impl::OLD, Q::X, Q::Y, "\n";
enum E { #[\Deprecated] case A; case B; }
var_dump(E::A, E::B);

// a handler that throws stops the call
set_error_handler(function ($level, $message) { throw new ErrorException($message); });
try {
    utf8_decode("x");
    echo "not reached\n";
} catch (ErrorException $e) {
    echo "caught: ", $e->getMessage(), "\n";
}
