<?php
// stream error operations inside one another: a user stream's methods run
// stream functions of their own, handlers start operations, a legacy error
// handler raises stream errors while warnings are reported, a handler
// throws or closes the stream (php's stream_errors_*.phpt, gh23262 and
// gh23264)

set_include_path('.');

class ErrorStream
{
    public $context;
    public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
    public function stream_read(int $count): string { return str_repeat('A', $count + 1); }
    public function stream_eof(): bool { return true; }
    public function stream_stat(): array { return []; }
}

class OuterStream
{
    public $context;
    public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
    public function stream_read(int $count): string
    {
        $inner = fopen('error-stream://x', 'r', false, $GLOBALS['ctx']);
        fread($inner, 1);
        fclose($inner);
        return 'x';
    }
    public function stream_eof(): bool { return true; }
    public function stream_stat(): array { return []; }
}

class NestingStream
{
    public $context;
    public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
    public function stream_read(int $count): string
    {
        $inner = fopen('php://memory', 'r');
        fread($inner, 1);
        fclose($inner);
        return 'x';
    }
    public function stream_eof(): bool { return true; }
    public function stream_stat(): array { return []; }
}

class DeepStream
{
    public $context;
    public static int $left = 0;
    public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
    public function stream_read(int $count): string
    {
        if (--self::$left > 0) {
            $f = fopen('deep-stream://x', 'r', false, $GLOBALS['ctx']);
            $s = fread($f, 1);
            fclose($f);
            return $s;
        }
        return str_repeat('A', $count + 1);
    }
    public function stream_eof(): bool { return true; }
    public function stream_stat(): array { return []; }
}

class WideStream
{
    public $context;
    public static int $left = 0;
    public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
    public function stream_read(int $count): string
    {
        if (--self::$left > 0) {
            $f = fopen('wide-stream://x', 'r');
            $s = fread($f, 1);
            fclose($f);
            return $s;
        }
        return 'x';
    }
    public function stream_eof(): bool { return true; }
    public function stream_stat(): array { return []; }
}

class ProxyStream
{
    public $context;
    private int $reads = 0;
    public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
    public function stream_read(int $count): string
    {
        $this->reads++;
        if ($this->reads === 2) {
            $inner = fopen('error-stream://x', 'r', false, $GLOBALS['innerCtx']);
            fread($inner, 1);
            fclose($inner);
        }
        return $this->reads <= 2 ? str_repeat('B', $count + 1) : '';
    }
    public function stream_eof(): bool { return $this->reads >= 3; }
    public function stream_stat(): array { return []; }
}

class InvalidEofStream
{
    public $context;
    public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
    public function stream_eof() { return []; }
    public function stream_stat(): array { return []; }
}

foreach (['error-stream' => 'ErrorStream', 'outer-stream' => 'OuterStream', 'nesting-stream' => 'NestingStream', 'deep-stream' => 'DeepStream', 'wide-stream' => 'WideStream', 'proxy' => 'ProxyStream', 'invalid-eof' => 'InvalidEofStream'] as $scheme => $class) {
    stream_wrapper_register($scheme, $class);
}

echo "--- errors raised inside a handler are reported outside its operation\n";
$ctx = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Silent,
    'error_handler' => static function (array $errors): void {
        echo "handler start: {$errors[0]->code->name}\n";
        include 'zphp_stream_errors_nesting_missing.inc';
        echo "handler end\n";
    },
]]);
$stream = fopen('outer-stream://x', 'r');
var_dump(fread($stream, 1));
fclose($stream);
var_dump(count(stream_last_errors()));

echo "--- deeply nested operations, and more started from the handler\n";
stream_clear_errors();
$busy = false;
$ctx = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Silent,
    'error_store' => StreamErrorStore::All,
    'error_handler' => static function (array $errors) use (&$busy): void {
        echo "handler: {$errors[0]->code->name}\n";
        if ($busy) {
            return;
        }
        $busy = true;
        WideStream::$left = 8;
        $f = fopen('wide-stream://x', 'r');
        fread($f, 1);
        fclose($f);
        $busy = false;
    },
]]);
DeepStream::$left = 9;
$stream = fopen('deep-stream://x', 'r', false, $ctx);
var_dump(fread($stream, 1));
fclose($stream);
var_dump(count(stream_last_errors()));

