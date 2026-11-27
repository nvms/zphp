<?php
// a destructor shutdown runs throws while a value it held is released: that
// value's destructor runs with no frame below it, so what it throws is fatal
// at once, without the first exception as its previous
class C {
    public function __construct(public string $name) {}
    public function __destruct() {
        echo "destruct {$this->name}\n";
        if ($this->name === "outer") {
            $inner = new C("inner");
            throw new Exception("from outer");
        }
        throw new Exception("from {$this->name}");
    }
}
class Later {
    public function __destruct() {
        echo "later\n";
    }
}

$later = new Later;
$c = new C("outer");
echo "end\n";
