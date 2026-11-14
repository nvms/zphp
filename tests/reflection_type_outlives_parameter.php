<?php
// a type taken from a parameter of a temporary getParameters() array keeps
// its names after the parameter and the array are gone

class Shape
{
    public function resize(self $other, ?self $maybe, self|int $either, (Countable&ArrayAccess)|null $dnf, Countable&ArrayAccess $both): self
    {
        return $this;
    }
}

function churn(): void
{
    $junk = [];
    for ($i = 0; $i < 50; $i++) {
        $junk[] = str_repeat(chr(65 + $i % 26), 16);
    }
}

function show(ReflectionType $t): string
{
    churn();
    if ($t instanceof ReflectionNamedType) {
        return $t->getName() . ($t->allowsNull() ? " (nullable)" : "");
    }
    $parts = [];
    foreach ($t->getTypes() as $sub) {
        $parts[] = show($sub);
    }
    return get_class($t) . "[" . implode(", ", $parts) . "] " . $t;
}

for ($n = 0; $n < 5; $n++) {
    echo show((new ReflectionMethod('Shape', 'resize'))->getParameters()[$n]->getType()), "\n";
}

$types = [];
for ($n = 0; $n < 5; $n++) {
    $types[] = (new ReflectionMethod('Shape', 'resize'))->getParameters()[$n]->getType();
}
churn();
foreach ($types as $t) {
    echo $t, "\n";
}

$m = new ReflectionMethod('Shape', 'resize');
$t = $m->getParameters()[0]->getType();
unset($m);
churn();
echo $t->getName(), "\n";
