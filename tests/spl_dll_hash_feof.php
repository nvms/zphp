<?php
// SplDoublyLinkedList iteration modes
$l = new SplDoublyLinkedList();
$l->push(1); $l->push(2); $l->push(3);
$l->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO | SplDoublyLinkedList::IT_MODE_KEEP);
foreach ($l as $v) echo "$v "; echo "|\n";

$l->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO | SplDoublyLinkedList::IT_MODE_KEEP);
foreach ($l as $v) echo "$v "; echo "|\n";

// FIFO + DELETE: empties the list
$l2 = new SplDoublyLinkedList();
$l2->push("a"); $l2->push("b"); $l2->push("c");
$l2->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO | SplDoublyLinkedList::IT_MODE_DELETE);
foreach ($l2 as $v) echo "$v ";
echo "| count=", count($l2), "\n";

// SplStack top vs pop
$s = new SplStack();
$s->push(10); $s->push(20); $s->push(30);
echo $s->top(), "|", count($s), "\n"; // 30, 3 (top doesn't remove)
echo $s->pop(), "|", count($s), "\n"; // 30, 2

// SplQueue (uses dequeue/enqueue)
$q = new SplQueue();
$q->enqueue("a"); $q->enqueue("b"); $q->enqueue("c");
echo $q->dequeue(), "\n"; // a
echo count($q), "\n"; // 2

// SplFixedArray out-of-range throws OutOfBoundsException (extends RuntimeException)
$fa = new SplFixedArray(3);
$fa[0] = "a"; $fa[1] = "b"; $fa[2] = "c";
try { echo $fa[-1], "\n"; } catch (\OutOfBoundsException $e) { echo "neg-idx\n"; }
try { echo $fa[5], "\n"; } catch (\OutOfBoundsException $e) { echo "high-idx\n"; }
try { $fa[-1] = "x"; } catch (\OutOfBoundsException $e) { echo "neg-set\n"; }

// SplObjectStorage attach with same object
$s = new SplObjectStorage();
$o = new stdClass; $o->v = 1;
$s[$o] = "first";
$s[$o] = "second"; // overwrites
echo count($s), ":", $s[$o], "\n"; // 1:second

// detach removes
$s->offsetUnset($o);
echo count($s), "\n"; // 0

// hash with wrong algo - PHP 8.4 throws ValueError (not silenceable)
try { hash("nonexistent", "data"); echo "no err\n"; } catch (\ValueError $e) { echo "hash-err\n"; }

// password_needs_rehash
$h = password_hash("secret", PASSWORD_BCRYPT, ["cost" => 4]);
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT, ["cost" => 4])); // false
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT, ["cost" => 12])); // true
var_dump(password_needs_rehash("plaintext", PASSWORD_BCRYPT)); // true

// ftruncate
$path = sys_get_temp_dir() . "/zphp_trunc.txt";
file_put_contents($path, "hello world");
$f = fopen($path, "r+");
ftruncate($f, 5);
fclose($f);
echo file_get_contents($path), "|\n"; // "hello"

ftruncate(fopen($path, "r+"), 10); // extend with NULs
echo strlen(file_get_contents($path)), "\n"; // 10
unlink($path);

// fflush
$path = sys_get_temp_dir() . "/zphp_flush.txt";
$f = fopen($path, "w");
fwrite($f, "data");
fflush($f);
echo strlen(file_get_contents($path)) > 0 ? "flushed\n" : "buffered\n";
fclose($f);
unlink($path);

// feof on closed handle - PHP 8 throws TypeError
$f = fopen("php://memory", "r");
fclose($f);
try { feof($f); echo "no err\n"; } catch (\TypeError $e) { echo "te\n"; }

// generator that throws before yield
function bad_gen() { throw new Exception("before yield"); yield 1; }
try {
    $g = bad_gen();
    $g->current();
} catch (Exception $e) {
    echo "caught:", $e->getMessage(), "\n";
}

// generator that yields then throws
function yield_then_throw() { yield 1; throw new RuntimeException("after yield"); }
$g = yield_then_throw();
echo $g->current(), "\n"; // 1
try { $g->next(); echo "no err\n"; } catch (RuntimeException $e) { echo "rt:", $e->getMessage(), "\n"; }

// iterators with break inside
function gen_inf() { for ($i = 0; ; $i++) yield $i; }
$count = 0;
foreach (gen_inf() as $v) {
    if ($v >= 3) break;
    $count++;
}
echo "looped=$count\n";

// nested iterator with break 2
foreach ([1,2,3] as $x) {
    foreach ([10,20,30] as $y) {
        if ($x === 2 && $y === 20) break 2;
        echo "$x,$y ";
    }
}
echo "\n";

// password_verify on long password (PHP 8.4 truncates at 72 for bcrypt)
$h = password_hash(str_repeat("x", 80), PASSWORD_BCRYPT);
var_dump(password_verify(str_repeat("x", 80), $h));
var_dump(password_verify(str_repeat("x", 72), $h)); // bcrypt truncates - matches
