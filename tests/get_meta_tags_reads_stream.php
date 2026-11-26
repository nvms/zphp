<?php
// get_meta_tags reads its stream through the stream buffer until the
// stream ends, warning about a read that brings more than it asked for
class ChunkStream
{
    public $context;
    public static array $reads = [];
    private int $chunk = 0;
    private static array $chunks;

    public function stream_open($path, $mode, $options, &$opened): bool
    {
        self::$chunks = [
            '<html><head><meta name="a" content="1">',
            str_repeat(' ', 5000) . '<meta name="b" content="2"></head>',
            '<body><meta name="c" content="3">',
            'never read',
        ];
        $this->chunk = 0;
        self::$reads = [];
        return true;
    }

    public function stream_read(int $count): string|false
    {
        self::$reads[] = $count;
        return self::$chunks[$this->chunk++] ?? '';
    }

    public function stream_eof(): bool
    {
        return $this->chunk >= count(self::$chunks);
    }

    public function stream_stat(): array
    {
        return [];
    }
}

class Oversized
{
    public $context;
    private bool $read = false;

    public function stream_open($path, $mode, $options, &$opened): bool
    {
        return true;
    }

    public function stream_read(int $count): string
    {
        $this->read = true;
        return '<meta name="x" content="y">' . str_repeat('A', $count);
    }

    public function stream_eof(): bool
    {
        return $this->read;
    }
}

stream_wrapper_register('chunks', ChunkStream::class);
stream_wrapper_register('oversized', Oversized::class);
var_dump(get_meta_tags('chunks://page'));
var_dump(ChunkStream::$reads);
var_dump(get_meta_tags('oversized://page'));
