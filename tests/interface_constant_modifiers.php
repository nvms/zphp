<?php
// interface constants keep final and their type, and are listed in order
interface Codes { final public const OK = 200; const string LABEL = 'codes'; const MISSING = 404; }
foreach ((new ReflectionClass('Codes'))->getReflectionConstants() as $r) {
    echo $r->getName(), ': ', var_export($r->isFinal(), true), ' ', $r->getType() ?? '-', "\n";
}
