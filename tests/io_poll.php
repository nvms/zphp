<?php
// php 8.6's Io\Poll: contexts, watchers and stream handles over the
// epoll and poll backends, after php-src's ext/standard/tests/poll

// stream Poll Testing helper

function pt_new_stream_poll(): Io\Poll\Context {
    return new Io\Poll\Context($GLOBALS['pt_backend']);
}

function pt_stream_poll_add($poll_ctx, $stream, $events, $data = null): Io\Poll\Watcher {
    return $poll_ctx->add(new StreamPollHandle($stream), $events, $data);
}

function pt_skip_for_backend($backend, $msg): void {
    $backends_to_skip = is_array($backend) ? $backend : array($backend);
    $current_backend = pt_new_stream_poll()->getBackend();
    if (in_array($current_backend->name, $backends_to_skip)) {
        die("skip backend {$current_backend->name} $msg\n");
    }
}

function pt_new_socket_pair(): array {
    $domain = (strtoupper(substr(PHP_OS, 0, 3) == 'WIN') ? STREAM_PF_INET : STREAM_PF_UNIX);
    $sockets = stream_socket_pair($domain, STREAM_SOCK_STREAM, 0);
    if ($sockets === false) {
        die("Cannot create socket pair\n");
    }
    return $sockets;
}

function pt_new_tcp_socket_pair(): array {
    $server = stream_socket_server("tcp://127.0.0.1:0", $errno, $errstr);
    if (!$server) {
        die("Cannot create TCP server: $errstr\n");
    }
    $address = stream_socket_get_name($server, false);

    $client = stream_socket_client("tcp://$address", $errno, $errstr);
    if (!$client) {
        fclose($server);
        die("Cannot connect to TCP server: $errstr\n");
    }

    $server_conn = stream_socket_accept($server);
    if (!$server_conn) {
        fclose($server);
        fclose($client);
        die("Cannot accept connection\n");
    }

    // Close the listening socket (no longer needed)
    fclose($server);

    return [$client, $server_conn];
}

function pt_new_tcp_socket_connections(int $num_conns): array {
    $server = stream_socket_server("tcp://127.0.0.1:0", $errno, $errstr);
    if (!$server) {
        die("Cannot create TCP server: $errstr\n");
    }
    $address = stream_socket_get_name($server, false);

    $clients = [];
    $server_conns = [];
    for ($i = 0; $i < $num_conns; ++$i) {
        $clients[$i] = stream_socket_client("tcp://$address", $errno, $errstr);
        if (!$clients[$i]) {
            fclose($server);
            die("Cannot connect to TCP server: $errstr\n");
        }

        $server_conns[$i] = stream_socket_accept($server);
        if (!$server_conns[$i]) {
            fclose($server);
            die("Cannot accept connection\n");
        }
    }

    // Close the listening socket (no longer needed)
    fclose($server);

    return [$clients, $server_conns];
}

function pt_write_sleep($stream, $data, $delay = 10000): int|false {
    $result = fwrite($stream, $data);
    usleep($delay);
    return $result;
}

function pt_event_array_to_string(array $events): string {
    $names = [];
    foreach ($events as $event) {
        if (is_array($event)) {
            // Optional slot, rendered in brackets.
            $names[] = '[' . pt_event_array_to_string($event) . ']';
        } else {
            $names[] = $event->name;
        }
    }
    return empty($names) ? 'NONE' : implode('|', $names);
}

function pt_print_events($watchers, $read_data = false): void {
    if (!is_array($watchers)) {
        die("Events must be an array\n");
    }
    echo "Events count: " . count($watchers) . "\n";
    foreach ($watchers as $i => $watcher) {
        if (!$watcher instanceof Io\Poll\Watcher) {
            die('Invalid event type');
        }
        echo "Event[$i]: " . pt_event_array_to_string($watcher->getTriggeredEvents()) . ", user data: " . $watcher->getData();
        if ($read_data && $watcher->hasTriggered(Io\Poll\Event::Read)) {
            $data = fread($watcher->getHandle()->getStream(), 1024);
            echo ", read data: '$data'";
        }
        echo "\n";
    }
}

function pt_expect_events($watchers, $expected, ?Io\Poll\Context $poll_ctx = null): void {
    if (!is_array($watchers)) {
        die("Events must be an array\n");
    }

    if (!is_array($expected)) {
        die("Expected events must be an array\n");
    }

    $event_count = count($watchers);
    $expected_count = count($expected);

    // Get the current backend for backend-specific expectations
    $backend = $poll_ctx ? $poll_ctx->getBackend()->name : 'unknown';

    if ($event_count !== $expected_count) {
        echo "Event count mismatch: got $event_count, expected $expected_count\n";
        pt_print_mismatched_events($watchers, $expected, [], $backend);
        return;
    }

    // Convert events to comparable format for matching
    $actual_events = [];
    foreach ($watchers as $watcher) {
        if (!$watcher instanceof Io\Poll\Watcher) {
            die('Invalid event type');
        }

        $event_data = [
            'events' => $watcher->getTriggeredEvents(),
            'data' => $watcher->getData(),
        ];

        $actual_events[] = $event_data;
    }

    // Resolve backend-specific expectations
    $resolved_expected = [];
    foreach ($expected as $exp_event) {
        $resolved_event = $exp_event;

        // Check if events field is a backend-specific map (associative array with string keys)
        if (isset($exp_event['events']) && is_array($exp_event['events'])) {
            // Check if it's a backend map (has string keys like 'default', 'Kqueue', etc.)
            $keys = array_keys($exp_event['events']);
            $is_backend_map = false;
            foreach ($keys as $key) {
                if (is_string($key)) {
                    $is_backend_map = true;
                    break;
                }
            }

            if ($is_backend_map) {
                // It's a backend-specific map, resolve it
                $resolved_event['events'] = pt_resolve_backend_specific_value($exp_event['events'], $backend);
            }
            // Otherwise it's already an array of Event enums, leave it as-is
        }

        $resolved_expected[] = $resolved_event;
    }

    // Try to match each expected event with an actual event
    $matched = [];
    $unmatched_expected = [];

    foreach ($resolved_expected as $exp_idx => $exp_event) {
        $found_match = false;

        foreach ($actual_events as $act_idx => $act_event) {
            if (isset($matched[$act_idx])) {
                continue; // Already matched
            }

            // Check if events and data match
            if (pt_events_equal($act_event['events'], $exp_event['events']) &&
                $act_event['data'] === $exp_event['data']) {

                // If read data is expected, check it
                if (isset($exp_event['read'])) {
                    $read_data = fread($watchers[$act_idx]->getHandle()->getStream(), 1024);
                    if ($read_data !== $exp_event['read']) {
                        continue; // Read data doesn't match
                    }
                }

                $matched[$act_idx] = $exp_idx;
                $found_match = true;
                break;
            }
        }

        if (!$found_match) {
            $unmatched_expected[] = $exp_event;
        }
    }

    // Check if all events matched
    if (count($matched) === $event_count && empty($unmatched_expected)) {
        echo "Events matched - count: $event_count\n";
    } else {
        echo "Events did not match:\n";
        pt_print_mismatched_events($watchers, $expected, $matched, $backend);
    }
}

function pt_events_equal($actual, $expected): bool {
    // Both should be arrays of Event enums
    if (!is_array($actual) || !is_array($expected)) {
        return false;
    }

    // An expected item that is itself an array marks an optional slot: it may be
    // absent, or filled by exactly one of the events it lists. Plain enums are
    // required. This lets a backend accept e.g. Write with an optional HangUp
    // that may not have propagated yet, without weakening the required events.
    $required = [];
    $optional_groups = [];
    foreach ($expected as $item) {
        if (is_array($item)) {
            $optional_groups[] = array_map(fn($e) => $e->name, $item);
        } else {
            $required[] = $item->name;
        }
    }

    $actual_names = array_map(fn($e) => $e->name, $actual);

    // Every required event must be present.
    foreach ($required as $name) {
        $idx = array_search($name, $actual_names, true);
        if ($idx === false) {
            return false;
        }
        unset($actual_names[$idx]);
    }

    // Each leftover actual event must be accounted for by a distinct optional
    // slot that lists it.
    foreach ($actual_names as $name) {
        $matched = false;
        foreach ($optional_groups as $gi => $group) {
            if (in_array($name, $group, true)) {
                unset($optional_groups[$gi]);
                $matched = true;
                break;
            }
        }
        if (!$matched) {
            return false;
        }
    }

    return true;
}

