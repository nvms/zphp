<?php
$nested = ['a', ['b', 'c'], ['d', ['e', 'f']]];

// default LEAVES_ONLY mode
$rii = new RecursiveIteratorIterator(new RecursiveArrayIterator($nested));
foreach ($rii as $v) echo $rii->getDepth(), ":$v ";
echo "\n";

// SELF_FIRST mode
$rii = new RecursiveIteratorIterator(new RecursiveArrayIterator($nested), RecursiveIteratorIterator::SELF_FIRST);
foreach ($rii as $v) echo $rii->getDepth(), ":", is_array($v)?"[a]":$v, " ";
echo "\n";

// setMaxDepth caps recursion at depth 1
$rii = new RecursiveIteratorIterator(new RecursiveArrayIterator($nested));
$rii->setMaxDepth(1);
foreach ($rii as $v) echo $rii->getDepth(), ":", is_array($v)?"[a]":$v, " ";
echo "\n";

// getMaxDepth
$rii = new RecursiveIteratorIterator(new RecursiveArrayIterator($nested));
$rii->setMaxDepth(2);
echo $rii->getMaxDepth(), "\n";
$rii->setMaxDepth(-1);
var_dump($rii->getMaxDepth());

// ArrayObject as ArrayAccess
$ao = new ArrayObject(['a' => 1, 'b' => 2]);
echo $ao['a'], "\n";
echo isset($ao['a']) ? "y" : "n", "\n";
$ao['c'] = 3;
echo count($ao), "\n";
unset($ao['a']);
echo isset($ao['a']) ? "y" : "n", "\n";
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";
$ao->append(99);
echo count($ao), "\n";
print_r($ao->getArrayCopy());

// Static var binding in function
function counter() {
    static $c = 0;
    return ++$c;
}
echo counter(), counter(), counter(), "\n";

// Closure with static
$f = function() {
    static $n = 0;
    return ++$n;
};
echo $f(), $f(), $f(), "\n";


// sscanf both modes
$r = sscanf("alice 30", "%s %d");
print_r($r);
$count = sscanf("alice 30", "%s %d", $name, $age);
echo "count=$count name=$name age=$age\n";

// fseek SEEK_*
$fh = fopen('php://memory', 'w+');
fwrite($fh, "Hello World");
fseek($fh, 0, SEEK_SET);
echo fread($fh, 5), "\n";
fseek($fh, 0, SEEK_END);
echo ftell($fh), "\n";
fseek($fh, -5, SEEK_END);
echo fread($fh, 5), "\n";
fclose($fh);