echo "--- a handler that throws\n";
$ctx = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Silent,
    'error_store' => StreamErrorStore::All,
    'error_handler' => static function (array $errors): void {
        throw new RuntimeException("handler: {$errors[0]->code->name}");
    },
]]);
for ($i = 0; $i < 2; $i++) {
    $stream = fopen('error-stream://x', 'r', false, $ctx);
    try {
        var_dump(fread($stream, 1));
    } catch (RuntimeException $e) {
        echo $e->getMessage(), "\n";
    }
    var_dump(count(stream_last_errors()));
    fclose($stream);
}

echo "--- a legacy error handler raising stream errors while a warning is reported\n";
$calls = 0;
set_error_handler(static function (int $severity, string $message) use (&$calls): bool {
    $calls++;
    echo "handler: $message\n";
    include 'zphp_stream_errors_nesting_missing.inc';
    echo "handler end\n";
    return true;
});
$stream = fopen('error-stream://x', 'r');
var_dump(fread($stream, 1));
fclose($stream);
var_dump($calls);
restore_error_handler();

echo "--- unwinding a nested operation restores the parent\n";
$busy = false;
set_error_handler(static function (int $severity, string $message) use (&$busy): bool {
    echo "handler: $message\n";
    if ($busy) {
        return true;
    }
    $busy = true;
    $s = fopen('nesting-stream://x', 'r');
    fread($s, 1);
    fclose($s);
    $busy = false;
    return true;
});
$stream = fopen('error-stream://x', 'r');
var_dump(fread($stream, 1));
fclose($stream);
restore_error_handler();

echo "--- wrapper errors after a nested operation are still reported\n";
stream_clear_errors();
$innerCtx = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Silent,
    'error_handler' => static function (array $errors): void {
        echo "inner handler: " . count($errors) . " error(s): {$errors[0]->code->name}\n";
    },
]]);
$outerCtx = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Silent,
    'error_store' => StreamErrorStore::All,
    'error_handler' => static function (array $errors): void {
        echo "outer handler: " . count($errors) . " error(s)\n";
        foreach ($errors as $error) {
            echo "  {$error->code->name}: {$error->message}\n";
        }
    },
]]);
$stream = fopen('proxy://x', 'r', false, $outerCtx);
var_dump(strlen(stream_get_contents($stream)));
fclose($stream);
var_dump(count(stream_last_errors()));

echo "--- a handler that opens a stream with its own context\n";
$ctx = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Silent,
    'error_handler' => static function (array $errors): void {
        echo "handler: " . count($errors) . " error(s)\n";
    },
]]);
$stream = fopen('error-stream://x', 'r', false, $ctx);
var_dump(fread($stream, 1));
fclose($stream);

echo "--- the handler closes the stream (gh23262)\n";
$stream = null;
$context = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Silent,
    'error_handler' => static function (array $errors) use (&$stream): void {
        echo "handler: {$errors[0]->code->name}\n";
        fclose($stream);
    },
]]);
$stream = fopen('invalid-eof://input', 'r', false, $context);
$meta = stream_get_meta_data($stream);
var_dump($meta['eof'], $meta['wrapper_type'], $meta['uri']);

echo "--- a legacy handler closes the stream, the context unset (gh23264)\n";
$context = stream_context_create(['stream' => [
    'error_mode' => StreamErrorMode::Error,
    'error_handler' => static function (array $errors): void {
        echo "handler: {$errors[0]->code->name}\n";
    },
]]);
$stream = fopen('error-stream://input', 'r', false, $context);
unset($context);
set_error_handler(static function (int $severity, string $message) use (&$stream): bool {
    echo "legacy: $message\n";
    fclose($stream);
    return true;
});
var_dump(fread($stream, 1));
restore_error_handler();
