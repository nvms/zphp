<?php
// serialize() and unserialize() nested in a Serializable's own methods share
// the outer call's back-reference table, as php's do

#[AllowDynamicProperties]
class Node implements Serializable
{
    public function serialize()
    {
        return serialize(get_object_vars($this));
    }

    public function unserialize($s)
    {
        foreach (unserialize($s) as $p => $v) {
            $this->$p = $v;
        }
    }
}
class Leaf extends Node {}
class Root extends Leaf {}

$root = new Root();
$root->a = new Node();
$root->a->b = new Leaf();
$root->a->b->c = $root;
$root->a->c = $root;
$root->a->b->a = $root->a;
$root->a->a = $root->a;

$s = serialize($root);
echo $s, "\n";
$copy = unserialize($s);
var_dump(
    $copy === $copy->a->b->c,
    $copy->a->a === $copy->a,
    $copy->a->b->a === $copy->a,
    $copy->a->c === $copy
);
print_r($copy);
echo "\n";

// __serialize starts a table of its own for a nested serialize()
class Fresh
{
    public $o;

    public function __construct()
    {
        $this->o = new stdClass();
    }

    public function __serialize(): array
    {
        return ['inner' => serialize($this->o), 'o' => $this->o];
    }
}
echo serialize([new Fresh(), 1]), "\n";
