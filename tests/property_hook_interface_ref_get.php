<?php
// an interface's &get hook can't be implemented by a by-value get hook

interface I {
    public $prop { &get; }
}

class A implements I {
    public $prop {
        get => $this->prop;
    }
}

echo "not reached\n";
