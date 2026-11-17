<?php
// file_get_contents() opens a user wrapper with the context it was given,
// also through php://filter with no filters named, and stats the stream
// before reading it
class DummyWrapper
{
    public $context;

    public function stream_open(string $path, string $mode, int $options, ?string &$opened_path): bool
    {
        echo "open $path\n";
        var_dump(stream_context_get_options($this->context));
        return true;
    }

    public function stream_stat()
    {
        echo "stat\n";
    }

    public function stream_read($count)
    {
        echo "read\n";
        return '';
    }

    public function stream_eof()
    {
        echo "eof\n";
        return true;
    }
}

$context = stream_context_create(['dummy' => ['foo' => 'bar']]);
stream_wrapper_register('dummy', DummyWrapper::class);
var_dump(file_get_contents('dummy://foo', false, $context));
var_dump(file_get_contents('php://filter/resource=dummy://foo', false, $context));
