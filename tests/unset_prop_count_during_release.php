<?php
// var_dump's property count while an unset property's value is destructed
class Holder {
    public $a = 1;
    public $child;
    public $b = 2;
}
class Child {
    public function __construct(public Holder $owner, public string $label) {}
    public function __destruct() {
        echo "destruct {$this->label}\n";
        var_dump($this->owner);
    }
}

// the property table was built by an earlier listing
$h = new Holder;
$h->child = new Child($h, "listed");
print_r($h);
echo "\n";
unset($h->child);
var_dump($h);

// no table built yet
$h2 = new Holder;
$h2->child = new Child($h2, "fresh");
unset($h2->child);

// a foreach builds it too
$h3 = new Holder;
$h3->child = new Child($h3, "iterated");
foreach ($h3 as $k => $v) {}
unset($h3->child);

// dynamic properties mean the table exists
$h4 = new Holder;
$h4->child = new Child($h4, "dynamic");
$h4->{'extra'} = 3;
$name = 'child';
unset($h4->$name);
var_dump($h4);
