<?php
// array_chunk(0) ValueError
try { array_chunk([1,2,3], 0); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { array_chunk([1,2,3], -1); echo "no\n"; } catch (\ValueError $e) { echo "ve-neg\n"; }
try { array_chunk([1,2,3], -2); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

print_r(array_chunk([1,2,3,4,5], 2));
print_r(array_chunk([], 2));
print_r(array_chunk(["a"=>1,"b"=>2,"c"=>3], 2, true));

// array_combine ordering
$keys = ["a", "b", "c"];
$vals = [1, 2, 3];
$r = array_combine($keys, $vals);
foreach ($r as $k => $v) echo "$k=$v ";
echo "\n"; // a=1 b=2 c=3 (insertion order)

// keys with int values
$r = array_combine([10, 20, 30], ["x", "y", "z"]);
foreach ($r as $k => $v) echo "$k=$v ";
echo "\n";

// uksort with __invoke
class Cmp {
    public function __invoke($a, $b) { return strcmp((string)$a, (string)$b); }
}
$arr = ["banana" => 1, "apple" => 2, "cherry" => 3];
uksort($arr, new Cmp);
foreach ($arr as $k => $v) echo "$k:$v ";
echo "\n";

// uksort with [obj, method]
class Cmp2 {
    public function rev($a, $b) { return strcmp((string)$b, (string)$a); }
}
$arr = ["banana" => 1, "apple" => 2, "cherry" => 3];
uksort($arr, [new Cmp2, 'rev']);
foreach ($arr as $k => $v) echo "$k:$v ";
echo "\n";

// ReflectionMethod::getDeclaringClass for inherited
class A { public function foo(): void {} }
class B extends A { public function bar(): void {} }
class C extends B { public function baz(): void {} }

$rm = new ReflectionMethod(C::class, 'foo');
echo $rm->getDeclaringClass()->getName(), "\n"; // A
$rm = new ReflectionMethod(C::class, 'bar');
echo $rm->getDeclaringClass()->getName(), "\n"; // B
$rm = new ReflectionMethod(C::class, 'baz');
echo $rm->getDeclaringClass()->getName(), "\n"; // C

// ReflectionClass::getInterfaceNames
interface IA1 {}
interface IB1 extends IA1 {}
interface IC1 {}
class CI1 implements IB1, IC1 {}
$rc = new ReflectionClass(CI1::class);
$names = $rc->getInterfaceNames();
sort($names);
print_r($names); // IA1, IB1, IC1

class CI2 extends CI1 {}
$rc = new ReflectionClass(CI2::class);
$names = $rc->getInterfaceNames();
sort($names);
print_r($names);

// get_object_vars
class Vis {
    public int $a = 1;
    protected int $b = 2;
    private int $c = 3;
    public static int $s = 4;
}
$v = new Vis;
print_r(get_object_vars($v)); // only public from outside scope

// from inside the class
class Vis2 {
    public int $a = 1;
    protected int $b = 2;
    private int $c = 3;
    public function dump(): array { return get_object_vars($this); }
}
print_r((new Vis2)->dump()); // all instance props

// nullsafe chains
class Box { public ?Box $next = null; public int $v = 0; public function __construct(int $v) { $this->v = $v; } }
$b = new Box(1);
$b->next = new Box(2);
$b->next->next = new Box(3);

echo $b->next?->next?->v, "\n"; // 3
echo $b->next?->next?->next?->v ?? "null", "\n"; // null

$b2 = new Box(10);
echo $b2->next?->next?->v ?? "deep-null", "\n"; // deep-null

// ?? on $arr[nested] when null
$a = null;
echo $a["x"] ?? "x-null", "\n"; // x-null
$a = ["k" => null];
echo $a["k"]["x"] ?? "n-null", "\n"; // n-null

// Method call on null
$obj = null;
echo $obj?->method() ?? "obj-null", "\n";

// Static call on null - errors
try { $cls = null; $cls::method(); echo "no\n"; } catch (\Error $e) { echo "static-null\n"; }

// chained nullsafe with method
class S { public function getInner(): ?S { return null; } public function name(): string { return "S"; } }
$s = new S;
echo $s->getInner()?->name() ?? "no-inner", "\n";

// method exists
class M { public function existing(): void {} }
var_dump(method_exists(M::class, 'existing'));
var_dump(method_exists(M::class, 'nonexistent'));
var_dump(method_exists(new M, 'existing'));
try { method_exists(null, 'foo'); echo "no\n"; } catch (\TypeError $e) { echo "te-null\n"; }

// property_exists
class PE { public int $x = 1; private int $y = 2; }
var_dump(property_exists(PE::class, 'x'));
var_dump(property_exists(PE::class, 'y'));
var_dump(property_exists(PE::class, 'z'));
var_dump(property_exists(new PE, 'x'));

// interface_exists / class_exists
interface II {}
class CC {}
var_dump(interface_exists("II"));
var_dump(interface_exists("CC")); // false
var_dump(class_exists("CC"));
var_dump(class_exists("II")); // false (interface, not class)
