<?php

class Database
{
    private static ?Database $instance = null;
    private array $tables = [];

    private function __construct() {}

    public static function getInstance(): Database
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function createTable(string $name, array $columns): void
    {
        $this->tables[$name] = ["columns" => $columns, "rows" => []];
    }

    public function insert(string $table, array $row): void
    {
        $this->tables[$table]["rows"][] = $row;
    }

    public function select(string $table): array
    {
        return $this->tables[$table]["rows"] ?? [];
    }

    public function count(string $table): int
    {
        return count($this->tables[$table]["rows"] ?? []);
    }

    public function getTableNames(): array
    {
        return array_keys($this->tables);
    }
}
