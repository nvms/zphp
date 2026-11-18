<?php
// get_object_vars() keeps a property another name references as a
// reference, so writing the copy writes the property; a property nothing
// else references is copied by value

class P {
    public $declared = 'declared';
    private $hidden = 'hidden';
    public function vars() { return get_object_vars($this); }
    public function &hiddenRef() { return $this->hidden; }
}

$a = 'original.a';
$obj = new stdClass;
$obj->ref = &$a;
$obj->val = $a;
$arr = get_object_vars($obj);
var_dump($arr);
$arr['ref'] = 'changed.ref';
$arr['val'] = 'changed.val';
var_dump($obj, $a);

$p = new P;
$alias = &$p->declared;
$h = &$p->hiddenRef();
$vars = $p->vars();
var_dump($vars);
$vars['declared'] = 'through get_object_vars';
$vars['hidden'] = 'hidden too';
var_dump($p, $alias, $h);

unset($alias);
$again = get_object_vars($p);
var_dump($again);
