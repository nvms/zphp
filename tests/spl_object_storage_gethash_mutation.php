<?php
// php 8.6 refuses to change any SplObjectStorage from inside a getHash() call
class EvilStorage extends SplObjectStorage {
    public bool $mutate = false;

    public function getHash($obj): string {
        global $victim;
        if ($this->mutate) {
            $victim[new stdClass()] = null;
        }
        return spl_object_id($obj);
    }
}

function populate(SplObjectStorage $victim, SplObjectStorage $other): void {
    for ($i = 0; $i < 1024; $i++) {
        $o = new stdClass();
        $victim[$o] = null;
        $other[$o] = null;
    }
}

$victim = new SplObjectStorage();
$other = new EvilStorage();

populate($victim, $other);
$other->mutate = true;

try {
    $victim->removeAllExcept($other);
} catch (Error $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

var_dump(count($victim), count($other));

unset($victim, $other);
$victim = new SplObjectStorage();
$other = new EvilStorage();

populate($victim, $other);
$other->mutate = true;

try {
    $other->addAll($victim);
} catch (Error $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

var_dump(count($victim), count($other));
