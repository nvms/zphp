<?php
// an exception thrown while unserialize() rebuilds an object propagates to
// the caller; only a malformed payload is a warning plus false
class Rebuilt {
    public function __serialize(): array { return ['n' => 1]; }
    public function __unserialize(array $data): void { throw new RuntimeException("rebuild refused " . $data['n']); }
}
class Woken {
    public $n = 2;
    public function __wakeup(): void { throw new LogicException("wake refused"); }
}
try { unserialize(serialize(new Rebuilt)); echo "no exception\n"; } catch (RuntimeException $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { unserialize(serialize(new Woken)); echo "no exception\n"; } catch (LogicException $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(@unserialize('a:1:{i:0;s:3:"ab"}'));
$nested = unserialize(serialize(['ok' => 1]));
var_dump($nested);