function pt_resolve_backend_specific_value($backend_map, $current_backend) {
    // Direct backend match
    if (isset($backend_map[$current_backend])) {
        return $backend_map[$current_backend];
    }

    // Check for multi-backend keys (e.g., "Kqueue|EventPorts")
    foreach ($backend_map as $key => $value) {
        if (strpos($key, '|') !== false) {
            $backends = array_map('trim', explode('|', $key));
            if (in_array($current_backend, $backends)) {
                return $value;
            }
        }
    }

    // Fall back to default
    if (isset($backend_map['default'])) {
        return $backend_map['default'];
    }

    // If no match found, this is an error
    die("No backend-specific value found for '$current_backend' and no default specified\n");
}

function pt_print_mismatched_events($actual_watchers, $expected_watchers, $matched = [], $backend_name = null): void {
    echo "Actual events:\n";
    foreach ($actual_watchers as $i => $watcher) {
        $match_status = isset($matched[$i]) ? " [MATCHED]" : " [UNMATCHED]";
        $watcher_names = pt_event_array_to_string($watcher->getTriggeredEvents());
        echo "  Event[$i]: $watcher_names, user data: " . $watcher->getData() . $match_status . "\n";
    }

    echo "Expected events:\n";
    foreach ($expected_watchers as $i => $exp_event) {
        $was_matched = in_array($i, $matched);
        $match_status = $was_matched ? " [MATCHED]" : " [UNMATCHED]";

        $events_value = $exp_event['events'];
        
        // Check if it's a backend-specific map
        if (is_array($events_value) && $backend_name !== null) {
            $keys = array_keys($events_value);
            $is_backend_map = false;
            foreach ($keys as $key) {
                if (is_string($key)) {
                    $is_backend_map = true;
                    break;
                }
            }
            
            if ($is_backend_map) {
                $events_value = pt_resolve_backend_specific_value($events_value, $backend_name);
            }
        }

        $watcher_names = is_array($events_value) ? pt_event_array_to_string($events_value) : 'INVALID';
        echo "  Event[$i]: $watcher_names, user data: " . $exp_event['data'];
        if (isset($exp_event['read'])) {
            echo ", read data: '" . $exp_event['read'] . "'";
        }
        echo $match_status . "\n";
    }
}

/*
 * Self-test for the pt_* event-matching helpers.
 *
 * This is deliberately NOT a .phpt: the CI only runs .phpt files, never .inc,
 * so this never executes there. It only runs when poll.inc is executed as the
 * main script, which lets the (fiddly) optional-slot matching logic be verified
 * by hand:
 *
 *     sapi/cli/php ext/standard/tests/poll/poll.inc
 */
function pt_run_self_test(): void {
    if (!enum_exists('Io\\Poll\\Event')) {
        echo "Io\\Poll\\Event not available; build with poll support to run the self-test\n";
        return;
    }

    $R = Io\Poll\Event::Read;
    $W = Io\Poll\Event::Write;
    $E = Io\Poll\Event::Error;
    $H = Io\Poll\Event::HangUp;

    $failures = 0;
    $check = function (string $label, bool $cond) use (&$failures) {
        if ($cond) {
            echo "ok   - $label\n";
        } else {
            echo "FAIL - $label\n";
            ++$failures;
        }
    };

    // Plain required sets are order independent and exact.
    $check('exact set matches', pt_events_equal([$W, $H], [$H, $W]));
    $check('missing required fails', !pt_events_equal([$W], [$W, $H]));
    $check('extra unexpected fails', !pt_events_equal([$W, $H], [$W]));

    // Optional slot: [$W, [$H]] means Write required, HangUp allowed but not
    // required.
    $check('optional present matches', pt_events_equal([$W, $H], [$W, [$H]]));
    $check('optional absent matches', pt_events_equal([$W], [$W, [$H]]));
    $check('optional cannot satisfy a required event', !pt_events_equal([$H], [$W, [$H]]));
    $check('unlisted extra with optional fails', !pt_events_equal([$W, $E], [$W, [$H]]));

    // A single optional slot accepts at most one of its listed events; separate
    // slots can each accept one.
    $check('optional picks one of group', pt_events_equal([$W, $H], [$W, [$H, $E]]));
    $check('optional group may stay empty', pt_events_equal([$W], [$W, [$H, $E]]));
    $check('single slot rejects two', !pt_events_equal([$W, $H, $E], [$W, [$H, $E]]));
    $check('two slots accept two', pt_events_equal([$W, $H, $E], [$W, [$H], [$E]]));

    // Rendering.
    $check('renders plain set', pt_event_array_to_string([$W, $H]) === 'Write|HangUp');
    $check('renders optional slot', pt_event_array_to_string([$W, [$H]]) === 'Write|[HangUp]');
    $check('renders empty as NONE', pt_event_array_to_string([]) === 'NONE');

    echo $failures === 0
        ? "\nAll self-tests passed\n"
        : "\n$failures self-test(s) FAILED\n";
}

if (isset($_SERVER['SCRIPT_FILENAME'])
        && realpath($_SERVER['SCRIPT_FILENAME']) === __FILE__) {
    pt_run_self_test();
}

$GLOBALS['pt_backend'] = Io\Poll\Backend::Auto;
echo "--- poll_stream_sock_add_only\n";
list($first1, $first2) = pt_new_socket_pair();
$first_ctx = pt_new_stream_poll();

pt_stream_poll_add($first_ctx, $first2, [Io\Poll\Event::Write], "socket2_data");

var_dump($first_ctx);
unset($first_ctx, $first1, $first2);

