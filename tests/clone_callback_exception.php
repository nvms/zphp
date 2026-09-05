<?php
class RejectClone {
    public function __clone() { throw new RuntimeException('clone rejected'); }
}
foreach ([new RejectClone(), curl_share_init()] as $object) {
    try {
        $copy = clone $object;
        echo "unexpected clone\n";
    } catch (Throwable $e) {
        echo get_class($e), ':', $e->getMessage(), "\n";
    }
}
echo "done\n";
