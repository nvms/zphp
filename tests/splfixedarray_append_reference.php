<?php
// a reference to an appended SplFixedArray element is refused
$a = new SplFixedArray(2);
try { $b = &$a[]; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $a[][1] = 2; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $a[] = 2; } catch (Error $e) { echo $e->getMessage(), "\n"; }
