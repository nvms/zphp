<?php

// simple variable
$x = 10;
$x += 5;
echo "x += 5: $x\n";
$old = $x++;
echo "x++: old=$old, x=$x\n";
$new = ++$x;
echo "++x: new=$new, x=$x\n";
$x--;
echo "x--: $x\n";
--$x;
echo "--x: $x\n";

// property compound
class Counter {
    public int $val = 0;
    public string $name = "test";
    public array $items = [1, 2, 3];
}

$c = new Counter();
$c->val = 10;
$c->val += 5;
echo "prop +=: $c->val\n";
$old = $c->val++;
echo "prop++: old=$old, val=$c->val\n";
$new = ++$c->val;
echo "++prop: new=$new, val=$c->val\n";
$c->val--;
echo "prop--: $c->val\n";
--$c->val;
echo "--prop: $c->val\n";
$c->name .= "_suffix";
echo "prop .=: $c->name\n";

// array element compound
$arr = [10, 20, 30];
$arr[0] += 5;
echo "arr[0] +=: $arr[0]\n";
$old = $arr[1]++;
echo "arr[1]++: old=$old, arr[1]=$arr[1]\n";
$new = ++$arr[2];
echo "++arr[2]: new=$new, arr[2]=$arr[2]\n";
$arr[0]--;
echo "arr[0]--: $arr[0]\n";
--$arr[0];
echo "--arr[0]: $arr[0]\n";

// assoc array
$map = ["a" => 1, "b" => 2];
$map["a"] += 10;
echo "map[a] +=: " . $map["a"] . "\n";
$old = $map["b"]++;
echo "map[b]++: old=$old, map[b]=" . $map["b"] . "\n";
$new = ++$map["a"];
echo "++map[a]: new=$new, map[a]=" . $map["a"] . "\n";

// string concat on array element
$words = ["hello"];
$words[0] .= " world";
echo "arr .=: $words[0]\n";

// null coalesce assign on array
$data = [];
$data["key"] ??= "default";
echo "arr ??=: " . $data["key"] . "\n";

// static property
class Config {
    public static int $count = 0;
}

Config::$count += 5;
echo "static +=: " . Config::$count . "\n";
$old = Config::$count++;
echo "static++: old=$old, count=" . Config::$count . "\n";
$new = ++Config::$count;
echo "++static: new=$new, count=" . Config::$count . "\n";

// nested: object property that's an array
$c2 = new Counter();
$c2->items[1] += 100;
echo "obj->arr[1] +=: " . $c2->items[1] . "\n";

// postfix in expression context
$arr2 = [100, 200];
$result = $arr2[0]++ + $arr2[1]++;
echo "postfix expr: result=$result, arr=[" . $arr2[0] . ", " . $arr2[1] . "]\n";
