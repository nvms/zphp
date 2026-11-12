<?php
class Base {
    public int $kept = 1;
}
class Child extends Base {
    #[\Override]
    public int $kept = 2;
    #[\Override]
    public int $fresh = 3;
}
echo "never runs\n";
