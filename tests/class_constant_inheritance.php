<?php
// constants that may be redeclared are, and reflection sees interface
// constants' final flag and types; overriding a final one ends the script
interface Codes { final public const OK = 200; const string LABEL = 'codes'; }
interface More extends Codes { const MISSING = 404; }
class Base implements More { const LABEL = 'base'; protected const LIMIT = 10; private const SECRET = 1; }
class Child extends Base { public const LIMIT = 20; private const SECRET = 2; }
class Again extends Base implements Codes { const MISSING = 410; }
echo Child::OK, ' ', Child::LIMIT, ' ', Again::MISSING, ' ', Base::LABEL, "\n";
foreach (['OK', 'LABEL'] as $c) {
    $r = new ReflectionClassConstant('Codes', $c);
    echo $c, ': ', var_export($r->isFinal(), true), ' ', $r->getType() ?? '-', "\n";
}
class Typed { const int|string ID = 1; const ?array LIST = null; }
class TypedChild extends Typed { const string ID = 'x'; const array LIST = []; }
echo TypedChild::ID, "\n";
echo "declaring\n";
if (true) {
    class Broken implements Codes { const OK = 201; }
}
