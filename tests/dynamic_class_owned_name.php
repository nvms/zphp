<?php
class DurableController {
    function value(): string { return 'alive'; }
}
function constructDynamic() {
    $name = 'Durable' . 'Controller';
    return new $name();
}
$object = constructDynamic();
gc_collect_cycles();
var_dump(get_class($object), $object->value());
$reflection = new ReflectionClass('Durable' . 'Controller');
$reflected = $reflection->newInstance();
unset($reflection);
gc_collect_cycles();
var_dump(get_class($reflected), $reflected->value());
