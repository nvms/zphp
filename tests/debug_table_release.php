<?php
// a debug table built for one listing lets go of what it holds afterwards, so
// objects it listed are destroyed when php destroys them
class D { function __destruct() { echo "~D\n"; } }
$ao = new ArrayObject([new D]);
var_dump(count((array)$ao));
print_r($ao); echo "\n";
unset($ao);
echo "after\n";
$dt = new DateTime('2020-01-01');
var_dump($dt);
unset($dt);
echo spl_object_id(new stdClass), "\n";
