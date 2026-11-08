<?php
// functions and closures declared in an included file keep their attributes
// and their parameters' attributes, also when the file is included again
require __DIR__ . '/include/attributed_functions.php';
include_once __DIR__ . '/include/attributed_functions.php';

function describe(ReflectionFunction $f) {
    foreach ($f->getAttributes() as $a) var_dump($a->getName(), $a->getArguments());
    foreach ($f->getParameters() as $p) {
        foreach ($p->getAttributes() as $a) var_dump($p->getName() . ': ' . $a->getName(), $a->getArguments());
    }
}
describe(new ReflectionFunction('included_function'));
describe(new ReflectionFunction(make_included_closure()));
