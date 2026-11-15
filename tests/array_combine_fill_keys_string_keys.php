<?php
// array_combine and array_fill_keys take non-integer keys through their
// string form, with its warnings and errors
class S { function __toString(): string { return "obj"; } }
$keys = [1, "2", 1.5, true, false, null, STDERR, [1], new S, "x"];
var_dump(array_keys(array_fill_keys($keys, 0)));
var_dump(array_keys(array_combine($keys, range(1, count($keys)))));
try { array_fill_keys([new stdClass], 1); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { array_combine([new stdClass], [1]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
