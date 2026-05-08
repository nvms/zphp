<?php
// duplicate named groups via (?J)
preg_match_all('/(?J)(?<n>\w+)|(?<n>\d+)/', "abc 123", $m);
print_r($m);

// preg_match_all with named, nested
preg_match_all('/(?<outer>(?<inner>\w)\1)/', "aa bb ccc", $m);
print_r($m);

// optional named not captured
preg_match_all('/(?<a>\w)(?<b>\d)?/', "x y2 z", $m);
print_r($m);

// PREG_SET_ORDER with named
preg_match_all('/(?<word>\w+):(?<num>\d+)/', "a:1 b:22 c:333", $m, PREG_SET_ORDER);
print_r($m);

// named + offset capture
preg_match_all('/(?<key>\w+)=(?<val>\d+)/', "x=1 y=2", $m, PREG_OFFSET_CAPTURE);
print_r($m);

// preg_match keeps both numeric and string keys
preg_match('/(?<word>\w+) (?<num>\d+)/', "hello 42", $m);
print_r($m);