echo "--- api surface\n";
// the api surface: dumps, getters, argument errors, refusals
use Io\Poll\{Backend, Event, Context, Watcher};
var_dump(Backend::getAvailableBackends());
foreach (Backend::cases() as $b) { echo $b->name, " ", var_export($b->isAvailable(), true), " ", var_export($b->supportsEdgeTriggering(), true), "\n"; }
$c = new Context();
var_dump($c, $c->getBackend());
[$r, $w] = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);
$h = new StreamPollHandle($r);
var_dump($h, $h->isValid(), $h->getStream() === $r);
$wa = $c->add($h, [Event::Read, Event::Read, Event::Write], "d");
var_dump($wa);
print_r($wa); echo "\n";
var_dump($wa->getWatchedEvents(), $wa->getTriggeredEvents(), $wa->getHandle() === $h, $wa->getData(), $wa->isActive());
var_dump(new Io\Poll\InactiveWatcherException("x"));
$ev = $c->wait(Time\Duration::fromSeconds(0));
var_dump(count($ev), $ev[0] === $wa, $wa->getTriggeredEvents());
try { new Watcher(); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { $c->add($h, []); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { $c->add($h, [1]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { $c->add($h, [Event::Read, 1]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { $wa->modify([]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { $c->add(new StreamPollHandle($w), [Event::Read, Event::EdgeTriggered]); echo "et ok\n"; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), " ", $e->getCode(), "\n"; }
$p = new Context(Backend::Poll);
try { $p->add(new StreamPollHandle($w), [Event::Read, Event::EdgeTriggered]); echo "et ok\n"; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), " ", $e->getCode(), "\n"; }
try { new Context(Backend::Kqueue); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), " ", $e->getCode(), "\n"; }
try { $h->foo = 1; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { serialize($c); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { serialize($wa); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { serialize($h); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { unserialize('O:16:"StreamPollHandle":0:{}'); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
try { new StreamPollHandle(1); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(Io\Poll\FailedPollOperationException::ERROR_NOSUPPORT, (new ReflectionClass(Io\Poll\FailedPollOperationException::class))->getConstants());

$c2 = new Context();
$m = fopen('php://memory', 'r+');
try { $c2->add(new StreamPollHandle($m), [Event::Read]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
class U { public $context; function stream_open($p, $m, $o, &$op) { return true; } function stream_eof() { return false; } }
stream_wrapper_register('uu', 'U');
$u = fopen('uu://x', 'r');
try { $c2->add(new StreamPollHandle($u), [Event::Read]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump((new StreamPollHandle($u))->isValid(), (new StreamPollHandle($m))->isValid());
[$r2, $w2] = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);
stream_filter_append($r2, 'string.rot13');
$wr = $c2->add(new StreamPollHandle($r2), [Event::Read]);
fwrite($w2, "abc");
var_dump(count($c2->wait(Time\Duration::fromSeconds(1))));
fclose($w2);
var_dump(fread($r2, 10), feof($r2), (new StreamPollHandle($r2))->isValid());
var_dump(count($ev = $c2->wait(Time\Duration::fromSeconds(1))), $ev[0]->getTriggeredEvents());
$f = fopen(__FILE__, 'r');
$pc = new Context(Io\Poll\Backend::Poll);
$wf = $pc->add(new StreamPollHandle($f), [Event::Read, Event::Write]);
var_dump(count($ev = $pc->wait(Time\Duration::fromSeconds(0))), $ev[0]->getTriggeredEvents());
try { $c2->add(new StreamPollHandle($f), [Event::Read]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), " ", $e->getCode(), "\n"; }
var_dump(count($pc->wait()));
var_dump(count((new Context(Io\Poll\Backend::Poll))->wait()));
var_dump(STDIN);

echo "--- api\n";
(function () {
    var_dump(Io\Poll\Backend::getAvailableBackends());
    foreach (Io\Poll\Backend::cases() as $b) {
        echo $b->name, " ", var_export($b->isAvailable(), true), " ", var_export($b->supportsEdgeTriggering(), true), "\n";
    }
    var_dump(Io\Poll\FailedPollOperationException::ERROR_NOSUPPORT, (new ReflectionClass(Io\Poll\FailedPollOperationException::class))->getConstants());
    var_dump(Io\Poll\Event::cases());
    foreach (['Io\\IoException', 'Io\\Poll\\PollException', 'Io\\Poll\\FailedPollWaitException', 'Io\\Poll\\InvalidHandleException'] as $class) {
        echo $class, ': ', get_parent_class($class), "\n";
    }
})();

$GLOBALS['pt_backend'] = Io\Poll\Backend::Auto;
echo "--- gh22759 (Auto)\n";
(function () {
[$r, $w] = pt_new_socket_pair();
$context = pt_new_stream_poll();
$handle = new StreamPollHandle($r);

$first = $context->add($handle, [Io\Poll\Event::Read]);
$first->remove();

$ref = WeakReference::create($first);
unset($first);
gc_collect_cycles();
var_dump($ref->get());

$second = $context->add($handle, [Io\Poll\Event::Read]);

unset($context);
gc_collect_cycles();

var_dump($second->isActive());

try {
    $second->remove();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

echo "done\n";
})();

echo "--- gh25086 (Auto)\n";
(function () {
function test_modify(string $name, array $events_list, bool $readable): void {
    [$r, $w] = pt_new_socket_pair();
    if ($readable) {
        fwrite($w, "x");
    }
    $context = pt_new_stream_poll();
    $watcher = pt_stream_poll_add($context, $r, $events_list[0]);

    $modify = function (int $count) use ($context, $watcher, $events_list) {
        for ($i = 0; $i < $count; $i++) {
            $context->wait(Time\Duration::fromSeconds(0));
            $watcher->modifyEvents($events_list[$i % count($events_list)]);
        }
    };

    // Warm up to absorb one-time allocations
    $modify(10);
    $before = memory_get_usage();
    $modify(1000);
    $growth = memory_get_usage() - $before;
    echo "$name: ", $growth < 1024 ? "no growth" : "grew by $growth bytes", "\n";
    $watcher->remove();
}



test_modify("read <-> read+write", [[Io\Poll\Event::Read], [Io\Poll\Event::Read, Io\Poll\Event::Write]], true);
test_modify("read <-> write", [[Io\Poll\Event::Read], [Io\Poll\Event::Write]], true);
test_modify("read -> read one-shot -> read", [[Io\Poll\Event::Read], [Io\Poll\Event::Read, Io\Poll\Event::OneShot]], true);
test_modify("re-arm read one-shot", [[Io\Poll\Event::Read, Io\Poll\Event::OneShot]], true);
test_modify("re-arm read+write one-shot, both fire", [[Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot]], true);
test_modify("re-arm read+write one-shot, write fires", [[Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot]], false);
})();

echo "--- poll_clone_not_allowed (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$handle = new StreamPollHandle($r);
$watcher = $ctx->add($handle, [Io\Poll\Event::Read]);

foreach ([$ctx, $handle, $watcher] as $obj) {
    try {
        clone $obj;
    } catch (Throwable $e) {
        echo $e::class, ': ', $e->getMessage(), "\n";
    }
}

echo "done\n";
})();

echo "--- poll_ctx_backend_unix (Auto)\n";
(function () {
// this just prints default poll ctx
$poll_ctx = new Io\Poll\Context();
var_dump($poll_ctx->getBackend());
// test with poll that is always available on Unix systems
$poll_ctx = new Io\Poll\Context(Io\Poll\Backend::Poll);
$backend = $poll_ctx->getBackend();
var_dump($backend->name);
try {
    new Io\Poll\Context(Io\Poll\Backend::WSAPoll);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
})();

echo "--- poll_ctx_wait_error (Auto)\n";
(function () {
$poll_ctx = new Io\Poll\Context();

try {
    $poll_ctx->wait(timeout: Time\Duration::fromSeconds(1)->negate());
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    $poll_ctx->wait(maxEvents: PHP_INT_MIN);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    $poll_ctx->wait(maxEvents: -1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}

try {
    $poll_ctx->wait(maxEvents: 0);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- poll_ctx_wait_error_int64 (Auto)\n";
(function () {
$poll_ctx = new Io\Poll\Context();

try {
    $poll_ctx->wait(maxEvents: PHP_INT_MAX);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), PHP_EOL;
}
})();

echo "--- poll_double_construct (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();

$handle = new StreamPollHandle($r);
try {
    $handle->__construct($r);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

$ctx = pt_new_stream_poll();
try {
    $ctx->__construct();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

echo "done\n";
})();

echo "--- poll_stream_add_error_duplicate (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

try {
    pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
})();

echo "--- poll_stream_add_unpollable (Auto)\n";
(function () {
$ctx = pt_new_stream_poll();

// epoll_ctl() rejects files that do not implement polling
foreach (['regular file' => fopen(__FILE__, 'r'), '/dev/null' => fopen('/dev/null', 'r')] as $label => $stream) {
    try {
        $ctx->add(new StreamPollHandle($stream), [Io\Poll\Event::Read]);
        echo "$label: added\n";
    } catch (Io\Poll\FailedHandleAddException $e) {
        printf("%s: %s, code %s\n", $label, $e->getMessage(),
            Io\Poll\FailedPollOperationException::ERROR_NOSUPPORT === $e->getCode() ? 'ERROR_NOSUPPORT' : $e->getCode());
    }
    fclose($stream);
}

// a pollable handle still works
[$r, $w] = pt_new_socket_pair();
$ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);
echo "socket: added\n";
})();

echo "--- poll_stream_buffered_edge (Auto)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
fwrite($b, "first\nsecond\n");
var_dump(fgets($a));

$ctx = pt_new_stream_poll();
$w = pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read, Io\Poll\Event::EdgeTriggered], 'a');

// Buffered data is state, an edge watcher reports transitions only
var_dump(count($ctx->wait(Time\Duration::fromMilliseconds(100))));

// A new edge on the descriptor is reported as usual
fwrite($b, "third\n");
$events = $ctx->wait(Time\Duration::fromMilliseconds(100));
var_dump(count($events), $events[0] === $w);
})();

echo "--- poll_stream_buffered_level (Auto)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
fwrite($b, "first\nsecond\n");
var_dump(fgets($a)); // "second\n" is now in $a's read buffer, the socket is empty

$ctx = pt_new_stream_poll();
$w = pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read], 'a');

// Returned at once although the descriptor is idle
$start = hrtime(true);
$events = $ctx->wait(Time\Duration::fromSeconds(5));
var_dump(count($events), $events[0] === $w, $events[0]->hasTriggered(Io\Poll\Event::Read));
var_dump(hrtime(true) - $start < 2_000_000_000);
var_dump(stream_get_meta_data($a)['unread_bytes']);

// Level: reported on every wait while the data stays buffered
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));

var_dump(fgets($a));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));

// Write interest is not concerned with read data
fwrite($b, "third\nfourth\n");
var_dump(fgets($a));
$w->modifyEvents([Io\Poll\Event::Write]);
$events = $ctx->wait(Time\Duration::fromSeconds(0));
var_dump(count($events), $events[0]->hasTriggered(Io\Poll\Event::Write), $events[0]->hasTriggered(Io\Poll\Event::Read));

// The buffer counts as soon as Read interest is back
$w->modifyEvents([Io\Poll\Event::Read]);
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
})();

echo "--- poll_stream_buffered_max_events (Auto)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
[$c, $d] = pt_new_socket_pair();
[$e, $f] = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read], 'a');
pt_stream_poll_add($ctx, $c, [Io\Poll\Event::Read], 'c');
pt_stream_poll_add($ctx, $e, [Io\Poll\Event::Read], 'e');

fwrite($b, "first\nsecond\n");
fwrite($d, "first\nsecond\n");
var_dump(fgets($a), fgets($c));
fwrite($f, "x"); // on the socket, not buffered

var_dump(count($ctx->wait(Time\Duration::fromSeconds(0), 1)));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0), 2)));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0), 3)));

var_dump(fgets($a), fgets($c), fread($e, 10));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
})();

echo "--- poll_stream_buffered_merge (Auto)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
[$c, $d] = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$wa = pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read], 'a');
$wc = pt_stream_poll_add($ctx, $c, [Io\Poll\Event::Read], 'c');

