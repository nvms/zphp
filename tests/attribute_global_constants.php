<?php
// a global constant keeps its attributes; a redefinition warns and leaves
// the first definition (and its attributes) in place
#[Attribute(Attribute::TARGET_CONSTANT | Attribute::IS_REPEATABLE)]
class Label { function __construct(public string $text) {} }

#[Label('first'), Label(text: 'again')]
const GREETING = 'hello';

#[Label('second')]
const GREETING = 'replaced';

const PLAIN = 1;
#[Label('late')]
const PLAIN = 2;

define('DEFINED', 1);
var_dump(define('DEFINED', 2), DEFINED);

foreach (['GREETING', 'PLAIN'] as $name) {
    $r = new ReflectionConstant($name);
    var_dump(constant($name), array_map(fn ($a) => $a->newInstance()->text, $r->getAttributes()));
}
try { (new ReflectionClass('Label'))->getAttributes()[0]->newInstance(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
#[Label('x')] class Wrong {}
try { (new ReflectionClass('Wrong'))->getAttributes()[0]->newInstance(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
