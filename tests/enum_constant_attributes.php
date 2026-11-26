<?php
// an enum's constants (not only its cases) carry their attributes

interface HasLimit {
    const LIMIT = 1;
}

#[Attribute(Attribute::TARGET_CLASS_CONSTANT)]
class Tag {
    public function __construct(public string $name) {}
}

enum Size implements HasLimit {
    case Small;

    #[Tag('max')]
    const MAX = 10;

    #[\Override]
    const LIMIT = 2;

    #[\Deprecated('use MAX')]
    const OLD = 5;

    const PLAIN = 1;
}

foreach (['Small', 'MAX', 'LIMIT', 'OLD', 'PLAIN'] as $name) {
    $rc = new ReflectionClassConstant(Size::class, $name);
    $attrs = array_map(fn($a) => $a->getName(), $rc->getAttributes());
    echo $name, ': ', implode(', ', $attrs), ' deprecated=', var_export($rc->isDeprecated(), true), "\n";
}

$tag = (new ReflectionClassConstant(Size::class, 'MAX'))->getAttributes(Tag::class)[0]->newInstance();
var_dump($tag->name);
var_dump(Size::LIMIT, Size::OLD);
