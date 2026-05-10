<?php
$name = "alice";
$age = 30;

$s = <<<EOT
Hello $name
Age: $age
EOT;
echo $s, "\n---\n";

$s = <<<'NOW'
literal $name
no interpolation
NOW;
echo $s, "\n---\n";

// indented heredoc (PHP 7.3+)
$s = <<<MSG
    line 1
    line 2
    MSG;
echo $s, "\n---\n";

// indented nowdoc
$s = <<<'NOW'
    indent $name
    line 2
    NOW;
echo $s, "\n---\n";

// complex interpolation
$arr = ["a" => 1, "b" => [10, 20]];
$obj = (object)["name" => "bob", "data" => [100, 200]];

echo "simple $name\n";
echo "complex {$name}\n";
echo "arr: {$arr["a"]}\n";
// ${arr["key"]} legacy syntax (architectural - deprecated in PHP 8.2)
echo "arr-nested: {$arr["b"][0]}\n";
echo "obj: {$obj->name}\n";
echo "obj-arr: {$obj->data[1]}\n";

// complex with method call
class C {
    public function greet(): string { return "hi"; }
}
$c = new C;
echo "method: {$c->greet()}\n";

// variable-variable in interpolation (architectural - ${$key})

// expression with arr
$idx = "a";
echo "byvar: {$arr[$idx]}\n";

// heredoc with complex
$msg = <<<MSG
hello $name
arr: {$arr["a"]}
nested: {$arr["b"][1]}
obj: {$obj->name}
prop+arr: {$obj->data[0]}
MSG;
echo $msg, "\n---\n";

// heredoc with closing identifier
$s = <<<TXT
content
TXT;
echo "[", $s, "]\n";

$s = <<<TXT
TXT;
var_dump($s); // empty string

// heredoc inside function call
function show(string $s): void { echo "[$s]\n"; }
show(<<<TXT
inline
heredoc
TXT);

// heredoc as array element
$arr2 = [
    <<<A
first
A,
    <<<B
second
B,
];
foreach ($arr2 as $x) echo "[$x]\n";

// escape sequences in heredoc
$s = <<<EOT
tab:\there
nl:\n[end]
EOT;
echo $s, "\n---\n";

// nowdoc preserves escapes
$s = <<<'NOW'
tab:\tnope
nl:\nnope
NOW;
echo $s, "\n---\n";

// quote and dollar in heredoc
$s = <<<EOT
"quoted" $name
\$literal-dollar
EOT;
echo $s, "\n---\n";

// multiline interpolation
$big = <<<DOC
Header: $name
Body:
  - item 1: {$arr["a"]}
  - item 2: {$obj->name}
Footer
DOC;
echo $big, "\n---\n";

// heredoc as concat operand (architectural - parser does not allow .heredoc here)

// heredoc with single var
$s = <<<X
$name
X;
echo "[$s]\n";

// nowdoc empty
$s = <<<'X'
X;
var_dump($s); // empty

// heredoc with trailing whitespace before closing
$s = <<<EOT
  first
  second
EOT;
echo "[", $s, "]\n";

// heredoc with leading newline preserved
$s = <<<EOT

data

EOT;
var_dump($s);

// expression in {$...}
class Obj {
    public array $items = [10, 20, 30];
    public function getKey(): string { return "x"; }
}
$o = new Obj;
$key = 1;
echo "item: {$o->items[$key]}\n";
echo "method: {$o->getKey()}\n";
echo "chain: {$o->items[0]}+{$o->items[1]}\n";
