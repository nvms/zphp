<?php
// recursive yield from
function range_gen(int $a, int $b): Generator {
    if ($a > $b) return;
    yield $a;
    yield from range_gen($a + 1, $b);
}
foreach (range_gen(1, 5) as $v) echo "$v ";
echo "\n";

// nested yield from with depth-3
function leaf(): Generator { yield "leaf"; }
function mid(): Generator { yield "midA"; yield from leaf(); yield "midB"; }
function root(): Generator { yield "rootA"; yield from mid(); yield "rootB"; }
foreach (root() as $v) echo "$v ";
echo "\n";

// generator return array via getReturn
function withReturn(): Generator {
    yield 1; yield 2; yield 3;
    return ["status" => "ok", "count" => 3];
}
$g = withReturn();
foreach ($g as $v) echo "$v ";
echo "|", json_encode($g->getReturn()), "\n";

// generator return via yield from inner
function inner(): Generator { yield "i1"; yield "i2"; return "inner-done"; }
function outer(): Generator {
    $r = yield from inner();
    yield "got:$r";
    return "outer-done";
}
$g = outer();
foreach ($g as $v) echo "$v ";
echo "|", $g->getReturn(), "\n";

// infinite generator with break
function infinite(): Generator {
    $i = 0;
    while (true) yield $i++;
}
$count = 0;
foreach (infinite() as $v) {
    if ($v >= 5) break;
    $count++;
}
echo $count, "\n";

// ArrayObject offsetExists for null-set keys
$ao = new ArrayObject();
$ao["a"] = null;
$ao["b"] = 1;
echo isset($ao["a"]) ? "y" : "n", "|"; // n (PHP isset returns false for null)
echo $ao->offsetExists("a") ? "y" : "n", "|"; // y (offsetExists checks key presence)
echo isset($ao["b"]) ? "y" : "n", "|";
echo $ao->offsetExists("c") ? "y" : "n", "\n";

// SplFixedArray serialize round-trip
$fa = new SplFixedArray(3);
$fa[0] = "x"; $fa[1] = 1; $fa[2] = null;
$s = serialize($fa);
$r = unserialize($s);
echo get_class($r), ":", $r->getSize(), ":", $r[0], ":", $r[1], ":", var_export($r[2], true), "\n";

// SplPriorityQueue clone
$pq = new SplPriorityQueue();
$pq->insert("a", 1); $pq->insert("b", 2); $pq->insert("c", 3);
$copy = clone $pq;
echo $pq->extract(), $copy->extract(), "\n"; // c, c
echo $pq->count(), "|", $copy->count(), "\n"; // 2, 2

// SplObjectStorage serialize
$s = new SplObjectStorage();
$o1 = new stdClass; $o1->v = 1;
$o2 = new stdClass; $o2->v = 2;
$s[$o1] = "info1";
$s[$o2] = "info2";
$serialized = serialize($s);
$r = unserialize($serialized);
echo get_class($r), ":", $r->count(), "\n";
foreach ($r as $obj) echo $obj->v, ":", $r->getInfo(), "|";
echo "\n";

// json_decode JSON_BIGINT_AS_STRING
$big = '{"id": 123456789012345678901234567890, "n": 5}';
$d = json_decode($big);
echo gettype($d->id), ":", gettype($d->n), "\n"; // float|double, int
$d2 = json_decode($big, false, 512, JSON_BIGINT_AS_STRING);
echo gettype($d2->id), ":", $d2->id, ":", gettype($d2->n), "\n"; // string

// base64_decode strict invalid chars
var_dump(base64_decode("AB!CD$%", true)); // false (invalid char with strict)
var_dump(base64_decode("AB!CD$%", false)); // works (lenient)
var_dump(base64_decode("AGVsbG8=", true)); // valid binary

// Phar test skipped: depends on PHP ini phar.readonly which is often locked on locally

// json edge: trailing newline
echo json_encode(["a" => 1]), "|\n";
echo json_encode([], JSON_FORCE_OBJECT), "\n"; // {}
echo json_encode(new stdClass), "\n"; // {}
echo json_encode(["a"], JSON_FORCE_OBJECT), "\n"; // {"0":"a"}

// json_decode with depth
$nested = '{"a":{"b":{"c":{"d":1}}}}';
var_dump(json_decode($nested, true, 5));
var_dump(json_decode($nested, true, 3));
