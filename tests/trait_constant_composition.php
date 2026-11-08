<?php
// a constant a class and a trait it uses both declare must agree in
// visibility, final, type and value
trait Defaults { public const LIMIT = 10; final public const MODE = 'a'; public const array LIST = []; }
class Same { use Defaults; public const LIMIT = 10; final public const MODE = 'a'; public const array LIST = []; }
echo Same::LIMIT, Same::MODE, count(Same::LIST), "\n";
class Computed { use Defaults; public const LIMIT = 5 + 5; final public const MODE = 'a'; public const array LIST = []; }
echo Computed::LIMIT, "\n";
echo "declaring\n";
if (true) {
    class Different { use Defaults; public const LIMIT = 11; final public const MODE = 'a'; public const array LIST = []; }
}