// $a: buffered data and an idle socket; $c: data on the socket
fwrite($b, "first\nsecond\n");
var_dump(fgets($a));
fwrite($d, "x");

$events = $ctx->wait(Time\Duration::fromMilliseconds(100));
$seen = [];
foreach ($events as $e) {
    $seen[$e->getData()] = $e->hasTriggered(Io\Poll\Event::Read);
}
ksort($seen);
var_dump($seen);

// $a: buffered data and data on the socket at once: one entry, Read once
fwrite($b, "third\n");
var_dump(fread($c, 10));
$events = $ctx->wait(Time\Duration::fromMilliseconds(100));
var_dump(count($events), $events[0] === $wa, $events[0]->hasTriggered(Io\Poll\Event::Read));
var_dump(fgets($a), fgets($a));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
})();

echo "--- poll_stream_buffered_oneshot (Auto)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
fwrite($b, "first\nsecond\n");
var_dump(fgets($a));

$ctx = pt_new_stream_poll();
$w = pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], 'a');

// Fires once from the buffer
$events = $ctx->wait(Time\Duration::fromSeconds(0));
var_dump(count($events), $events[0] === $w);

// Disarmed: neither the buffer nor new data on the socket reports it
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
fwrite($b, "third\n");
var_dump(count($ctx->wait(Time\Duration::fromMilliseconds(50))));
var_dump($w->isActive());

// Re-armed: the buffer reports it at once, again once
$w->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));

// Drained, re-armed: the descriptor reports it
var_dump(fgets($a), fgets($a));
$w->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
fwrite($b, "fourth\n");
$events = $ctx->wait(Time\Duration::fromMilliseconds(100));
var_dump(count($events), $events[0]->hasTriggered(Io\Poll\Event::Read));

$w->remove();
var_dump($w->isActive());
})();

echo "--- poll_stream_closed_dup_fd (Auto)\n";
(function () {
// The child keeps a duplicate of $r open, so epoll would keep the interest after
// fclose() unless the watcher is unregistered while the fd is still open
$ctx = new Io\Poll\Context(Io\Poll\Backend::Epoll);
list($r, $w) = pt_new_socket_pair();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);

$proc = proc_open('sleep 2', [0 => $r], $pipes);
fclose($r);
$watcher->remove();
unset($watcher);
gc_collect_cycles();

fwrite($w, "ping");
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";

// A new stream that takes the same fd number gets its own registration
list($r2, $w2) = pt_new_socket_pair();
$watcher2 = $ctx->add(new StreamPollHandle($r2), [Io\Poll\Event::Read], "new");
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
fwrite($w2, "pong");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
echo "Events count: ", count($events), "\n";
var_dump($events[0]->getData());

proc_terminate($proc);
proc_close($proc);
echo "done\n";
})();

echo "--- poll_stream_closed_fd_reuse (Auto)\n";
(function () {
$ctx = pt_new_stream_poll();

list($r0, $w0) = pt_new_socket_pair();
$old = $ctx->add(new StreamPollHandle($r0), [Io\Poll\Event::Read], "old");

// The lowest free fd number is handed out first, so $r1 takes the number $r0 had
fclose($r0);
list($r1, $w1) = pt_new_socket_pair();

$new = $ctx->add(new StreamPollHandle($r1), [Io\Poll\Event::Read], "new");
var_dump($old->isActive());
var_dump($new->isActive());

fwrite($w1, "ping");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events));
var_dump($events[0] === $new);
var_dump($events[0]->getData());

$old->remove();
echo "old removed\n";

$new->remove();
var_dump($new->isActive());
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
})();

echo "--- poll_stream_closed_fd_reuse_unwatched (Auto)\n";
(function () {
$ctx = pt_new_stream_poll();

list($r0, $w0) = pt_new_socket_pair();
$old = $ctx->add(new StreamPollHandle($r0), [Io\Poll\Event::Read], "old");

// The lowest free fd number is handed out first, so $r1 takes the number $r0 had
fclose($r0);
list($r1, $w1) = pt_new_socket_pair();
fwrite($w1, "ping");

echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($old->isActive());

$old->remove();
var_dump($old->isActive());
var_dump(fread($r1, 10));
})();

echo "--- poll_stream_closed_many (Auto)\n";
(function () {
$ctx = pt_new_stream_poll();

list($rk, $wk) = pt_new_socket_pair();
$keep = $ctx->add(new StreamPollHandle($rk), [Io\Poll\Event::Read], "keep");

list($ro, $wo) = pt_new_socket_pair();
$oneshot = $ctx->add(new StreamPollHandle($ro), [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "oneshot");
fwrite($wo, "x");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events), $events[0]->getData());

for ($i = 0; $i < 200; $i++) {
    list($r, $w) = pt_new_socket_pair();
    $watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);
    fclose($r);
    $watcher->remove();
    fclose($w);
}

// The fired one-shot watcher stays disarmed, the kept one is still watched
fwrite($wk, "y");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events), $events[0]->getData());
var_dump($keep->isActive(), $oneshot->isActive());

$oneshot->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events));

list($r, $w) = pt_new_socket_pair();
$new = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read], "new");
fwrite($w, "z");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events));
var_dump($oneshot->isActive());
})();

echo "--- poll_stream_closed_multi_context (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$handle = new StreamPollHandle($r);

$ctx1 = pt_new_stream_poll();
$ctx2 = pt_new_stream_poll();
$w1 = $ctx1->add($handle, [Io\Poll\Event::Read]);
$w2 = $ctx2->add($handle, [Io\Poll\Event::Read]);

fwrite($w, "ping");
fclose($r);

echo "ctx1 events count: ", count($ctx1->wait(Time\Duration::fromSeconds(0))), "\n";
echo "ctx2 events count: ", count($ctx2->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($w1->isActive());
var_dump($w2->isActive());

$w1->remove();
$w2->remove();
echo "removed\n";

fclose($w);
})();

echo "--- poll_stream_closed_persistent (Auto)\n";
(function () {
$srv = stream_socket_server("tcp://127.0.0.1:0", $e1, $e2);
$addr = stream_socket_get_name($srv, false);
$p = pfsockopen("tcp://" . $addr, -1, $en, $es, 1);

$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($p), [Io\Poll\Event::Write]);
echo "Events count: ", count($ctx->wait(Time\Duration::fromMicroseconds(100000))), "\n";

// The persistent stream outlives the request, so the watcher and context are
// intentionally left to be freed at shutdown
echo "done\n";
})();

echo "--- poll_stream_closed_watcher_inactive (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);

fwrite($w, "ping");
var_dump($watcher->isActive());

fclose($r);
var_dump($watcher->isActive());

echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";

$watcher->remove();
$watcher->remove();
echo "removed\n";
var_dump($watcher->isActive());

try {
    $watcher->modifyEvents([Io\Poll\Event::Write]);
} catch (Io\Poll\InactiveWatcherException $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

fclose($w);
})();

echo "--- poll_stream_handle_close_then_free (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);

// Close the underlying streams before the watcher and handle are freed.
fclose($r);
fclose($w);

unset($watcher, $ctx);
gc_collect_cycles();
echo "ok\n";
})();

echo "--- poll_stream_handle_closed_stream (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

$handle = new StreamPollHandle($r);
$watcher = $poll_ctx->add($handle, [Io\Poll\Event::Read]);
$not_added_yet = new StreamPollHandle($w);

fclose($r);
fclose($w);

var_dump($handle->isValid());
var_dump(get_debug_type($handle->getStream()));

try {
    $watcher->modifyEvents([Io\Poll\Event::Write]);
} catch (Io\Poll\InactiveWatcherException $e) {
    echo $e->getMessage(), "\n";
}

try {
    $poll_ctx->add($not_added_yet, [Io\Poll\Event::Read]);
} catch (Io\Poll\InvalidHandleException $e) {
    echo $e->getMessage(), "\n";
}

echo "Events count: ", count($poll_ctx->wait(Time\Duration::fromSeconds(0))), "\n";

$watcher->remove();
var_dump($watcher->isActive());
})();

echo "--- poll_stream_handle_fd_release (Auto)\n";
(function () {
function open_fds(): int {
    return count(scandir('/proc/self/fd'));
}

$before = open_fds();
for ($i = 0; $i < 100; $i++) {
    list($r, $w) = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);
    $h = new StreamPollHandle($r);
    unset($h, $r, $w);
}
gc_collect_cycles();
$delta = open_fds() - $before;

// Without the fix each handle pins its stream, leaking ~100 fds.
var_dump($delta < 10);
})();

