<?php
// a class constant's expression is evaluated on its first access, or when
// the class is first instantiated or reflected, then type checked and kept
class Config {
    const NEXT = self::FIRST + 1;
    const FIRST = 1;
    const NAME = APP_NAME;
    const float RATIO = WHOLE;
    const string LABEL = LABEL_OBJECT;
}
echo Config::NEXT, "\n";
define('APP_NAME', 'app'); echo Config::NAME, "\n";
define('WHOLE', 3); var_dump(Config::RATIO);
define('LABEL_OBJECT', new stdClass);
for ($i = 0; $i < 2; $i++) {
    try { var_dump(Config::LABEL); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
}
class Loop { const P = self::Q; const Q = self::P; }
try { echo Loop::P; } catch (Error $e) { echo $e->getMessage(), "\n"; }
class NeedsMissing { const Z = NOT_DEFINED; }
try { new NeedsMissing; } catch (Error $e) { echo 'new: ', $e->getMessage(), "\n"; }
try { (new ReflectionClass('NeedsMissing'))->getConstants(); } catch (Error $e) { echo 'reflection: ', $e->getMessage(), "\n"; }
enum Suit { const Suit DEFAULT = Suit::Hearts; const static ALSO = self::Hearts; case Hearts; }
var_dump(Suit::DEFAULT, Suit::ALSO);
class Strict { const int I = STRING_FIVE; const int|string M = FLOAT_ONE; }
define('STRING_FIVE', '5'); define('FLOAT_ONE', 1.0);
try { var_dump(Strict::I); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { var_dump(Strict::M); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
class Literal { const float F = 3; }
var_dump(Literal::F);
class Magic { const M = __METHOD__ . '|' . __FUNCTION__ . '|' . __CLASS__ . '|' . DEFERRED_SUFFIX; }
define('DEFERRED_SUFFIX', 'x');
var_dump(Magic::M);
