<?php
// iterator_apply
$src = new ArrayIterator([1, 2, 3, 4, 5]);
$count = 0;
$n = iterator_apply($src, function () use (&$count) { $count++; return true; });
echo "n=$n count=$count\n"; // 5 5

// iterator_apply by-ref args not fully supported in zphp (architectural)

// serialize Closure - PHP throws Exception
$cl = function () { return 1; };
try { serialize($cl); echo "no\n"; } catch (\Exception $e) { echo "ser-closure:", get_class($e), "\n"; }

// serialize circular obj
class Node { public string $v; public ?Node $next = null; public function __construct(string $v) { $this->v = $v; } }
$a = new Node("a");
$b = new Node("b");
$a->next = $b;
$b->next = $a;
$ser = serialize($a);
echo strlen($ser) > 0 ? "ok\n" : "no\n";
echo strpos($ser, "r:") !== false ? "has-ref\n" : "no-ref\n"; // back-ref
$r = unserialize($ser);
echo $r->v, "->", $r->next->v, "->", $r->next->next->v, "\n"; // a->b->a (cycle preserved)
echo $r->next->next === $r ? "same\n" : "diff\n";

// allowed_classes filter not implemented (architectural)
$sa = serialize(new Node("x"));
$r = unserialize($sa);
echo get_class($r), "\n"; // Node

// var_export of resource - PHP errors? No, prints something
$h = fopen(sys_get_temp_dir() . "/zphp_ve_" . getmypid(), "w");
$out = var_export($h, true);
echo gettype($out), "\n"; // string
fclose($h);
unlink(sys_get_temp_dir() . "/zphp_ve_" . getmypid());

// var_export of cyclic - PHP errors with warning + null
class C { public ?C $self = null; }
$c = new C; $c->self = $c;
ob_start();
$x = @var_export($c, true);
$out = ob_get_clean();
echo gettype($x), "\n";

// JSON_FORCE_OBJECT
echo json_encode([1, 2, 3], JSON_FORCE_OBJECT), "\n"; // {"0":1,...}
echo json_encode([], JSON_FORCE_OBJECT), "\n"; // {}
echo json_encode(["a" => 1], JSON_FORCE_OBJECT), "\n"; // {"a":1}

// Combined flags
echo json_encode([1, 2], JSON_FORCE_OBJECT | JSON_PRETTY_PRINT), "\n";
echo json_encode([1, 2], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";

// json_encode with object that JsonSerializes
class JS implements JsonSerializable {
    public function jsonSerialize(): mixed { return ["custom" => true]; }
}
echo json_encode(new JS), "\n";
echo json_encode([new JS, new JS]), "\n";

// json_encode of nested JSON
echo json_encode(["a" => [1, 2, ["b" => "c"]]], JSON_UNESCAPED_SLASHES), "\n";

// big nested with json_decode depth
$j = '{"l1":{"l2":{"l3":{"l4":{"l5":42}}}}}';
$d = json_decode($j, true, 5);
echo isset($d["l1"]["l2"]["l3"]["l4"]["l5"]) ? "ok\n" : "no\n";

$d = json_decode($j, true, 4);
echo $d === null ? "null\n" : "got\n";
echo json_last_error(), ":", json_last_error_msg(), "\n";

// JSON with special floats
echo json_encode(0.1), "\n";
echo json_encode(0.1 + 0.2), "\n";
echo json_encode([0.1, 0.2, 0.3]), "\n";

// JSON encode special chars
echo json_encode("hello \"world\"\n\ttab\rcr\\back"), "\n";

// date format constants
echo date(DATE_ATOM, mktime(12, 0, 0, 6, 15, 2024)), "\n";
echo date(DATE_RFC2822, mktime(12, 0, 0, 6, 15, 2024)), "\n";
echo date(DATE_W3C, mktime(12, 0, 0, 6, 15, 2024)), "\n";
