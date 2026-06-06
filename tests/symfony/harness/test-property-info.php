<?php
// exercises symfony/property-info - property discovery + read/write detection
// via reflection. stresses zphp's Reflection over typed props, constructor
// promotion, readonly, and getter/setter/isser accessor inference
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\PropertyInfo\Extractor\ReflectionExtractor;

class Product {
    public int $id;
    public string $name;
    private ?float $price = null;
    public array $tags = [];
    public function __construct(public readonly string $sku) {}
    public function getName(): string { return $this->name; }
    public function setName(string $n): void { $this->name = $n; }
    public function isActive(): bool { return true; }
    public function getPrice(): ?float { return $this->price; }
}

$ex = new ReflectionExtractor();

$props = $ex->getProperties(Product::class);
sort($props);
echo "props: ", implode(',', $props), "\n";

foreach (['id', 'name', 'price', 'tags', 'sku', 'active', 'missing'] as $p) {
    $r = $ex->isReadable(Product::class, $p) ? 'R' : '-';
    $w = $ex->isWritable(Product::class, $p) ? 'W' : '-';
    echo "$p: $r$w\n";
}
