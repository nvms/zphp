<?php
// Reflection
class Animal {
    public string $name;
    protected int $age = 0;
    private string $secret = "x";
    const KIND = "animal";
    public function __construct(string $name) { $this->name = $name; }
    public function speak(): string { return "..."; }
    private function _internal(): void {}
    protected static function build(): static { return new static("anon"); }
}

class Dog extends Animal {
    public string $breed = "mutt";
    const SOUND = "woof";
    public function speak(): string { return "woof"; }
    public function fetch(int $count = 1): string { return str_repeat("fetch ", $count); }
}

$rc = new ReflectionClass(Dog::class);
echo $rc->getName(), "\n";
echo $rc->getParentClass()->getName(), "\n";
echo count($rc->getMethods()), "\n";
foreach ($rc->getMethods() as $m) echo $m->getName(), " ";
echo "\n";
foreach ($rc->getMethods(ReflectionMethod::IS_PUBLIC) as $m) echo $m->getName(), " ";
echo "\n";
foreach ($rc->getProperties() as $p) echo $p->getName(), " ";
echo "\n";
foreach ($rc->getConstants() as $name => $val) echo "$name=$val ";
echo "\n";
print_r(array_keys($rc->getConstants()));
echo $rc->hasConstant("SOUND") ? "yes" : "no", "\n";
echo $rc->hasConstant("KIND") ? "yes" : "no", "\n"; // inherited
echo $rc->hasConstant("MISSING") ? "yes" : "no", "\n";
echo $rc->getConstant("KIND"), "\n";

// ReflectionMethod
$rm = $rc->getMethod("fetch");
echo $rm->getName(), "\n";
echo $rm->getNumberOfParameters(), "\n";
echo $rm->getNumberOfRequiredParameters(), "\n";
$rt = $rm->getReturnType();
echo $rt ? (string)$rt : "no-type", "\n";
foreach ($rm->getParameters() as $p) echo $p->getName(), " ";
echo "\n";

// ReflectionFunction
function add(int $a, int $b = 0): int { return $a + $b; }
$rf = new ReflectionFunction("add");
echo $rf->getNumberOfParameters(), "\n";
echo $rf->getNumberOfRequiredParameters(), "\n";
echo (string)$rf->getReturnType(), "\n";

// closure
$closure = function(int $x): string { return (string)$x; };
$rf = new ReflectionFunction($closure);
echo (string)$rf->getReturnType(), "\n";
echo $rf->isClosure() ? "is" : "not", "\n";

// SplPriorityQueue
$q = new SplPriorityQueue();
$q->insert("a", 1);
$q->insert("b", 5);
$q->insert("c", 3);
echo $q->extract(), "\n"; // b
echo $q->extract(), "\n"; // c
echo $q->extract(), "\n"; // a

// extract flags
$q = new SplPriorityQueue();
$q->insert("a", 1);
$q->insert("b", 5);
$q->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
print_r($q->extract());
$q->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
echo $q->extract(), "\n";

// SplObjectStorage getInfo/setInfo
$s = new SplObjectStorage();
$o1 = new stdClass; $o2 = new stdClass;
$s[$o1] = "one";
$s[$o2] = "two";
$s->rewind();
echo $s->getInfo(), "\n";
$s->setInfo("ONE");
echo $s[$o1], "\n";
$s->next();
echo $s->getInfo(), "\n";

// str_pad multibyte
echo str_pad("café", 10, "*"), "|\n"; // byte-based: pads less than chars
echo mb_str_pad("café", 10, "*"), "|\n";
echo mb_str_pad("café", 10, "ø"), "|\n";
echo mb_str_pad("café", 10, "*", STR_PAD_LEFT), "|\n";
echo mb_str_pad("café", 10, "*", STR_PAD_BOTH), "|\n";
echo mb_str_pad("héllo", 3, "*"), "|\n"; // shorter than current

// mb_substr_count
echo mb_substr_count("ababab", "ab"), "\n";
echo mb_substr_count("café café café", "café"), "\n";
echo mb_substr_count("aaaaa", "aa"), "\n"; // non-overlapping = 2
echo mb_substr_count("", "x"), "\n";
try { mb_substr_count("abc", ""); echo "no err\n"; } catch (ValueError $e) { echo "v-err\n"; }

// ctype on numeric strings
var_dump(ctype_digit("123"));
var_dump(ctype_digit(""));
var_dump(@ctype_digit(123));   // PHP 8.1+: true (treats as ASCII)
var_dump(@ctype_digit(48));    // ASCII '0' = 48
var_dump(@ctype_digit(49));    // ASCII '1'
var_dump(@ctype_alpha(65));    // 'A'
var_dump(@ctype_alnum(48));
var_dump(ctype_xdigit("ABC"));
var_dump(ctype_xdigit("XYZ"));

// get_object_vars
class Base {
    public $a = 1;
    private $b = 2;
    protected $c = 3;
    public function getInternal() { return get_object_vars($this); }
}
class Sub extends Base {
    public $d = 4;
    private $e = 5;
    public function getInternal() { return get_object_vars($this); }
}
$s = new Sub();
print_r(get_object_vars($s)); // outside: only public a + d
print_r($s->getInternal()); // inside Sub: own privates + parent public/protected (no parent private)

// array_diff with mixed types
print_r(array_diff([1, "1", 2, "2.0", 2.0], [1, "2"]));
print_r(array_diff(["a", "b", "c"], ["b"], ["c"]));
print_r(array_diff_key(["a"=>1,"b"=>2,"c"=>3], ["b"=>0], ["c"=>0]));

// array_merge with null values
print_r(array_merge(["a" => 1], ["a" => null]));
print_r(array_merge([null, null], [null]));
print_r(array_merge(["a" => null], ["a" => 1]));

// array_combine string keys
print_r(array_combine(["a", "b", "c"], [1, 2, 3]));
print_r(array_combine([1.5, 2.5], ["x", "y"])); // floats truncate to int

// array_map null callback (transpose)
print_r(array_map(null, [1, 2, 3]));
print_r(array_map(null, [1, 2, 3], ["a", "b", "c"]));
print_r(array_map(null, [1, 2], ["a", "b", "c"], ["x", "y", "z"]));
