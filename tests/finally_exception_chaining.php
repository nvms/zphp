<?php
// an exception leaving a finally block that holds another takes the held one
// as its previous, wherever it was thrown; one caught inside the block doesn't
function thrower($m) { throw new Exception($m); }
function chain($e) { $out = []; do { $out[] = $e->getMessage(); } while ($e = $e->getPrevious()); return implode(' <- ', $out); }
// thrown in a callee from finally
try { try { throw new Exception('a'); } finally { thrower('b'); } } catch (Exception $e) { echo chain($e), "\n"; }
// thrown directly in finally
try { try { throw new Exception('a'); } finally { throw new Exception('b'); } } catch (Exception $e) { echo chain($e), "\n"; }
// caught inside the finally: no chaining
try { try { throw new Exception('a'); } finally { try { thrower('inner'); } catch (Exception $i) { echo chain($i), "\n"; } } } catch (Exception $e) { echo chain($e), "\n"; }
// a throwable operand is not in flight
function two($a, $b) {}
try { two(new Exception('operand'), thrower('c')); } catch (Exception $e) { echo chain($e), "\n"; }
// across functions
function inner() { try { throw new Exception('x'); } finally { thrower('y'); } }
function outer() { try { inner(); } finally { echo "outer finally\n"; } }
try { outer(); } catch (Exception $e) { echo chain($e), "\n"; }
// catch body throws, finally throws from a callee
try { try { throw new Exception('t'); } catch (Exception $c) { thrower('c'); } finally { thrower('f'); } } catch (Exception $e) { echo chain($e), "\n"; }
// a callback from a native function
try { try { throw new Exception('n'); } finally { array_map(fn () => thrower('cb'), [1]); } } catch (Exception $e) { echo chain($e), "\n"; }
// caught, then a later exception in the same frame
try { try { throw new Exception('first'); } finally { echo "f\n"; } } catch (Exception $e) { try { thrower('later'); } catch (Exception $l) { echo chain($l), "\n"; } }