echo "--- poll_stream_modify_oneshot_flag (Auto)\n";
(function () {


[$r, $w] = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = pt_stream_poll_add($ctx, $r, [Io\Poll\Event::Read]);
fwrite($w, "a");

echo "Level: ", count($ctx->wait(Time\Duration::fromSeconds(0))), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";

// Read stays registered, only the one-shot flag changes
$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
echo "One-shot: ", count($ctx->wait(Time\Duration::fromSeconds(0))), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($watcher->isActive());

// Back to level-triggered, which re-arms the watcher
$watcher->modifyEvents([Io\Poll\Event::Read]);
echo "Level: ", count($ctx->wait(Time\Duration::fromSeconds(0))), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";

// Add write to a one-shot read, only one event is reported for the watcher
$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot]);
$events = $ctx->wait(Time\Duration::fromSeconds(0));
echo "Read+write one-shot: ", count($events), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($events[0] === $watcher);

$watcher->remove();
})();

echo "--- poll_stream_oneshot_rearm (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$handle = new StreamPollHandle($r);
$watcher = $ctx->add($handle, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "data");

fwrite($w, "a");
echo "Events count: ", count($ctx->wait(Time\Duration::fromMicroseconds(100000))), "\n";
var_dump(fread($r, 10));

fwrite($w, "b");
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($watcher->isActive());

try {
    $ctx->add($handle, [Io\Poll\Event::Read]);
} catch (Io\Poll\HandleAlreadyWatchedException $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
echo "Events count: ", count($events), "\n";
var_dump($events[0] === $watcher);
var_dump(fread($r, 10));

$watcher->remove();
var_dump($watcher->isActive());
})();

echo "--- poll_stream_sock_modify_write (Auto)\n";
(function () {
list($socket1, $socket2) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

$watcher = pt_stream_poll_add($poll_ctx, $socket2, [Io\Poll\Event::Write], "socket_data");
$watcher->modify([Io\Poll\Event::Write], "modified_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'modified_data']
]);
})();

echo "--- poll_stream_sock_read (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket_data");

fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_sock_remove_write (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
list($socket2r, $socket2w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

$watcher1w = pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket_data_1");
pt_stream_poll_add($poll_ctx, $socket2w, [Io\Poll\Event::Write], "socket_data_2");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data_1'],
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data_2']
]);

$watcher1w->remove();

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data_2']
]);

// check that both streams are still usable
var_dump(fwrite($socket1w, "test 1"));
var_dump(fwrite($socket2w, "test 2"));
var_dump(fread($socket1r, 100));
var_dump(fread($socket2r, 100));
})();

echo "--- poll_stream_sock_rw_close (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

fwrite($socket1w, "test data");

fclose($socket1r);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    [
        'events' => [
            'default' => [Io\Poll\Event::Write, Io\Poll\Event::Error, Io\Poll\Event::HangUp],
            'Kqueue' => [Io\Poll\Event::Write, Io\Poll\Event::HangUp],
            // On Solaris event ports the peer close may not be folded into a
            // POLLHUP in the same snapshot as the POLLOUT readiness, so HangUp
            // is optional here.
            'EventPorts' => [Io\Poll\Event::Write, [Io\Poll\Event::HangUp]],
        ],
        'data' => 'socket2_data'
    ]
], $poll_ctx);

fclose($socket1w);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_sock_rw_max_events (Auto)\n";
(function () {
$poll_ctx = pt_new_stream_poll();

// Each FD is ready for both read and write. Backends that report read and
// write separately (kqueue) see twice as many events as FDs and have to merge
// them without dropping any FD, filling only half of the maxEvents entries.
$writers = [];
$expected = [];
for ($i = 0; $i < 4; $i++) {
    list($reader, $writer) = pt_new_socket_pair();
    $writers[$i] = $writer;
    pt_stream_poll_add($poll_ctx, $reader, [Io\Poll\Event::Read, Io\Poll\Event::Write], "sock$i");
    pt_write_sleep($writer, "test $i data");
    $expected[] = [
        'events' => [Io\Poll\Event::Read, Io\Poll\Event::Write],
        'data' => "sock$i",
        'read' => "test $i data",
    ];
}

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 8), $expected);

// All read data was drained above, so only write events remain
$expected = [];
for ($i = 0; $i < 4; $i++) {
    $expected[] = ['events' => [Io\Poll\Event::Write], 'data' => "sock$i"];
}
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 8), $expected);
})();

echo "--- poll_stream_sock_rw_multi_edge (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read, Io\Poll\Event::EdgeTriggered], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write, Io\Poll\Event::EdgeTriggered], "socket2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), []);

fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'test data']
]);

fwrite($socket1w, "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);

fwrite($socket1w, " and even more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'more data and even more data']
]);

fclose($socket1r);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    [
        'events' => ['default' => [Io\Poll\Event::Write, Io\Poll\Event::HangUp]],
        'data' => 'socket2_data'
    ]
], $poll_ctx);

fclose($socket1w);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_sock_rw_multi_level (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);

fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'test data']
]);

fwrite($socket1w, "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data']
]);

fwrite($socket1w, " and even more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'more data and even more data']
]);

fclose($socket1r);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    [
        'events' => [
            'default' => [Io\Poll\Event::Write, Io\Poll\Event::HangUp],
            // On Solaris event ports the peer close may not be folded into a
            // POLLHUP in the same snapshot as the POLLOUT readiness, so HangUp
            // is optional here.
            'EventPorts' => [Io\Poll\Event::Write, [Io\Poll\Event::HangUp]],
        ],
        'data' => 'socket2_data'
    ]
], $poll_ctx);

fclose($socket1w);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_sock_rw_single_edge (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read, Io\Poll\Event::EdgeTriggered], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write, Io\Poll\Event::EdgeTriggered], "socket2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);
fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_sock_rw_single_level (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);
fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_sock_write (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data']
]);
})();

echo "--- poll_stream_sock_write_close (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();
list($socket2r, $socket2w) = pt_new_socket_pair();

pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket1w_data");
pt_stream_poll_add($poll_ctx, $socket2w, [Io\Poll\Event::Write], "socket2w_data");

fclose($socket1w);
fclose($socket2w);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_read (Auto)\n";
(function () {
list($socket1r, $socket1w) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket_data");

pt_write_sleep($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_tcp_read_max_events (Auto)\n";
(function () {
list($clients, $servers) = pt_new_tcp_socket_connections(8);
$poll_ctx = pt_new_stream_poll();

for ($i = 0; $i < count($servers); $i++) {
    pt_stream_poll_add($poll_ctx, $servers[$i], [Io\Poll\Event::Read], "server$i");
}

for ($i = 0; $i < count($clients); $i++) {
    pt_write_sleep($clients[$i], "test $i data");
}

// 8 FDs are ready but only 4 events fit into the buffer, so the remaining
// events must be delivered by the following wait() without any duplicates.
$seen = [];
for ($round = 1; $round <= 2; $round++) {
    $watchers = $poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 4);
    echo "Round $round count: " . count($watchers) . "\n";
    foreach ($watchers as $watcher) {
        $data = $watcher->getData();
        if (isset($seen[$data])) {
            echo "Duplicate event for $data\n";
        }
        $seen[$data] = true;
        // Drain so level triggering does not re-report the FD
        fread($watcher->getHandle()->getStream(), 1024);
    }
}

ksort($seen);
echo "Seen: " . implode(',', array_keys($seen)) . "\n";

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), []);
})();

echo "--- poll_stream_tcp_read_multiple_level (Auto)\n";
(function () {
list($clients, $servers) = pt_new_tcp_socket_connections(20);
$poll_ctx = pt_new_stream_poll();

for ($i = 0; $i < count($servers); $i++) {
    pt_stream_poll_add($poll_ctx, $servers[$i], [Io\Poll\Event::Read], "server{$i}_data");
}

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), []);

for ($i = 0; $i < count($clients); $i++) {
    pt_write_sleep($clients[$i], "test $i data");
}

// Build expected events for all 20 connections
$expected_events = [];
for ($i = 0; $i < 20; $i++) {
    $expected_events[] = ['events' => [Io\Poll\Event::Read], 'data' => "server{$i}_data", 'read' => "test $i data"];
}
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), $expected_events);

