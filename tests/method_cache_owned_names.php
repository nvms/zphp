<?php
class CachedMethods {
    function add() { return 'add'; }
    function sub() { return 'sub'; }
    function yes() { return true; }
    function not() { return false; }
}
$object = new CachedMethods();
foreach (['ADD', 'SUB', 'YES', 'NOT', 'ADD', 'SUB'] as $name) {
    $method = strtolower($name);
    var_dump(method_exists($object, $method), $object->$method());
    unset($method);
    gc_collect_cycles();
}
