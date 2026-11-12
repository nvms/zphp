<?php
// the Attribute class declares its typed $flags, which unserialize fills
// as a declared property
$r = new ReflectionProperty(Attribute::class, 'flags');
var_dump((string) $r->getType(), (new Attribute)->flags, (new Attribute(Attribute::TARGET_METHOD))->flags);
var_dump(get_object_vars(unserialize('O:9:"Attribute":1:{s:5:"flags";i:63;}')));
var_dump(unserialize('O:9:"Attribute":1:{s:5:"flags";s:1:"x";}'));
