<?php
// covers: pcntl_sigprocmask OS masks, previous-mask writeback, all operations
function check_mask($condition) {
    if (!$condition) throw new Exception('signal mask check failed');
}

$original = null;
check_mask(pcntl_sigprocmask(SIG_BLOCK, [SIGUSR1], $original));
try {
    // The reported mask is the PREVIOUS mask, not the requested one.
    $current = [];
    check_mask(pcntl_sigprocmask(SIG_UNBLOCK, [SIGUSR1], $current));
    check_mask(in_array(SIGUSR1, $current, true));
    $copy = $current;
    check_mask(pcntl_sigprocmask(SIG_BLOCK, [SIGUSR2], $current));
    check_mask(!in_array(SIGUSR1, $current, true));
    check_mask(in_array(SIGUSR1, $copy, true));

    check_mask(pcntl_sigprocmask(SIG_SETMASK, [SIGUSR1], $current));
    check_mask(in_array(SIGUSR2, $current, true));
    check_mask(pcntl_sigprocmask(SIG_BLOCK, [SIGUSR1], $current));
    check_mask($current === [SIGUSR1]);

    // Function-local output and writeback through a by-reference wrapper.
    function read_mask(&$out) {
        $local = null;
        check_mask(pcntl_sigprocmask(SIG_BLOCK, [SIGUSR1], $local));
        check_mask($local === [SIGUSR1]);
        check_mask(pcntl_sigprocmask(SIG_BLOCK, [SIGUSR1], $out));
    }
    $wrapped = null;
    read_mask($wrapped);
    check_mask($wrapped === [SIGUSR1]);

    // Variable calls and explicitly referenced spread args.
    $fn = 'pcntl_sigprocmask';
    $local = null;
    check_mask($fn(SIG_BLOCK, [SIGUSR1], $local));
    check_mask($local === [SIGUSR1]);
    $spread = [SIG_BLOCK, [SIGUSR1], &$local];
    $local = null;
    check_mask(pcntl_sigprocmask(...$spread));
    check_mask($local === [SIGUSR1]);
    $local = null;
    check_mask($fn(...$spread));
    check_mask($local === [SIGUSR1]);

    // Invalid operations/signals fail without replacing the output or mask.
    $untouched = ['sentinel'];
    try {
        check_mask(@pcntl_sigprocmask(-1, [SIGUSR2], $untouched) === false);
        check_mask(pcntl_get_last_error() !== 0);
    } catch (ValueError $e) {
        // PHP versions differ in argument-validation policy.
    }
    check_mask($untouched === ['sentinel']);
    try {
        check_mask(@pcntl_sigprocmask(SIG_BLOCK, [0], $untouched) === false);
        check_mask(pcntl_get_last_error() !== 0);
    } catch (ValueError $e) {
    }
    check_mask($untouched === ['sentinel']);
    check_mask(pcntl_sigprocmask(SIG_BLOCK, [SIGUSR1], $current));
    check_mask($current === [SIGUSR1]);
} finally {
    // Restoration may legitimately use an empty inherited mask. This test
    // does not assert a version-specific empty-input validation policy.
    pcntl_sigprocmask(SIG_SETMASK, $original);
}
echo "ok\n";
