<?php
// serialize() holds each array while it walks it: a __serialize that grows
// the array through a reference separates it, and the walk sees the old one
class G {
    public $ref;
    public function __serialize(): array {
        for ($i = 0; $i < 3; $i++) {
            $this->ref[] = 'x' . $i;
        }
        return ['d' => 1];
    }
}
$g = new G();
$inner = [$g, 'tail'];
$g->ref = &$inner;
$top = [&$inner];
var_dump(serialize($top));
var_dump(count($inner));

$g = new G();
$inner = [$g, 'tail'];
$g->ref = &$inner;
var_dump(serialize($inner));
var_dump(count($inner));
