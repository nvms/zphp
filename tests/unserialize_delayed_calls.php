<?php
// php queues every __unserialize() until the whole string is read and runs
// them then, in the order their objects finished, even when reading failed
// after their elements; the first that throws ends the rest

class W {
    public $tag;
    public function __unserialize(array $data): void {
        echo "unserialize ", json_encode($data), "\n";
        $this->tag = $data["a"] ?? null;
        if (($data["a"] ?? null) === "boom") throw new RuntimeException("boom");
    }
}

$cases = [
    'a:2:{i:0;O:1:"W":1:{s:1:"a";i:1;}i:1;O:1:"W":1:{s:1:"a";i:2;}}',
    'O:1:"W":2:{s:1:"a";i:1;s:1:"b";O:1:"W":1:{s:1:"a";i:2;}}',
    'O:1:"W":1:{s:1:"a";i:1;',
    'a:2:{i:0;O:1:"W":1:{s:1:"a";i:1;}i:1;O:1:"W":1:{s:1:"a";s:1:"x"',
    'a:3:{i:0;O:1:"W":1:{s:1:"a";s:4:"boom";}i:1;O:1:"W":1:{s:1:"a";i:2;}i:2;i:3;}',
    'O:8:"DateTime":1:{i:1;d:2;',
    'a:2:{i:0;O:1:"W":1:{s:1:"a";i:1;}i:1;R:2;}',
];
foreach ($cases as $s) {
    echo "-- ", $s, "\n";
    try {
        $r = @unserialize($s);
        echo "result ", json_encode($r), "\n";
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

// __wakeup() is queued the same way, so the two interleave in order
class K {
    public $data;
    public function __wakeup() {
        echo "wakeup ", json_encode($this->data), "\n";
    }
}
foreach ([
    'O:1:"K":1:{s:4:"data";a:1:{i:0;O:1:"W":1:{s:1:"a";O:1:"K":1:{s:4:"data";i:5;}}}}',
    'a:2:{i:0;O:1:"K":1:{s:4:"data";i:1;}i:1;O:1:"W":1:{s:1:"a";i:2;}}',
    'a:2:{i:0;O:1:"K":1:{s:4:"data";i:1;}i:1;O:1:"W":1:{s:1:"a";i:2;}',
] as $s) {
    echo "-- ", $s, "\n";
    var_dump(@unserialize($s) !== false);
}

$a = new ArrayObject();
$m = new ArrayObject();
$m[] = $m;
$a[] = $m;
$b = new ArrayObject();
$b->unserialize($a->serialize());
echo $b->serialize(), "\n";
