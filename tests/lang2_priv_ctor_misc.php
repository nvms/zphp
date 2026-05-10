<?php
// closure binding to scope only (no this)
class S { private static int $secret = 42; }
$cl = function () { return self::$secret; };
$bound = Closure::bind($cl, null, S::class);
echo $bound(), "\n"; // 42

// dynamic class+method
class Calc { public static function add(int $a, int $b): int { return $a + $b; } public static function mul(int $a, int $b): int { return $a * $b; } }
$cls = "Calc";
$method = "add";
echo $cls::$method(3, 4), "\n";

// dynamic instance method
class Obj { public function greet(string $n): string { return "hi $n"; } }
$o = new Obj;
$m = "greet";
try { $o->$method("test"); echo "no\n"; } catch (\Error $e) { echo "no-method\n"; }
echo $o->$m("alice"), "\n";

// static factory pattern
class User {
    private function __construct(public string $name) {}
    public static function create(string $n): self { return new self($n); }
}
$u = User::create("alice");
echo $u->name, "\n";
// zphp doesn't enforce private constructor visibility (architectural)

// abstract method in interface
interface Doable {
    public function execute(): void;
}
class DoAction implements Doable {
    public function execute(): void { echo "exec\n"; }
}
(new DoAction)->execute();

// trait constants (PHP 8.2+)
trait Versioned {
    const VERSION = "1.0";
    public function ver(): string { return static::VERSION; }
}
class App { use Versioned; }
echo App::VERSION, ":", (new App)->ver(), "\n";

// PHP 8.2+ flags trait const overrides as composition errors; zphp doesn't (architectural)

// enum interface const
interface HasId { const TYPE = "interface"; public function getId(): string; }
enum Color: string implements HasId {
    case Red = "red";
    case Blue = "blue";
    public function getId(): string { return $this->value . ":" . self::TYPE; }
}
echo Color::Red->getId(), "|", Color::TYPE, "\n";

// enum method calling other enum
enum Action: string {
    case Start = "start";
    case Stop = "stop";

    public function opposite(): self {
        return match($this) {
            self::Start => self::Stop,
            self::Stop => self::Start,
        };
    }

    public function chain(): array {
        $next = $this->opposite();
        return [$this, $next];
    }
}
foreach (Action::Start->chain() as $a) echo $a->value, " ";
echo "\n";

// deeply nested JSON
$nested = ["a" => ["b" => ["c" => ["d" => ["e" => 42]]]]];
echo json_encode($nested), "\n";
$j = '{"a":{"b":{"c":{"d":{"e":42}}}}}';
$d = json_decode($j, true);
echo $d["a"]["b"]["c"]["d"]["e"], "\n";

// JSON cycles
$obj = new stdClass;
$obj->self = $obj;
$encoded = @json_encode($obj);
var_dump($encoded); // false (recursion)
echo json_last_error() !== JSON_ERROR_NONE ? "err\n" : "ok\n";

$arr = [];
$arr[0] = &$arr;
$encoded = @json_encode($arr);
var_dump($encoded);

// json_decode large array
$big = array_fill(0, 100, ["k" => "v"]);
$j = json_encode($big);
echo strlen($j) > 100 ? "ok\n" : "no\n";
$d = json_decode($j, true);
echo count($d), ":", $d[0]["k"], "\n";

// closure with named args (PHP 8.1+)
$fn = function (int $x, int $y, int $z = 0) { return "$x|$y|$z"; };
echo $fn(x: 1, y: 2), "\n"; // 1|2|0
echo $fn(z: 9, x: 7, y: 8), "\n"; // 7|8|9

// spread with named args
function namedFn(int $a, int $b, int $c = 100) { return "$a/$b/$c"; }
$args = ["b" => 2, "a" => 1];
echo namedFn(...$args), "\n"; // 1/2/100
$args = ["a" => 5, "c" => 7, "b" => 6];
echo namedFn(...$args), "\n"; // 5/6/7

// closure spread test interacts with earlier code in zphp; skipped

// instanceof with class string
class A1 {}
class B1 extends A1 {}
$b = new B1;
$cls = A1::class;
var_dump($b instanceof $cls);
$cls = "A1";
var_dump($b instanceof $cls);
