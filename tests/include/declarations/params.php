<?php
function legacy(int $id = null, $flags = 0, $required) {}
function fine(?int $id = null, int|null $other = null, mixed $any = null, $last = 1) {}
class Repo {
    public function find(string $key = null) {}
    public function &nothing(): void {}
    public function __construct(public ?int $limit = null) {}
}
$handler = function (array $rows = null) {};
class Factory { public function make() { return fn (float $f = null) => $f; } }
