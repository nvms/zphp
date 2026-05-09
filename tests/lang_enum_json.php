<?php
// array_pad
print_r(array_pad([1,2,3], 5, 0));
print_r(array_pad([1,2,3], -5, 0));
print_r(array_pad([1,2,3], 2, 0));
print_r(array_pad([], 3, "x"));

// array_replace
print_r(array_replace(["a","b","c"], [1=>"X"]));
print_r(array_replace(["k"=>1,"v"=>2], ["k"=>10,"new"=>3]));

// array_replace_recursive
$base = ["a" => 1, "b" => ["x" => 10, "y" => 20], "c" => [1,2,3]];
$over = ["b" => ["y" => 99, "z" => 100], "c" => ["A"]];
print_r(array_replace_recursive($base, $over));

// range
print_r(range(1, 5));
print_r(range(1, 10, 2));
print_r(range('a', 'e'));
print_r(range(0.0, 1.0, 0.25));
print_r(range(5, 1));
print_r(range(5, 1, -1));

// compact/extract
$x = 1; $y = "two"; $z = [3];
print_r(compact("x", "y", "z"));
print_r(compact(["x", "y", "z"]));

extract(["m" => 100, "n" => 200]);
echo $m, "|", $n, "\n";

// list destructuring
[$a, $b, $c] = [10, 20, 30];
echo "$a,$b,$c\n";

["k" => $k, "v" => $v] = ["k" => 1, "v" => 2];
echo "$k,$v\n";

// list with refs
$arr = [1, 2, 3];
[&$first, , &$third] = $arr;
$first = 100; $third = 300;
print_r($arr);

// match no default
try { match(99) { 1 => "one" }; echo "no err\n"; } catch (\UnhandledMatchError $e) { echo "ume\n"; }

// throw expression
$x = 5;
$r = $x > 0 ? "pos" : throw new RuntimeException("neg");
echo $r, "\n";
try { $r = -1 > 0 ? "pos" : throw new RuntimeException("neg"); } catch (\RuntimeException $e) { echo "caught\n"; }

// throw in ??
$cfg = null;
try { $v = $cfg ?? throw new RuntimeException("missing"); echo "got\n"; } catch (\RuntimeException $e) { echo "caught2\n"; }

// never return type
function bail(string $msg): never { throw new RuntimeException($msg); }
try { bail("done"); echo "no\n"; } catch (\RuntimeException $e) { echo "ne:", $e->getMessage(), "\n"; }

// intersection types
interface IsCountable { public function size(): int; }
interface IsNamed { public function name(): string; }
class Item implements IsCountable, IsNamed { public function size(): int { return 5; } public function name(): string { return "item"; } }
function describe(IsCountable&IsNamed $thing): string { return $thing->name() . ":" . $thing->size(); }
echo describe(new Item), "\n";

// union types with Stringable
function takeStr(string|Stringable $s): string { return (string)$s; }
class S implements Stringable { public function __toString(): string { return "stringable!"; } }
echo takeStr("a"), "|", takeStr(new S), "\n";

// enums
enum Status: int { case Active = 1; case Inactive = 0; case Pending = 2; }
echo count(Status::cases()), "\n";
foreach (Status::cases() as $c) echo "$c->name=$c->value ";
echo "\n";

$s = Status::from(1);
echo $s->name, "\n";
$s = Status::tryFrom(99);
var_dump($s);
try { Status::from(99); echo "no err\n"; } catch (\ValueError $e) { echo "ve\n"; }

// ReflectionEnum
$re = new ReflectionEnum(Status::class);
echo $re->isBacked() ? "backed\n" : "no\n";
foreach ($re->getCases() as $c) echo $c->getName(), ":", $c->getBackingValue(), "|";
echo "\n";

// var_export of enum
var_export(Status::Active);
echo "\n";

// json_encode enum
echo json_encode(Status::Active), "\n";
echo json_encode([Status::Active, Status::Pending]), "\n";

// non-backed enum json
enum Color { case Red; case Blue; }
try { echo json_encode(Color::Red), "\n"; } catch (\Throwable $e) { echo "type:", get_class($e), "\n"; }

// match with enum
$desc = match($s = Status::Active) {
    Status::Active => "on",
    Status::Inactive => "off",
    Status::Pending => "wait",
};
echo $desc, "\n";

// enum implements interface
interface Hexed { public function hex(): string; }
enum Theme: string implements Hexed {
    case Light = "light";
    case Dark = "dark";
    public function hex(): string { return $this === Theme::Light ? "#fff" : "#000"; }
}
echo Theme::Light->hex(), "|", Theme::Dark->hex(), "\n";
echo Theme::Light instanceof Hexed ? "yes\n" : "no\n";

// enum const
enum Priority: int {
    const HIGH_THRESHOLD = 5;
    case Low = 1;
    case High = 10;
}
echo Priority::HIGH_THRESHOLD, "\n";

// json_decode nested
$j = '{"a":{"b":{"c":42}},"list":[1,2,3]}';
$o = json_decode($j);
echo $o->a->b->c, "|", count($o->list), "\n";
$assoc = json_decode($j, true);
echo $assoc['a']['b']['c'], "|", $assoc['list'][2], "\n";
