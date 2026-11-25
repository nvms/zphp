<?php
// an internal unit enum declares its cases' name property, as a user enum does
foreach (['RoundingMode', 'SortDirection', 'Random\IntervalBoundary'] as $enum) {
    $rc = new ReflectionClass($enum);
    var_dump(array_map(fn ($p) => $p->getName(), $rc->getProperties()));
    var_dump($rc->hasProperty('name'), property_exists($enum, 'name'));
    $p = new ReflectionProperty($enum, 'name');
    var_dump($p->isReadOnly(), $p->isPublic(), (string) $p->getType(), $p->hasDefaultValue());
}
echo new ReflectionClass('RoundingMode');
try {
    $case = SortDirection::Ascending;
    $case->name = 'x';
} catch (Error $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
try {
    $case = SortDirection::Ascending;
    $case->other = 'x';
} catch (Error $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