pt_write_sleep($clients[1], "more data");
pt_write_sleep($clients[2], "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'server1_data', 'read' => 'more data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'server2_data', 'read' => 'more data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_read_one_shot (Auto)\n";
(function () {
list($client1, $server1) = pt_new_tcp_socket_pair();
list($client2, $server2) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client1, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "client1_data");
pt_stream_poll_add($poll_ctx, $server1, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "server1_data");
pt_stream_poll_add($poll_ctx, $client2, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "client2_data");
pt_stream_poll_add($poll_ctx, $server2, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "server2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), []);

pt_write_sleep($client1, "test data");
pt_write_sleep($client2, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'server1_data', 'read' => 'test data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'server2_data', 'read' => 'test data']
]);

pt_write_sleep($client1, "more data");
pt_write_sleep($client2, "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_read_one_shot_max_events (Auto)\n";
(function () {
list($clients, $servers) = pt_new_tcp_socket_connections(8);
$poll_ctx = pt_new_stream_poll();

for ($i = 0; $i < count($servers); $i++) {
    pt_stream_poll_add($poll_ctx, $servers[$i], [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "server$i");
}

for ($i = 0; $i < count($clients); $i++) {
    pt_write_sleep($clients[$i], "test $i data");
}

// 8 oneshot FDs are ready but only 4 events fit into the buffer. The events
// that did not fit must not be consumed - the following wait() has to deliver
// them, and each oneshot event must be delivered exactly once.
$seen = [];
for ($round = 1; $round <= 2; $round++) {
    $watchers = $poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 4);
    echo "Round $round count: " . count($watchers) . "\n";
    foreach ($watchers as $watcher) {
        $data = $watcher->getData();
        if (isset($seen[$data])) {
            echo "Duplicate event for $data\n";
        }
        $seen[$data] = true;
    }
}

ksort($seen);
echo "Seen: " . implode(',', array_keys($seen)) . "\n";

// Every oneshot watcher fired once, so new data must not be reported
pt_write_sleep($clients[0], "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_rw_one_shot (Auto)\n";
(function () {
list($client, $server) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "client_data");
pt_stream_poll_add($poll_ctx, $server, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "server_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Write], 'data' => 'server_data']
]);

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_rw_one_shot_mixed (Auto)\n";
(function () {
list($client, $server) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "client_data");
pt_stream_poll_add($poll_ctx, $server, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "server_data");

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Read, Io\Poll\Event::Write], 'data' => 'server_data']
]);

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_rw_single_level (Auto)\n";
(function () {
list($client, $server) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client, [Io\Poll\Event::Read, Io\Poll\Event::Write], "client_data");
pt_stream_poll_add($poll_ctx, $server, [Io\Poll\Event::Read, Io\Poll\Event::Write], "server_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Write], 'data' => 'server_data']
]);

fwrite($client, "test data");
usleep(10000);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Read, Io\Poll\Event::Write], 'data' => 'server_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_wait_no_add (Auto)\n";
(function () {
$poll_ctx = pt_new_stream_poll();
$events = $poll_ctx->wait(Time\Duration::fromMicroseconds(100000));
pt_print_events($events);
})();

echo "--- poll_watcher_gc_cycle (Auto)\n";
(function () {
class Canary {
    public $ref;
    public function __destruct() {
        echo "Canary freed\n";
    }
}

list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);

$c = new Canary();
$c->ref = $watcher;         // Canary -> Watcher
$watcher->modifyData($c);   // Watcher->data -> Canary (cycle)

unset($ctx, $watcher, $c, $r, $w);

echo "before gc\n";
gc_collect_cycles();
echo "after gc\n";
})();

echo "--- poll_watcher_outlives_context (Auto)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read], "data");

// Drop the Context while still holding the Watcher it returned.
unset($ctx);
gc_collect_cycles();

var_dump($watcher->isActive());

try {
    $watcher->remove();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

try {
    $watcher->modifyEvents([Io\Poll\Event::Write]);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

echo "done\n";
})();

$GLOBALS['pt_backend'] = Io\Poll\Backend::Poll;
echo "--- gh22759 (Poll)\n";
(function () {
[$r, $w] = pt_new_socket_pair();
$context = pt_new_stream_poll();
$handle = new StreamPollHandle($r);

$first = $context->add($handle, [Io\Poll\Event::Read]);
$first->remove();

$ref = WeakReference::create($first);
unset($first);
gc_collect_cycles();
var_dump($ref->get());

$second = $context->add($handle, [Io\Poll\Event::Read]);

unset($context);
gc_collect_cycles();

var_dump($second->isActive());

try {
    $second->remove();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

echo "done\n";
})();

echo "--- poll_clone_not_allowed (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$handle = new StreamPollHandle($r);
$watcher = $ctx->add($handle, [Io\Poll\Event::Read]);

foreach ([$ctx, $handle, $watcher] as $obj) {
    try {
        clone $obj;
    } catch (Throwable $e) {
        echo $e::class, ': ', $e->getMessage(), "\n";
    }
}

echo "done\n";
})();

echo "--- poll_double_construct (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();

$handle = new StreamPollHandle($r);
try {
    $handle->__construct($r);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

$ctx = pt_new_stream_poll();
try {
    $ctx->__construct();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

echo "done\n";
})();

echo "--- poll_stream_add_error_duplicate (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

try {
    pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
})();

echo "--- poll_stream_buffered_level (Poll)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
fwrite($b, "first\nsecond\n");
var_dump(fgets($a)); // "second\n" is now in $a's read buffer, the socket is empty

$ctx = pt_new_stream_poll();
$w = pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read], 'a');

// Returned at once although the descriptor is idle
$start = hrtime(true);
$events = $ctx->wait(Time\Duration::fromSeconds(5));
var_dump(count($events), $events[0] === $w, $events[0]->hasTriggered(Io\Poll\Event::Read));
var_dump(hrtime(true) - $start < 2_000_000_000);
var_dump(stream_get_meta_data($a)['unread_bytes']);

// Level: reported on every wait while the data stays buffered
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));

var_dump(fgets($a));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));

// Write interest is not concerned with read data
fwrite($b, "third\nfourth\n");
var_dump(fgets($a));
$w->modifyEvents([Io\Poll\Event::Write]);
$events = $ctx->wait(Time\Duration::fromSeconds(0));
var_dump(count($events), $events[0]->hasTriggered(Io\Poll\Event::Write), $events[0]->hasTriggered(Io\Poll\Event::Read));

// The buffer counts as soon as Read interest is back
$w->modifyEvents([Io\Poll\Event::Read]);
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
})();

echo "--- poll_stream_buffered_max_events (Poll)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
[$c, $d] = pt_new_socket_pair();
[$e, $f] = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read], 'a');
pt_stream_poll_add($ctx, $c, [Io\Poll\Event::Read], 'c');
pt_stream_poll_add($ctx, $e, [Io\Poll\Event::Read], 'e');

fwrite($b, "first\nsecond\n");
fwrite($d, "first\nsecond\n");
var_dump(fgets($a), fgets($c));
fwrite($f, "x"); // on the socket, not buffered

var_dump(count($ctx->wait(Time\Duration::fromSeconds(0), 1)));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0), 2)));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0), 3)));

var_dump(fgets($a), fgets($c), fread($e, 10));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
})();

echo "--- poll_stream_buffered_merge (Poll)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
[$c, $d] = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$wa = pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read], 'a');
$wc = pt_stream_poll_add($ctx, $c, [Io\Poll\Event::Read], 'c');

// $a: buffered data and an idle socket; $c: data on the socket
fwrite($b, "first\nsecond\n");
var_dump(fgets($a));
fwrite($d, "x");

$events = $ctx->wait(Time\Duration::fromMilliseconds(100));
$seen = [];
foreach ($events as $e) {
    $seen[$e->getData()] = $e->hasTriggered(Io\Poll\Event::Read);
}
ksort($seen);
var_dump($seen);

// $a: buffered data and data on the socket at once: one entry, Read once
fwrite($b, "third\n");
var_dump(fread($c, 10));
$events = $ctx->wait(Time\Duration::fromMilliseconds(100));
var_dump(count($events), $events[0] === $wa, $events[0]->hasTriggered(Io\Poll\Event::Read));
var_dump(fgets($a), fgets($a));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
})();

echo "--- poll_stream_buffered_oneshot (Poll)\n";
(function () {
[$a, $b] = pt_new_socket_pair();
fwrite($b, "first\nsecond\n");
var_dump(fgets($a));

$ctx = pt_new_stream_poll();
$w = pt_stream_poll_add($ctx, $a, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], 'a');

// Fires once from the buffer
$events = $ctx->wait(Time\Duration::fromSeconds(0));
var_dump(count($events), $events[0] === $w);

// Disarmed: neither the buffer nor new data on the socket reports it
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
fwrite($b, "third\n");
var_dump(count($ctx->wait(Time\Duration::fromMilliseconds(50))));
var_dump($w->isActive());

// Re-armed: the buffer reports it at once, again once
$w->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));

// Drained, re-armed: the descriptor reports it
var_dump(fgets($a), fgets($a));
$w->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
var_dump(count($ctx->wait(Time\Duration::fromSeconds(0))));
fwrite($b, "fourth\n");
$events = $ctx->wait(Time\Duration::fromMilliseconds(100));
var_dump(count($events), $events[0]->hasTriggered(Io\Poll\Event::Read));

$w->remove();
var_dump($w->isActive());
})();

