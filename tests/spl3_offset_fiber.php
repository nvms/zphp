<?php
// SplObjectStorage offsetGet on missing
$s = new SplObjectStorage();
$o1 = new stdClass; $o1->n = 1;
$o2 = new stdClass; $o2->n = 2;
$s[$o1] = "data";

echo $s[$o1], "\n"; // data
try { echo $s[$o2], "\n"; } catch (\UnexpectedValueException $e) { echo "uve\n"; }

// SplFixedArray size 0
$fa = new SplFixedArray(0);
echo $fa->getSize(), "\n";
echo $fa->count(), "\n";
foreach ($fa as $v) echo "x";
echo "|\n";
try { echo $fa[0], "\n"; } catch (\OutOfBoundsException $e) { echo "oob\n"; }

// negative size
try { new SplFixedArray(-1); echo "no\n"; } catch (\Throwable $e) { echo "neg-size:", get_class($e), "\n"; }

// setSize to smaller
$fa = new SplFixedArray(5);
for ($i = 0; $i < 5; $i++) $fa[$i] = "v$i";
$fa->setSize(3);
echo $fa->getSize(), "\n";
foreach ($fa as $k => $v) echo "$k=$v|";
echo "\n";

// setSize to larger fills nulls
$fa->setSize(6);
for ($i = 0; $i < 6; $i++) echo var_export($fa[$i], true), "|";
echo "\n";

// ArrayObject getArrayCopy preserves order
$ao = new ArrayObject(["b" => 1, "a" => 2, "c" => 3]);
print_r($ao->getArrayCopy());
$ao->ksort();
print_r($ao->getArrayCopy());

// Generator with throw and return
function genTR() {
    try {
        yield 1;
        yield 2;
    } catch (RuntimeException $e) {
        return "caught:" . $e->getMessage();
    }
    return "normal";
}

$g = genTR();
echo $g->current(), "\n"; // 1
$g->throw(new RuntimeException("x"));
echo $g->getReturn(), "\n"; // caught:x

$g = genTR();
foreach ($g as $v) echo "$v ";
echo "|", $g->getReturn(), "\n";

// fiber double-start
$f = new Fiber(function () { return "ok"; });
$f->start();
try { $f->start(); echo "no\n"; } catch (\FiberError $e) { echo "fe-double-start\n"; }
echo $f->getReturn(), "\n";

// fiber resume after terminated
$f = new Fiber(function () {
    Fiber::suspend("a");
    return "done";
});
$f->start(); // a
$f->resume(null); // returns "done", terminated
try { $f->resume(null); echo "no\n"; } catch (\FiberError $e) { echo "fe-resume-term\n"; }
echo $f->getReturn(), "\n";

// fiber: getReturn before terminated
$f = new Fiber(function () { Fiber::suspend(); });
$f->start();
try { $f->getReturn(); echo "no\n"; } catch (\FiberError $e) { echo "fe-not-term\n"; }

// fiber: getReturn on completed
$f = new Fiber(function () { return 42; });
$f->start();
echo $f->getReturn(), "\n";

// SplStack count operations
$st = new SplStack();
echo $st->count(), "\n";
$st->push(1); $st->push(2);
echo $st->count(), "\n";

// SplQueue count
$q = new SplQueue();
echo $q->count(), "\n";

// SplObjectStorage::contains is deprecated in 8.5 (architectural)
$s = new SplObjectStorage();
$o = new stdClass;
echo isset($s[$o]) ? "y" : "n", "\n";
$s[$o] = "v";
echo isset($s[$o]) ? "y" : "n", "\n";

// ArrayIterator getArrayCopy
$ai = new ArrayIterator(["x" => 1, "y" => 2]);
print_r($ai->getArrayCopy());
