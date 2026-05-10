<?php
// SplObjectStorage iterating keys (objects)
$s = new SplObjectStorage();
$o1 = new stdClass; $o1->n = 1;
$o2 = new stdClass; $o2->n = 2;
$o3 = new stdClass; $o3->n = 3;
$s[$o1] = "a";
$s[$o2] = "b";
$s[$o3] = "c";

// foreach gets the object as value, integer index as key
foreach ($s as $k => $obj) echo "$k:", $obj->n, "/", $s[$obj], "|";
echo "\n";

// SplObjectStorage current/key/next
$s->rewind();
while ($s->valid()) {
    echo $s->key(), ":", $s->current()->n, "/", $s->getInfo(), "|";
    $s->next();
}
echo "\n";

// WeakReference (PHP 7.4+)
echo class_exists("WeakReference") ? "y" : "n", "\n";
$o = new stdClass;
$o->x = 42;
$ref = WeakReference::create($o);
echo $ref->get()->x, "\n"; // 42

// Throwable interface methods
try {
    throw new RuntimeException("oops", 42);
} catch (\Throwable $e) {
    echo $e->getMessage(), "|", $e->getCode(), "|", $e->getLine() > 0 ? "L>0" : "L=0", "\n";
    echo basename($e->getFile()), "\n";
    echo gettype($e->getTrace()), ":", count($e->getTrace()) >= 0 ? "ok" : "no", "\n";
    echo gettype($e->getTraceAsString()), "\n";
}

// Custom exception with parent message
class MyException extends Exception {
    public function __construct(string $msg, public readonly string $detail = "") {
        parent::__construct($msg);
    }
}
try { throw new MyException("hi", "extra"); } catch (MyException $e) {
    echo $e->getMessage(), "/", $e->detail, "\n";
}

// Custom hierarchy
class AppException extends Exception {}
class NotFound extends AppException {}
class Forbidden extends AppException {}

try { throw new NotFound("nope"); } catch (AppException $e) {
    echo get_class($e), ":", $e->getMessage(), "\n";
}

// catch (X|Y $e)
try { throw new NotFound("a"); } catch (NotFound|Forbidden $e) { echo "caught:", get_class($e), "\n"; }
try { throw new Forbidden("b"); } catch (NotFound|Forbidden $e) { echo "caught:", get_class($e), "\n"; }
try { throw new RuntimeException("c"); } catch (NotFound|Forbidden $e) { echo "no\n"; } catch (RuntimeException $e) { echo "rt:", $e->getMessage(), "\n"; }

// catch with no var
try { throw new Exception("v"); } catch (Exception) { echo "caught-novar\n"; }

// Error vs Exception
echo (new TypeError) instanceof \Error ? "y" : "n", "\n";
echo (new TypeError) instanceof \Exception ? "y" : "n", "\n";
echo (new TypeError) instanceof \Throwable ? "y" : "n", "\n";
echo (new Exception) instanceof \Error ? "y" : "n", "\n";
echo (new Exception) instanceof \Throwable ? "y" : "n", "\n";
echo (new \DivisionByZeroError) instanceof \ArithmeticError ? "y" : "n", "\n";
echo (new \ArithmeticError) instanceof \Error ? "y" : "n", "\n";
echo (new \LogicException) instanceof \Exception ? "y" : "n", "\n";
echo (new \RuntimeException) instanceof \Exception ? "y" : "n", "\n";
echo (new \BadMethodCallException) instanceof \BadFunctionCallException ? "y" : "n", "\n";
echo (new \BadFunctionCallException) instanceof \LogicException ? "y" : "n", "\n";

// finally with re-throw
function withRethrow(): int {
    try {
        throw new RuntimeException("orig");
    } catch (\Exception $e) {
        throw new LogicException("wrapped", 0, $e);
    } finally {
        echo "fin|";
    }
}
try { withRethrow(); } catch (\LogicException $e) {
    echo $e->getMessage(), "<-", $e->getPrevious()->getMessage(), "\n";
}

// catch hierarchy
try { throw new LogicException("l"); } catch (\Exception $e) { echo "exc:", get_class($e), "\n"; }
try { throw new TypeError("t"); } catch (\Throwable $e) { echo "thr:", get_class($e), "\n"; }

// uncaught propagation through method
class Service {
    public function run(): void { throw new RuntimeException("svc"); }
}
try {
    (new Service)->run();
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "method-throw:", $e->getMessage(), "\n";
}

// caught in nested try
function nested() {
    try {
        throw new LogicException("inner");
    } catch (RuntimeException $e) {
        return "wrong";
    }
}
try { nested(); } catch (\LogicException $e) { echo "outer:", $e->getMessage(), "\n"; }
