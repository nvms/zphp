<?php
// a parameter default that its declared type can't hold stops the file
// before it runs
echo "not reached\n";
function ok(float $ratio = 1, iterable $items = [], bool $flag = false) {}
function broken(int $count = 'none') {}
