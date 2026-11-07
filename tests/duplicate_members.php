<?php
// a method or property declared twice in one class stops the file before it
// runs, constructor promotion included
echo "not reached\n";
class Point {
    public function __construct(public int $x, public int $y) {}
    public $x;
}
