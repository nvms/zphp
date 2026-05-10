<?php
// basic list()
list($a, $b, $c) = [1, 2, 3];
echo "$a $b $c\n";

// short syntax
[$a, $b, $c] = [10, 20, 30];
echo "$a $b $c\n";

// fewer-values-than-vars warning (architectural - PHP emits Undefined array key)

// extra values ignored
[$a, $b] = [1, 2, 3, 4];
echo "$a $b\n";

// associative keys
["a" => $x, "b" => $y] = ["a" => "alpha", "b" => "beta", "c" => "gamma"];
echo "$x $y\n";

// mix associative and numeric not allowed in same destructure
$pair = ["x" => 1, "y" => 2];
["x" => $a, "y" => $b] = $pair;
echo "$a $b\n";

// nested destructuring
[[$a, $b], [$c, $d]] = [[1, 2], [3, 4]];
echo "$a $b $c $d\n";

// nested mixed
[$first, ["x" => $x], [3 => $third]] = [
    "f",
    ["x" => "X", "y" => "Y"],
    [0 => "z", 3 => "third-val"],
];
echo "$first $x $third\n";

// swap
$x = 1; $y = 2;
[$x, $y] = [$y, $x];
echo "$x $y\n";

// triple swap
$a = 1; $b = 2; $c = 3;
[$a, $b, $c] = [$c, $a, $b];
echo "$a $b $c\n";

// in foreach
$pairs = [[1, "a"], [2, "b"], [3, "c"]];
foreach ($pairs as [$n, $l]) echo "$n=$l ";
echo "\n";

// in foreach with key
foreach ($pairs as $i => [$n, $l]) echo "$i:$n=$l ";
echo "\n";

// foreach with assoc destructuring
$rows = [
    ["name" => "alice", "age" => 30],
    ["name" => "bob", "age" => 25],
];
foreach ($rows as ["name" => $name, "age" => $age]) echo "$name=$age ";
echo "\n";

// destructuring with explicit numeric keys
[1 => $b, 0 => $a] = [10, 20];
echo "$a $b\n";

// skip values
[, $b, , $d] = [1, 2, 3, 4];
echo "$b $d\n";

// list() vs [] are equivalent
list($a, $b) = [1, 2];
echo "$a $b\n";

// nested skip
[$first, [, , $deep]] = ["x", [1, 2, 3]];
echo "$first $deep\n";

// destructure objects via array methods (Stringable / ArrayAccess won't work directly)

// destructure into already declared
$x = "before";
[$x] = ["after"];
echo "$x\n";

// from function return
function tuple(): array {
    return [1, 2, 3];
}
[$a, $b, $c] = tuple();
echo "$a $b $c\n";

// destructure inside expression
$result = [10, 20];
[$a, $b] = $result;
$result[] = 30;
echo "$a $b cnt=", count($result), "\n";

// nested associative
$data = [
    "user" => ["name" => "alice", "id" => 1],
    "meta" => ["created" => "2025-01-01"],
];
[
    "user" => ["name" => $name, "id" => $id],
    "meta" => ["created" => $created],
] = $data;
echo "$name $id $created\n";

// destructuring with null-coalesce after
[$a, $b, $c] = [10, null, 30];
echo $a, " ", $b ?? "null", " ", $c, "\n";

// chained destructure within foreach with index
$points = [
    ["x" => 1, "y" => 2],
    ["x" => 3, "y" => 4],
    ["x" => 5, "y" => 6],
];
$xs = [];
foreach ($points as ["x" => $px]) $xs[] = $px;
print_r($xs);

// destructure negative-int keys
$a_arr = [-1 => "neg", 0 => "zero", 1 => "pos"];
[-1 => $a, 1 => $b] = $a_arr;
echo "$a $b\n";

// list() with reference
$arr = [1, 2, 3];
[&$first] = $arr;
$first = 99;
print_r($arr); // arr[0] should now be 99

// missing-key NULL fill (architectural - PHP emits Undefined array key warnings)

// destructure result of array_combine
[$x, $y, $z] = array_combine([0, 1, 2], ["a", "b", "c"]);
echo "$x $y $z\n";

// destructure with compact-like pattern
$data = ["a" => 1, "b" => 2, "c" => 3];
extract($data);
echo "$a $b $c\n";
