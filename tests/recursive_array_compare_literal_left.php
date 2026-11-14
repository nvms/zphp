<?php
// comparing a recursive array with a literal fails the same way whichever
// side the literal is on

$a = [&$a];
try { var_dump($a === [[]]); } catch (Error $e) { echo "1: ", $e->getMessage(), "\n"; }
try { var_dump([[]] === $a); } catch (Error $e) { echo "2: ", $e->getMessage(), "\n"; }
try { var_dump([[]] == $a); } catch (Error $e) { echo "3: ", $e->getMessage(), "\n"; }
try { var_dump([[]] !== $a); } catch (Error $e) { echo "4: ", $e->getMessage(), "\n"; }
try { var_dump([[]] != $a); } catch (Error $e) { echo "5: ", $e->getMessage(), "\n"; }
try { var_dump([1, [2]] === $a); } catch (Error $e) { echo "6: ", $e->getMessage(), "\n"; }
var_dump($a === $a);
$b = 1;
var_dump(1 == $b, '1' === $b, [1, 2] == [2 => 1], null == false, 'abc' != $b);
