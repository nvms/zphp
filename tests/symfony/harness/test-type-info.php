<?php
// exercises symfony/type-info - reflection-based property type resolution. the
// TypeContextFactory cache path uses nested `??=` coalesce-assign, which stresses
// undefined-intermediate-key warning suppression
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\TypeInfo\TypeResolver\TypeResolver;

class Widget {
    public int $count;
    public ?string $label;
    public array $items;
    public float $ratio;
    public bool $enabled;
}

$r = TypeResolver::create();
$rc = new ReflectionClass('Widget');
foreach ($rc->getProperties() as $p) {
    try {
        $t = $r->resolve($p);
        echo $p->getName(), ' => ', (string) $t, "\n";
    } catch (\Throwable $e) {
        echo $p->getName(), ' => ERR ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}
