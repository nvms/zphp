<?php
// Registering each parent grows the class/interface tables while the child
// declaration is still in progress. Both direct and diamond contracts survive.
spl_autoload_register(function ($name) {
    if ($name === 'AutoloadLeaf') {
        eval('interface AutoloadLeaf extends AutoloadLeft, AutoloadRight {}');
    } elseif ($name === 'AutoloadLeft') {
        eval('interface AutoloadLeft extends AutoloadRoot {}');
    } elseif ($name === 'AutoloadRight') {
        eval('interface AutoloadRight extends AutoloadRoot {}');
    } elseif ($name === 'AutoloadRoot') {
        for ($i = 0; $i < 80; $i++) {
            eval('interface AutoloadPadding' . $i . ' {}');
        }
        eval('interface AutoloadRoot { public int $value { get; set; } }');
    }
});
var_dump(interface_exists('AutoloadLeaf'));
class AutoloadImplementation implements AutoloadLeaf {
    public int $value = 7;
}
$object = new AutoloadImplementation;
var_dump($object instanceof AutoloadLeaf, $object instanceof AutoloadLeft,
    $object instanceof AutoloadRight, $object instanceof AutoloadRoot);
echo $object->value, "\n";
$object->value = 12;
echo $object->value, "\n";
