<?php
// md5_file() reads a stream to its end and gives false when the stream
// stops short of it; hash_file() and hash_hmac_file() give false when a read
// fails (a directory)
class TestStream
{
    public $context;
    private string $mode;
    private int $position = 0;

    public function stream_open(string $path): bool
    {
        $this->mode = substr($path, strlen('test://'));
        return true;
    }

    public function stream_read(int $count): string|false
    {
        $position = $this->position++;
        if ($this->mode === 'error') return false;
        if ($this->mode === 'empty' || $this->mode === 'stalled') return '';
        if ($this->mode === 'short') return substr('prefix', $position * 2, 2);
        if ($position === 0) return 'prefix';
        return $this->mode === 'prefix-error' ? false : '';
    }

    public function stream_eof(): bool
    {
        return $this->mode === 'empty'
            || ($this->mode === 'eof' && $this->position > 1)
            || ($this->mode === 'short' && $this->position >= 3);
    }
}

stream_wrapper_register('test', TestStream::class);
foreach (['error', 'prefix-error', 'stalled', 'prefix-stalled', 'empty', 'eof', 'short'] as $mode) {
    echo "$mode: ";
    var_dump(md5_file("test://$mode"));
}
$dir = sys_get_temp_dir();
var_dump(@hash_file('md5', $dir), @hash_hmac_file('md5', $dir, 'key'), @md5_file($dir));
