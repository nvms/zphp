<?php
class Hidden {
    private function __get($name) { return "get $name"; }
    protected function __set($name, $value) {}
    protected function __isset($name) { return true; }
    private function __unset($name) {}
    private function __call($name, $args) {}
    protected static function __callStatic($name, $args) {}
    public function __toString(): string { return 'hidden'; }
    private function __invoke() {}
    private function __construct() {}
    private function __clone() {}
}
interface Typed {
    public function __get(string|int $name);
    public function __debugInfo(): ?array;
    public static function __set_state(array $state): static;
}
