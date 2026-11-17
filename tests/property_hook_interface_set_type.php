<?php
// a plain property implementing an interface property with a set hook must
// accept everything the hook's parameter type does

interface I {
    public string $prop {
        set(int|string $value);
    }
}
class C implements I {
    public string $prop;
}

echo "not reached\n";
