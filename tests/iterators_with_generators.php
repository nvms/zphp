<?php

$g = function() { yield 1; yield 2; yield 3; yield 4; yield 5; };

// FilterIterator with generator
$even = new CallbackFilterIterator($g(), fn($v) => $v % 2 === 0);
foreach ($even as $v) echo $v . " ";
echo "\n";

// LimitIterator with generator
$first3 = new LimitIterator($g(), 0, 3);
foreach ($first3 as $v) echo $v . " ";
echo "\n";

// AppendIterator with generators
$ai = new AppendIterator();
$ai->append((function(){ yield 'a'; yield 'b'; })());
$ai->append((function(){ yield 'c'; yield 'd'; })());
foreach ($ai as $v) echo $v . " ";
echo "\n";

// IteratorIterator wrapping a generator
$ii = new IteratorIterator($g());
foreach ($ii as $v) echo $v . " ";
echo "\n";

// CachingIterator with generator
$ci = new CachingIterator($g());
foreach ($ci as $v) echo $v . " ";
echo "\n";

// nested: Filter on top of Limit on top of generator
$pipeline = new CallbackFilterIterator(
    new LimitIterator($g(), 1, 3),
    fn($v) => $v > 2
);
foreach ($pipeline as $v) echo $v . " ";
echo "\n";