echo "--- poll_stream_closed_fd_reuse (Poll)\n";
(function () {
$ctx = pt_new_stream_poll();

list($r0, $w0) = pt_new_socket_pair();
$old = $ctx->add(new StreamPollHandle($r0), [Io\Poll\Event::Read], "old");

// The lowest free fd number is handed out first, so $r1 takes the number $r0 had
fclose($r0);
list($r1, $w1) = pt_new_socket_pair();

$new = $ctx->add(new StreamPollHandle($r1), [Io\Poll\Event::Read], "new");
var_dump($old->isActive());
var_dump($new->isActive());

fwrite($w1, "ping");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events));
var_dump($events[0] === $new);
var_dump($events[0]->getData());

$old->remove();
echo "old removed\n";

$new->remove();
var_dump($new->isActive());
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
})();

echo "--- poll_stream_closed_fd_reuse_unwatched (Poll)\n";
(function () {
$ctx = pt_new_stream_poll();

list($r0, $w0) = pt_new_socket_pair();
$old = $ctx->add(new StreamPollHandle($r0), [Io\Poll\Event::Read], "old");

// The lowest free fd number is handed out first, so $r1 takes the number $r0 had
fclose($r0);
list($r1, $w1) = pt_new_socket_pair();
fwrite($w1, "ping");

echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($old->isActive());

$old->remove();
var_dump($old->isActive());
var_dump(fread($r1, 10));
})();

echo "--- poll_stream_closed_many (Poll)\n";
(function () {
$ctx = pt_new_stream_poll();

list($rk, $wk) = pt_new_socket_pair();
$keep = $ctx->add(new StreamPollHandle($rk), [Io\Poll\Event::Read], "keep");

list($ro, $wo) = pt_new_socket_pair();
$oneshot = $ctx->add(new StreamPollHandle($ro), [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "oneshot");
fwrite($wo, "x");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events), $events[0]->getData());

for ($i = 0; $i < 200; $i++) {
    list($r, $w) = pt_new_socket_pair();
    $watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);
    fclose($r);
    $watcher->remove();
    fclose($w);
}

// The fired one-shot watcher stays disarmed, the kept one is still watched
fwrite($wk, "y");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events), $events[0]->getData());
var_dump($keep->isActive(), $oneshot->isActive());

$oneshot->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events));

list($r, $w) = pt_new_socket_pair();
$new = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read], "new");
fwrite($w, "z");
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
var_dump(count($events));
var_dump($oneshot->isActive());
})();

echo "--- poll_stream_closed_multi_context (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$handle = new StreamPollHandle($r);

$ctx1 = pt_new_stream_poll();
$ctx2 = pt_new_stream_poll();
$w1 = $ctx1->add($handle, [Io\Poll\Event::Read]);
$w2 = $ctx2->add($handle, [Io\Poll\Event::Read]);

fwrite($w, "ping");
fclose($r);

echo "ctx1 events count: ", count($ctx1->wait(Time\Duration::fromSeconds(0))), "\n";
echo "ctx2 events count: ", count($ctx2->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($w1->isActive());
var_dump($w2->isActive());

$w1->remove();
$w2->remove();
echo "removed\n";

fclose($w);
})();

echo "--- poll_stream_closed_watcher_inactive (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);

fwrite($w, "ping");
var_dump($watcher->isActive());

fclose($r);
var_dump($watcher->isActive());

echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";

$watcher->remove();
$watcher->remove();
echo "removed\n";
var_dump($watcher->isActive());

try {
    $watcher->modifyEvents([Io\Poll\Event::Write]);
} catch (Io\Poll\InactiveWatcherException $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

fclose($w);
})();

echo "--- poll_stream_handle_close_then_free (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read]);

// Close the underlying streams before the watcher and handle are freed.
fclose($r);
fclose($w);

unset($watcher, $ctx);
gc_collect_cycles();
echo "ok\n";
})();

echo "--- poll_stream_handle_closed_stream (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

$handle = new StreamPollHandle($r);
$watcher = $poll_ctx->add($handle, [Io\Poll\Event::Read]);
$not_added_yet = new StreamPollHandle($w);

fclose($r);
fclose($w);

var_dump($handle->isValid());
var_dump(get_debug_type($handle->getStream()));

try {
    $watcher->modifyEvents([Io\Poll\Event::Write]);
} catch (Io\Poll\InactiveWatcherException $e) {
    echo $e->getMessage(), "\n";
}

try {
    $poll_ctx->add($not_added_yet, [Io\Poll\Event::Read]);
} catch (Io\Poll\InvalidHandleException $e) {
    echo $e->getMessage(), "\n";
}

echo "Events count: ", count($poll_ctx->wait(Time\Duration::fromSeconds(0))), "\n";

$watcher->remove();
var_dump($watcher->isActive());
})();

echo "--- poll_stream_modify_oneshot_flag (Poll)\n";
(function () {


[$r, $w] = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = pt_stream_poll_add($ctx, $r, [Io\Poll\Event::Read]);
fwrite($w, "a");

echo "Level: ", count($ctx->wait(Time\Duration::fromSeconds(0))), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";

// Read stays registered, only the one-shot flag changes
$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
echo "One-shot: ", count($ctx->wait(Time\Duration::fromSeconds(0))), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($watcher->isActive());

// Back to level-triggered, which re-arms the watcher
$watcher->modifyEvents([Io\Poll\Event::Read]);
echo "Level: ", count($ctx->wait(Time\Duration::fromSeconds(0))), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";

// Add write to a one-shot read, only one event is reported for the watcher
$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot]);
$events = $ctx->wait(Time\Duration::fromSeconds(0));
echo "Read+write one-shot: ", count($events), " ",
    count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($events[0] === $watcher);

$watcher->remove();
})();

echo "--- poll_stream_oneshot_rearm (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$handle = new StreamPollHandle($r);
$watcher = $ctx->add($handle, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "data");

fwrite($w, "a");
echo "Events count: ", count($ctx->wait(Time\Duration::fromMicroseconds(100000))), "\n";
var_dump(fread($r, 10));

fwrite($w, "b");
echo "Events count: ", count($ctx->wait(Time\Duration::fromSeconds(0))), "\n";
var_dump($watcher->isActive());

try {
    $ctx->add($handle, [Io\Poll\Event::Read]);
} catch (Io\Poll\HandleAlreadyWatchedException $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

$watcher->modifyEvents([Io\Poll\Event::Read, Io\Poll\Event::OneShot]);
$events = $ctx->wait(Time\Duration::fromMicroseconds(100000));
echo "Events count: ", count($events), "\n";
var_dump($events[0] === $watcher);
var_dump(fread($r, 10));

$watcher->remove();
var_dump($watcher->isActive());
})();

echo "--- poll_stream_sock_modify_write (Poll)\n";
(function () {
list($socket1, $socket2) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

$watcher = pt_stream_poll_add($poll_ctx, $socket2, [Io\Poll\Event::Write], "socket_data");
$watcher->modify([Io\Poll\Event::Write], "modified_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'modified_data']
]);
})();

echo "--- poll_stream_sock_read (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket_data");

fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_sock_remove_write (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
list($socket2r, $socket2w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

$watcher1w = pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket_data_1");
pt_stream_poll_add($poll_ctx, $socket2w, [Io\Poll\Event::Write], "socket_data_2");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data_1'],
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data_2']
]);

$watcher1w->remove();

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data_2']
]);

// check that both streams are still usable
var_dump(fwrite($socket1w, "test 1"));
var_dump(fwrite($socket2w, "test 2"));
var_dump(fread($socket1r, 100));
var_dump(fread($socket2r, 100));
})();

echo "--- poll_stream_sock_rw_close (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

fwrite($socket1w, "test data");

fclose($socket1r);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    [
        'events' => [
            'default' => [Io\Poll\Event::Write, Io\Poll\Event::Error, Io\Poll\Event::HangUp],
            'Kqueue' => [Io\Poll\Event::Write, Io\Poll\Event::HangUp],
            // On Solaris event ports the peer close may not be folded into a
            // POLLHUP in the same snapshot as the POLLOUT readiness, so HangUp
            // is optional here.
            'EventPorts' => [Io\Poll\Event::Write, [Io\Poll\Event::HangUp]],
        ],
        'data' => 'socket2_data'
    ]
], $poll_ctx);

fclose($socket1w);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_sock_rw_max_events (Poll)\n";
(function () {
$poll_ctx = pt_new_stream_poll();

// Each FD is ready for both read and write. Backends that report read and
// write separately (kqueue) see twice as many events as FDs and have to merge
// them without dropping any FD, filling only half of the maxEvents entries.
$writers = [];
$expected = [];
for ($i = 0; $i < 4; $i++) {
    list($reader, $writer) = pt_new_socket_pair();
    $writers[$i] = $writer;
    pt_stream_poll_add($poll_ctx, $reader, [Io\Poll\Event::Read, Io\Poll\Event::Write], "sock$i");
    pt_write_sleep($writer, "test $i data");
    $expected[] = [
        'events' => [Io\Poll\Event::Read, Io\Poll\Event::Write],
        'data' => "sock$i",
        'read' => "test $i data",
    ];
}

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 8), $expected);

