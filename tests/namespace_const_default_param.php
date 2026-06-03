<?php

// a default parameter value that references a GLOBAL constant must resolve via
// the same namespace fallback PHP uses everywhere: inside `namespace Foo`, the
// unqualified `PHP_INT_MAX` is looked up as `Foo\PHP_INT_MAX` first, then falls
// back to the global `\PHP_INT_MAX`. zphp stored the qualified name on the
// deferred-constant default but skipped the global fallback, so the default
// resolved to null. this surfaced as Laravel's Str::explode($d) (its $limit =
// PHP_INT_MAX default became null -> explode limit 1 -> string not split).

namespace App\Support;

const LOCAL_LIMIT = 7;

function withGlobalConst($x, $limit = PHP_INT_MAX): int { return $limit; }
function withErrConst($n = E_ALL): int { return $n; }
function withLocalConst($n = LOCAL_LIMIT): int { return $n; }
function bodyConst(): int { return PHP_INT_MAX; }

// the real-world shape: a default-param limit fed straight into explode()
function splitAll(string $s, string $d, int $limit = PHP_INT_MAX): array {
    return \explode($d, $s, $limit);
}

namespace App;

use function App\Support\withGlobalConst;
use function App\Support\withErrConst;
use function App\Support\withLocalConst;
use function App\Support\bodyConst;
use function App\Support\splitAll;

echo "global const default: ", withGlobalConst('a'), "\n";   // 9223372036854775807
echo "E_ALL default: ", withErrConst(), "\n";                // 30719
echo "local const default: ", withLocalConst(), "\n";        // 7
echo "body const: ", bodyConst(), "\n";                      // 9223372036854775807
echo "explode via default limit: ", implode('|', splitAll('x-y-z', '-')), "\n";  // x|y|z
echo "explode count: ", count(splitAll('one - two - three', '-')), "\n";          // 3

// phpinfo() section-flag constants are defined
echo "INFO_GENERAL=", INFO_GENERAL, " INFO_ALL=", INFO_ALL, " INFO_MODULES=", INFO_MODULES, "\n"; // 1 4294967295 8
