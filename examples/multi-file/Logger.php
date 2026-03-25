<?php

class Logger
{
    private static array $logs = [];
    private string $prefix;

    public function __construct(string $prefix = "")
    {
        $this->prefix = $prefix;
    }

    public function log(string $level, string $message): void
    {
        $entry = ($this->prefix !== "" ? "[{$this->prefix}] " : "") . strtoupper($level) . ": " . $message;
        self::$logs[] = $entry;
    }

    public function info(string $message): void
    {
        $this->log("info", $message);
    }

    public function error(string $message): void
    {
        $this->log("error", $message);
    }

    public static function getAll(): array
    {
        return self::$logs;
    }

    public static function clear(): void
    {
        self::$logs = [];
    }
}
