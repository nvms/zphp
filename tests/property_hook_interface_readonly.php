<?php
// a public readonly property is protected(set), which can't implement an
// interface property with a public set

interface I {
    public int $prop { get; set; }
}
class C implements I {
    public function __construct(public readonly int $prop) {}
}

echo "not reached\n";
