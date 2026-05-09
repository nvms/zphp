<?php
// clone with private/protected props
class Foo {
    public int $a = 1;
    protected int $b = 2;
    private int $c = 3;
    public function dump() { return [$this->a, $this->b, $this->c]; }
}
$f = new Foo;
$f2 = clone $f;
$f2->a = 99;
print_r($f->dump());
print_r($f2->dump());

// __clone
class Box {
    public function __construct(public int $v, public array $tags = []) {}
    public function __clone(): void {
        $this->v++;
        $this->tags[] = "cloned";
    }
}
$b = new Box(10, ["x"]);
$b2 = clone $b;
print_r([$b->v, $b->tags]);
print_r([$b2->v, $b2->tags]);

// deep clone (objects nested)
class Inner { public int $n = 0; }
class Outer { public Inner $i; public function __construct() { $this->i = new Inner; } }
$o = new Outer;
$o->i->n = 5;
$o2 = clone $o;
$o2->i->n = 99;
echo $o->i->n, " ", $o2->i->n, "\n"; // PHP shallow: both 99

// __clone with deep
class Outer2 {
    public Inner $i;
    public function __construct() { $this->i = new Inner; }
    public function __clone(): void { $this->i = clone $this->i; }
}
$o = new Outer2;
$o->i->n = 5;
$o2 = clone $o;
$o2->i->n = 99;
echo $o->i->n, " ", $o2->i->n, "\n"; // 5 99

// instanceof with class string
class A {} class B extends A {}
$cn = "A";
$a = new A;
var_dump($a instanceof $cn);
$cn = "B";
var_dump($a instanceof $cn);
$cn = A::class;
var_dump((new B) instanceof $cn);

// instanceof through trait/interface
interface ILike {}
trait TLike { public function ping(): string { return "ping"; } }
class M implements ILike { use TLike; }
$m = new M;
var_dump($m instanceof ILike);
echo $m->ping(), "\n";

// switch with type juggling
function which($v) {
    switch ($v) {
        case 0: return "zero";
        case "0": return "str-zero"; // never reached: 0 == "0" but PHP picks first match
        case 1: return "one";
        case true: return "true";
        default: return "default";
    }
}
echo which(0), " ", which(1), " ", which("hello"), " ", which(true), "\n";

// foreach by-ref over array of objects
class N { public int $v = 0; }
$arr = [new N, new N, new N];
foreach ($arr as &$x) $x->v = 99;
unset($x);
foreach ($arr as $x) echo $x->v, " ";
echo "\n";

// foreach over generator already consumed
function gen() { yield 1; yield 2; yield 3; }
$g = gen();
foreach ($g as $v) echo $v, " ";
echo "| ";
try { foreach ($g as $v) echo $v, " "; echo "no err\n"; } catch (Exception $e) { echo "closed-gen\n"; }

// Generator::getReturn after completion
function genReturn() { yield 1; yield 2; return "done"; }
$g = genReturn();
foreach ($g as $v) {}
echo $g->getReturn(), "\n";

// Generator getReturn before completion - throws
function genIncomplete() { yield 1; yield 2; }
$g = genIncomplete();
$g->current();
try { $g->getReturn(); echo "no err\n"; } catch (Exception $e) { echo "ge\n"; } catch (Error $e) { echo "ge2\n"; }

// Fiber resume after terminated
$f = new Fiber(function() { Fiber::suspend("a"); return "done"; });
echo $f->start(), "\n";
echo $f->resume("ignore"), "\n";
echo var_export($f->getReturn(), true), "\n";
echo $f->isTerminated() ? "term" : "not", "\n";
try { $f->resume("again"); echo "no err\n"; } catch (\FiberError $e) { echo "fe\n"; } catch (Error $e) { echo "fe2\n"; }

// IteratorIterator wrap of array iterator
$ii = new IteratorIterator(new ArrayIterator([1, 2, 3]));
$ii->rewind();
while ($ii->valid()) { echo $ii->current(), " "; $ii->next(); }
echo "\n";

// spl_autoload_register multiple
$tracker = [];
spl_autoload_register(function($n) use (&$tracker) { $tracker[] = "L1:$n"; });
spl_autoload_register(function($n) use (&$tracker) { $tracker[] = "L2:$n"; });
$loaders = spl_autoload_functions();
echo "count=", count($loaders), "\n";
class_exists("NonExistent_XYZ");
print_r($tracker);

// date diff over leap years
$d1 = new DateTime('2020-02-29'); // leap
$d2 = new DateTime('2024-02-29'); // leap
$diff = $d1->diff($d2);
echo "$diff->y-$diff->m-$diff->d days=$diff->days\n";

$d1 = new DateTime('2019-03-01');
$d2 = new DateTime('2020-02-29');
$diff = $d1->diff($d2);
echo "$diff->y-$diff->m-$diff->d days=$diff->days\n";

// DateTime add over month boundary
$d = new DateTime('2024-01-31');
$d->add(new DateInterval('P1M'));
echo $d->format('Y-m-d'), "\n"; // 2024-03-02

$d = new DateTime('2023-02-28');
$d->add(new DateInterval('P1Y'));
echo $d->format('Y-m-d'), "\n"; // 2024-02-28

// str_word_count format=2 (positions)
print_r(str_word_count("The quick brown fox", 2));
print_r(str_word_count("Hello", 2));
