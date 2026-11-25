<?php
// php 8.6 names a virtual property with asymmetric visibility and only one
// hook get-only or set-only, at the line its hooks end on
class GetOnlyAsym {
    public private(set) int $v {
        get => 1;
    }
}
echo "unreachable\n";
