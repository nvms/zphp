<?php
// a property name built by an expression is a temporary; magic methods and
// hooks still see it intact after the access pops it

class Magic
{
    public $depth = 0;
    public $stored = [];

    public function __get($name)
    {
        if (++$this->depth > 3) {
            return $name;
        }
        return $this->{$name . "x"};
    }

    public function __set($name, $value)
    {
        $this->stored[] = $name . "=" . $value;
    }

    public function __isset($name)
    {
        echo "isset ", $name, "\n";
        return true;
    }
}

$m = new Magic();
var_dump($m->{"a" . str_repeat("b", 3)});
$m->{"c" . str_repeat("d", 3)} = 1;
var_dump($m->stored);
var_dump($m->{"i" . str_repeat("j", 2)} ?? "none");

class Hooked
{
    public array $list = [];
}

$h = new Hooked();
$h->{"li" . "st"}[] = 1;
$h->{"li" . "st"}["k"] = 2;
var_dump($h->list);
