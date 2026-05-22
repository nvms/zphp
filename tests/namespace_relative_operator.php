<?php
// regression: the `namespace\` relative-namespace operator resolves a name
// against the current namespace, skipping use-alias lookup. covers function
// calls, constants, `new`, static calls, and multi-segment names.

namespace App;

function ping(): string { return 'App\\ping'; }
const LEVEL = 7;

class Box {
    public function tag(): string { return 'App\\Box'; }
    public static function build(): self { return new self(); }
}

namespace App\Sub;

function ping(): string { return 'App\\Sub\\ping'; }

class Thing {
    public function tag(): string { return 'App\\Sub\\Thing'; }
}

namespace App;

echo namespace\ping(), "\n";
echo namespace\LEVEL, "\n";

$b = new namespace\Box();
echo $b->tag(), "\n";
echo namespace\Box::build()->tag(), "\n";

echo namespace\Sub\ping(), "\n";

$t = new namespace\Sub\Thing();
echo $t->tag(), "\n";
