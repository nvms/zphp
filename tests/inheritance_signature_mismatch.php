<?php
// an override whose signature does not fit the parent's ends the script,
// with both declarations printed as php prints them
interface Store {
    public function put(string $key, mixed $value = null, int $ttl = 60, array $tags = [], string $prefix = 'cache-entries:', ...$extra): bool;
}
echo "declaring\n";
if (true) {
    class MemoryStore implements Store {
        public function put(string $key, mixed $value = null, int $ttl = 60, array $tags = ['a'], string $prefix = 'x'): bool { return true; }
    }
}
echo "not reached\n";
