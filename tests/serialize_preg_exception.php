<?php
// custom __serialize / __unserialize
class Vec {
    public function __construct(public int $x = 0, public int $y = 0) {}
    public function __serialize(): array { return ['v' => "$this->x,$this->y"]; }
    public function __unserialize(array $d): void {
        [$x, $y] = explode(',', $d['v']);
        $this->x = (int)$x;
        $this->y = (int)$y;
    }
}
$v = new Vec(3, 4);
$s = serialize($v);
echo $s, "\n";
$v2 = unserialize($s);
echo "$v2->x,$v2->y\n";

// Serializable interface (deprecated but still works in PHP 8.x)
// skipped - deprecated and zphp may handle it differently

// preg_quote
echo preg_quote("hello.world"), "\n";
echo preg_quote("a.b/c", "/"), "\n";
echo preg_quote("$10.50"), "\n";
echo preg_quote("[]^()\\.+*?-"), "\n";

// preg_replace_callback with named groups
$out = preg_replace_callback(
    '/(?<key>\w+)=(?<val>\d+)/',
    fn($m) => $m['key'] . ':' . ($m['val'] * 2),
    "a=1 b=2 c=3"
);
echo $out, "\n";

// preg_replace with array search and replace
echo preg_replace(['/a/', '/b/'], ['X', 'Y'], 'aabb'), "\n";
echo preg_replace(['/a/', '/b/', '/c/'], ['1', '2'], 'abc'), "\n"; // 3rd replaces with empty
print_r(preg_replace('/\d+/', 'N', ['12 cats', '3 dogs']));

// array_diff_assoc strict (no, array_diff_assoc isn't strict, just key+value matched)
print_r(array_diff_assoc(['a' => 1, 'b' => 2, 'c' => 3], ['a' => 1, 'b' => '2'])); // b: int 2 vs string '2' - PHP loose

// str_pad with too-long fill
echo str_pad("x", 10, "abcdefghi"), "|\n"; // fill cycles to fit 9 chars
echo str_pad("x", 10, "abc"), "|\n";
echo str_pad("xx", 5, "abcdefghij"), "|\n"; // fill truncated

// str_repeat with negative
try { $r = str_repeat("a", -1); echo "no err\n"; } catch (ValueError $e) { echo "v\n"; }

// exception chaining $previous
try {
    try { throw new RuntimeException("inner"); }
    catch (RuntimeException $e) { throw new LogicException("outer", 0, $e); }
} catch (LogicException $e) {
    echo $e->getMessage(), "\n";
    $prev = $e->getPrevious();
    echo $prev ? get_class($prev) . ":" . $prev->getMessage() : "no prev", "\n";
}

// nested exception chain
try {
    try {
        try { throw new ValueError("L0"); }
        catch (ValueError $e) { throw new RuntimeException("L1", 0, $e); }
    } catch (RuntimeException $e) { throw new LogicException("L2", 0, $e); }
} catch (LogicException $e) {
    $cur = $e;
    while ($cur) {
        echo get_class($cur), ":", $cur->getMessage(), "\n";
        $cur = $cur->getPrevious();
    }
}

// error handler chain
$tracked = [];
set_error_handler(function($n, $m) use (&$tracked) { $tracked[] = "outer:$m"; return true; });
set_error_handler(function($n, $m) use (&$tracked) { $tracked[] = "inner:$m"; return true; });
trigger_error("test1", E_USER_WARNING);
restore_error_handler();
trigger_error("test2", E_USER_WARNING);
restore_error_handler();
print_r($tracked);

// get_object_vars on enum
enum Status: string { case Active = 'a'; case Off = 'o'; }
print_r(get_object_vars(Status::Active));

// ReflectionEnumUnitCase
enum Direction { case Up; case Down; }
$rc = new ReflectionEnum(Direction::class);
foreach ($rc->getCases() as $case) {
    echo get_class($case), ":", $case->getName(), "\n";
}

// preg_replace flags - x mode
echo preg_replace('/(?x)
    \d+   # digits
    \s+   # space
/', 'N', "12   cats"), "\n";

// preg_match_all with PREG_SET_ORDER
$s = "a=1 b=2 c=3";
preg_match_all('/(\w+)=(\d+)/', $s, $m, PREG_SET_ORDER);
print_r($m);
preg_match_all('/(\w+)=(\d+)/', $s, $m, PREG_PATTERN_ORDER);
print_r($m);
preg_match_all('/(?P<key>\w+)=(?P<val>\d+)/', $s, $m, PREG_SET_ORDER);
print_r($m);
