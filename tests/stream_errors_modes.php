<?php
// the stream context options error_mode, error_store and error_handler:
// errors raised as warnings (the default), thrown as a StreamException,
// kept quiet, stored for stream_last_errors() or handed to a callback
// (php's ext/standard/tests/streams/stream_errors_*.phpt)

function context(array $options) {
    return stream_context_create(['stream' => $options]);
}

function show_errors(string $title) {
    $errors = stream_last_errors();
    echo $title, ": ", count($errors), " stored\n";
    foreach ($errors as $i => $error) {
        printf("  [%d] %s %s severity=%d terminating=%s: %s\n", $i, $error->code->name, $error->wrapperName, $error->severity, var_export($error->terminating, true), $error->message);
    }
}

// exception mode: the first error's message and code, every error
$context = context(['error_mode' => StreamErrorMode::Exception]);
try {
    fopen('php://nonexistent', 'r', false, $context);
} catch (StreamException $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
    echo "Code: ", $e->getCode(), "\n";
    $errors = $e->getErrors();
    echo "Wrapper: ", $errors[0]->wrapperName, "\n";
    echo "Error code name: ", $errors[0]->code->name, "\n";
    var_dump($errors);
    var_dump($e->getPrevious(), $e->getLine() === __LINE__ - 11);
}

// silent with every error stored: each operation replaces the last
$context = context(['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::All]);
var_dump(fopen('php://nonexistent1', 'r', false, $context));
$error1 = stream_last_errors()[0];
fopen('php://nonexistent2', 'r', false, $context);
$error2 = stream_last_errors()[0];
var_dump($error1 === $error2, $error1 == $error2, stream_last_errors() === stream_last_errors());
show_errors('two operations');
stream_clear_errors();
show_errors('cleared');

// the option values must be the enums
foreach ([['error_mode' => 'invalid'], ['error_store' => 123], ['error_mode' => StreamErrorStore::All]] as $options) {
    try {
        fopen('php://nonexistent', 'r', false, context($options));
        echo "no TypeError\n";
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
// an operation without errors never looks at them
var_dump(is_resource(fopen('php://memory', 'r', false, context(['error_mode' => 'invalid']))));

// Auto stores nothing for Error, the non-terminating errors for Exception
// and everything for Silent
stream_clear_errors();
@fopen('php://nonexistent', 'r', false, context(['error_mode' => StreamErrorMode::Error, 'error_store' => StreamErrorStore::Auto]));
show_errors('error auto');
try {
    fopen('php://nonexistent2', 'r', false, context(['error_mode' => StreamErrorMode::Exception, 'error_store' => StreamErrorStore::Auto]));
} catch (StreamException $e) {
    echo "caught\n";
}
show_errors('exception auto');
fopen('php://nonexistent3', 'r', false, context(['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::Auto]));
show_errors('silent auto');
stream_clear_errors();
fopen('php://nonexistent', 'r', false, context(['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::None]));
show_errors('silent none');
fopen('php://nonexistent', 'r', false, context(['error_mode' => StreamErrorMode::Error, 'error_store' => StreamErrorStore::All]));
show_errors('error all');

// the handler gets the errors whatever the mode
$called = false;
$context = context([
    'error_mode' => StreamErrorMode::Silent,
    'error_handler' => function (array $errors) use (&$called) {
        $called = true;
        echo "Handler called\n";
        foreach ($errors as $error) {
            echo "Wrapper: ", $error->wrapperName, "\n";
            echo "Code: ", $error->code->name, "\n";
            echo "Message: ", $error->message, "\n";
            echo "Terminating: ", $error->terminating ? 'yes' : 'no', "\n";
        }
    },
]);
var_dump(fopen('php://nonexistent', 'r', false, $context), $called);
$context = context(['error_mode' => StreamErrorMode::Error, 'error_handler' => function (array $errors) { echo "handler after the warning\n"; }]);
var_dump(fopen('php://nonexistent', 'r', false, $context));
try {
    fopen('php://nonexistent', 'r', false, context(['error_mode' => StreamErrorMode::Exception, 'error_handler' => function (array $errors) { echo "handler before the throw reaches the caller\n"; }]));
} catch (StreamException $e) {
    echo "caught ", $e->getMessage(), "\n";
}
foreach (['no_such_function', [new stdClass, 'nope'], null] as $handler) {
    try {
        fopen('php://nonexistent', 'r', false, context(['error_mode' => StreamErrorMode::Silent, 'error_handler' => $handler]));
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

// a user stream that returns more than asked for, a non-terminating error,
// and stream_select() on it, two terminating ones
class TestStream
{
    public $context;
    private $position = 0;

    public function stream_open($path, $mode, $options, &$opened_path)
    {
        return true;
    }

    public function stream_read($count)
    {
        $this->position += $count;
        return str_repeat('x', $count + 10);
    }

    public function stream_eof()
    {
        return $this->position >= 100;
    }

    public function stream_stat()
    {
        return [];
    }
}
stream_wrapper_register('test', 'TestStream');
$plain = sys_get_temp_dir() . '/zphp_stream_errors_modes.txt';
file_put_contents($plain, 'plain');

function stream_test_errors($title, $options)
{
    global $plain;
    stream_clear_errors();
    $context = context($options);
    $stream = fopen('test://foo', 'r', false, $context);
    try {
        echo $title, "\n";
        $file = fopen($plain, 'r', false, $context);
        $data = fread($stream, 10);
        $read = [$file, $stream];
        $write = null;
        $except = null;
        stream_select($read, $write, $except, 0, 0, $context);
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    show_errors($title);
}
stream_test_errors('ALL', ['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::All]);
stream_test_errors('NON TERMINATING', ['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::NonTerminating]);
stream_test_errors('TERMINATING', ['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::Terminating]);
stream_test_errors('AUTO EXCEPTION', ['error_mode' => StreamErrorMode::Exception, 'error_store' => StreamErrorStore::Auto]);
stream_test_errors('AUTO ERROR', ['error_mode' => StreamErrorMode::Error, 'error_store' => StreamErrorStore::Auto]);
stream_test_errors('HANDLER ONLY', ['error_handler' => function ($errors) { echo "handler: ", count($errors), "\n"; }]);

// a stream reports with the context it was opened with; stream_select()
// with the one it is given
$stream = fopen('test://foo', 'r', false, context(['error_mode' => StreamErrorMode::Silent]));
var_dump(strlen(fread($stream, 10)));
try {
    $read = [fopen($plain, 'r'), $stream];
    $write = $except = null;
    var_dump(stream_select($read, $write, $except, 0, 0, context(['error_mode' => StreamErrorMode::Exception])));
} catch (StreamException $e) {
    echo "the select's own context: ", $e->getMessage(), "\n";
}
fclose($stream);
unlink($plain);
