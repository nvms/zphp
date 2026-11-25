<?php
// libxml_get_external_entity_loader() returns what
// libxml_set_external_entity_loader() set last, null before and after a reset
var_dump(libxml_get_external_entity_loader());
$loader = function ($public, $system, $context) { return null; };
var_dump(libxml_set_external_entity_loader($loader));
var_dump(libxml_get_external_entity_loader() === $loader);
var_dump(libxml_set_external_entity_loader('strlen'), libxml_get_external_entity_loader());
var_dump(libxml_set_external_entity_loader(null), libxml_get_external_entity_loader());
try {
    libxml_set_external_entity_loader(new SimpleXMLElement('<root/>'));
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(libxml_get_external_entity_loader());
$f = new ReflectionFunction('libxml_get_external_entity_loader');
var_dump((string) $f->getReturnType(), $f->getNumberOfParameters(), $f->getExtensionName());
