<?php

class LazyRecord
{
    private ?int $id = null;
    private string $name;

    public function id(): ?int { return $this->id; }
    public function name(): string { return $this->name; }
    public function load(): void { $this->name = 'Ada'; }
}

$reflection = new ReflectionClass(LazyRecord::class);
$record = $reflection->newLazyGhost(function (LazyRecord $record) {
    echo "initialize\n";
    $record->load();
});
$identifier = $reflection->getProperty('id');
$identifier->setRawValueWithoutLazyInitialization($record, 7);
var_dump($reflection->isUninitializedLazyObject($record));
var_dump($record->id());
var_dump($reflection->isUninitializedLazyObject($record));
var_dump($record->name());
var_dump($reflection->isUninitializedLazyObject($record));

// Parent and child private slots with identical names stay independent.
class LazyParent { private int $id = 1; public function parentId() { return $this->id; } }
class LazyChild extends LazyParent { private int $id = 2; public function childId() { return $this->id; } }
$reflection = new ReflectionClass(LazyChild::class);
$record = $reflection->newLazyGhost(function ($record) { echo "private-init\n"; });
(new ReflectionProperty(LazyParent::class, 'id'))->setRawValueWithoutLazyInitialization($record, 7);
var_dump($record->parentId(), $reflection->isUninitializedLazyObject($record));
var_dump($record->childId(), $reflection->isUninitializedLazyObject($record));
