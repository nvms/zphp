<?php
// an interface property marked #[\Override] needs a parent declaring it
interface I {
    #[\Override]
    public mixed $i { get; }
}
echo "not reached\n";
