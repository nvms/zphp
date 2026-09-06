<?php
trait HookStorage {
    private string $stored = 'seed';
    public string $label {
        get => $this->stored;
        set { $this->stored = strtoupper($value); }
    }
    public int $counter = 7 {
        get => $this->counter;
        set => $value + 1;
    }
    public function readStored() { return $this->stored; }
}
trait NestedHookStorage { use HookStorage; }
class FirstHookOwner { use HookStorage; }
class SecondHookOwner { use NestedHookStorage; }
foreach ([new FirstHookOwner(), new SecondHookOwner()] as $owner) {
    var_dump($owner->readStored(), $owner->label, $owner->counter);
    $owner->label = 'changed';
    $owner->counter = 10;
    var_dump($owner->readStored(), $owner->label, $owner->counter);
}
