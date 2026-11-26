<?php
// a dynamic property created under the name of an ancestor's unset private
// property leaves that private property unset
class C {
    private $p = 'test';
    function unsetPrivate() { unset($this->p); }
    function setPrivate() { $this->p = 'changed'; }
    function getP() { return isset($this->p) ? $this->p : 'unset'; }
}
#[AllowDynamicProperties]
class D extends C {
    function setP() { $this->p = 'changed in D'; }
}
$d = new D;
$d->unsetPrivate();
$d->setP();
var_dump($d, $d->getP());

$d = new D;
$d->unsetPrivate();
$d->p = 'global';
var_dump($d, $d->getP(), (array) $d, get_object_vars($d));
$d->setPrivate();
var_dump($d, $d->getP());

$d = new D;
$d->unsetPrivate();
$d->setPrivate();
var_dump($d);
