<?php

class LazySerializedRecord
{
    public ?int $id = null;
    public string $name;
    public int $untouched;
}

$reflection = new ReflectionClass(LazySerializedRecord::class);
foreach ([0, ReflectionClass::SKIP_INITIALIZATION_ON_SERIALIZE] as $options) {
    $record = $reflection->newLazyGhost(function (LazySerializedRecord $record) {
        echo "initialize\n";
        $record->name = 'Ada';
    }, $options);
    $reflection->getProperty('id')->setRawValueWithoutLazyInitialization($record, 7);
    var_dump(serialize($record));
    var_dump($reflection->isUninitializedLazyObject($record));
}
