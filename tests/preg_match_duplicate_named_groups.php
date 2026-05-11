<?php
preg_match('/(?J)(?<x>a)|(?<x>b)/', "b", $m);
print_r($m);

preg_match('/(?J)(?<x>a)|(?<x>b)/', "a", $m);
print_r($m);

preg_match('/(?J)(?<year>\d{4})|(?<year>\d{2})/', "2024", $m);
print_r($m);

preg_match('/(?<name>foo)/', "foo bar", $m);
print_r($m);

preg_match('/(?J)(?<v>foo)|(?<v>bar)/', "neither", $m);
var_dump($m);