// All read data was drained above, so only write events remain
$expected = [];
for ($i = 0; $i < 4; $i++) {
    $expected[] = ['events' => [Io\Poll\Event::Write], 'data' => "sock$i"];
}
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 8), $expected);
})();

echo "--- poll_stream_sock_rw_multi_level (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);

fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'test data']
]);

fwrite($socket1w, "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data']
]);

fwrite($socket1w, " and even more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'more data and even more data']
]);

fclose($socket1r);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    [
        'events' => [
            'default' => [Io\Poll\Event::Write, Io\Poll\Event::HangUp],
            // On Solaris event ports the peer close may not be folded into a
            // POLLHUP in the same snapshot as the POLLOUT readiness, so HangUp
            // is optional here.
            'EventPorts' => [Io\Poll\Event::Write, [Io\Poll\Event::HangUp]],
        ],
        'data' => 'socket2_data'
    ]
], $poll_ctx);

fclose($socket1w);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_sock_rw_single_level (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket1_data");
pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data']
]);
fwrite($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket2_data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket1_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_sock_write (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'socket_data']
]);
})();

echo "--- poll_stream_sock_write_close (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_socket_pair();
$poll_ctx = pt_new_stream_poll();
list($socket2r, $socket2w) = pt_new_socket_pair();

pt_stream_poll_add($poll_ctx, $socket1w, [Io\Poll\Event::Write], "socket1w_data");
pt_stream_poll_add($poll_ctx, $socket2w, [Io\Poll\Event::Write], "socket2w_data");

fclose($socket1w);
fclose($socket2w);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_read (Poll)\n";
(function () {
list($socket1r, $socket1w) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $socket1r, [Io\Poll\Event::Read], "socket_data");

pt_write_sleep($socket1w, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'socket_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_tcp_read_max_events (Poll)\n";
(function () {
list($clients, $servers) = pt_new_tcp_socket_connections(8);
$poll_ctx = pt_new_stream_poll();

for ($i = 0; $i < count($servers); $i++) {
    pt_stream_poll_add($poll_ctx, $servers[$i], [Io\Poll\Event::Read], "server$i");
}

for ($i = 0; $i < count($clients); $i++) {
    pt_write_sleep($clients[$i], "test $i data");
}

// 8 FDs are ready but only 4 events fit into the buffer, so the remaining
// events must be delivered by the following wait() without any duplicates.
$seen = [];
for ($round = 1; $round <= 2; $round++) {
    $watchers = $poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 4);
    echo "Round $round count: " . count($watchers) . "\n";
    foreach ($watchers as $watcher) {
        $data = $watcher->getData();
        if (isset($seen[$data])) {
            echo "Duplicate event for $data\n";
        }
        $seen[$data] = true;
        // Drain so level triggering does not re-report the FD
        fread($watcher->getHandle()->getStream(), 1024);
    }
}

ksort($seen);
echo "Seen: " . implode(',', array_keys($seen)) . "\n";

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), []);
})();

echo "--- poll_stream_tcp_read_multiple_level (Poll)\n";
(function () {
list($clients, $servers) = pt_new_tcp_socket_connections(20);
$poll_ctx = pt_new_stream_poll();

for ($i = 0; $i < count($servers); $i++) {
    pt_stream_poll_add($poll_ctx, $servers[$i], [Io\Poll\Event::Read], "server{$i}_data");
}

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), []);

for ($i = 0; $i < count($clients); $i++) {
    pt_write_sleep($clients[$i], "test $i data");
}

// Build expected events for all 20 connections
$expected_events = [];
for ($i = 0; $i < 20; $i++) {
    $expected_events[] = ['events' => [Io\Poll\Event::Read], 'data' => "server{$i}_data", 'read' => "test $i data"];
}
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), $expected_events);

pt_write_sleep($clients[1], "more data");
pt_write_sleep($clients[2], "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'server1_data', 'read' => 'more data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'server2_data', 'read' => 'more data']
]);

pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_read_one_shot (Poll)\n";
(function () {
list($client1, $server1) = pt_new_tcp_socket_pair();
list($client2, $server2) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client1, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "client1_data");
pt_stream_poll_add($poll_ctx, $server1, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "server1_data");
pt_stream_poll_add($poll_ctx, $client2, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "client2_data");
pt_stream_poll_add($poll_ctx, $server2, [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "server2_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), []);

pt_write_sleep($client1, "test data");
pt_write_sleep($client2, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Read], 'data' => 'server1_data', 'read' => 'test data'],
    ['events' => [Io\Poll\Event::Read], 'data' => 'server2_data', 'read' => 'test data']
]);

pt_write_sleep($client1, "more data");
pt_write_sleep($client2, "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_read_one_shot_max_events (Poll)\n";
(function () {
list($clients, $servers) = pt_new_tcp_socket_connections(8);
$poll_ctx = pt_new_stream_poll();

for ($i = 0; $i < count($servers); $i++) {
    pt_stream_poll_add($poll_ctx, $servers[$i], [Io\Poll\Event::Read, Io\Poll\Event::OneShot], "server$i");
}

for ($i = 0; $i < count($clients); $i++) {
    pt_write_sleep($clients[$i], "test $i data");
}

// 8 oneshot FDs are ready but only 4 events fit into the buffer. The events
// that did not fit must not be consumed - the following wait() has to deliver
// them, and each oneshot event must be delivered exactly once.
$seen = [];
for ($round = 1; $round <= 2; $round++) {
    $watchers = $poll_ctx->wait(Time\Duration::fromMicroseconds(100000), 4);
    echo "Round $round count: " . count($watchers) . "\n";
    foreach ($watchers as $watcher) {
        $data = $watcher->getData();
        if (isset($seen[$data])) {
            echo "Duplicate event for $data\n";
        }
        $seen[$data] = true;
    }
}

ksort($seen);
echo "Seen: " . implode(',', array_keys($seen)) . "\n";

// Every oneshot watcher fired once, so new data must not be reported
pt_write_sleep($clients[0], "more data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_rw_one_shot (Poll)\n";
(function () {
list($client, $server) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "client_data");
pt_stream_poll_add($poll_ctx, $server, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "server_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Write], 'data' => 'server_data']
]);

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_rw_one_shot_mixed (Poll)\n";
(function () {
list($client, $server) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "client_data");
pt_stream_poll_add($poll_ctx, $server, [Io\Poll\Event::Read, Io\Poll\Event::Write, Io\Poll\Event::OneShot], "server_data");

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Read, Io\Poll\Event::Write], 'data' => 'server_data']
]);

pt_write_sleep($client, "test data");
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), []);
})();

echo "--- poll_stream_tcp_rw_single_level (Poll)\n";
(function () {
list($client, $server) = pt_new_tcp_socket_pair();
$poll_ctx = pt_new_stream_poll();

pt_stream_poll_add($poll_ctx, $client, [Io\Poll\Event::Read, Io\Poll\Event::Write], "client_data");
pt_stream_poll_add($poll_ctx, $server, [Io\Poll\Event::Read, Io\Poll\Event::Write], "server_data");

pt_expect_events($poll_ctx->wait(Time\Duration::fromSeconds(0)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Write], 'data' => 'server_data']
]);

fwrite($client, "test data");
usleep(10000);
pt_expect_events($poll_ctx->wait(Time\Duration::fromMicroseconds(100000)), [
    ['events' => [Io\Poll\Event::Write], 'data' => 'client_data'],
    ['events' => [Io\Poll\Event::Read, Io\Poll\Event::Write], 'data' => 'server_data', 'read' => 'test data']
]);
})();

echo "--- poll_stream_wait_no_add (Poll)\n";
(function () {
$poll_ctx = pt_new_stream_poll();
$events = $poll_ctx->wait(Time\Duration::fromMicroseconds(100000));
pt_print_events($events);
})();

echo "--- poll_watcher_outlives_context (Poll)\n";
(function () {
list($r, $w) = pt_new_socket_pair();
$ctx = pt_new_stream_poll();
$watcher = $ctx->add(new StreamPollHandle($r), [Io\Poll\Event::Read], "data");

// Drop the Context while still holding the Watcher it returned.
unset($ctx);
gc_collect_cycles();

var_dump($watcher->isActive());

try {
    $watcher->remove();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

try {
    $watcher->modifyEvents([Io\Poll\Event::Write]);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}

echo "done\n";
})();

