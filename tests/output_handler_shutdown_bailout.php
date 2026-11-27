<?php
// an output handler that throws while the buffers are flushed at shutdown,
// with no exception handler, bails out: what the buffers held and the
// error's display copy are lost (only the log copy is written), and the
// handler was called by the engine, so its frame has no caller
ini_set('zend.exception_ignore_args', '1');
echo "start\n";
ob_start(function ($buffer) {
    throw new Exception("boom");
});
echo "buffered\n";
