<?php

require __DIR__ . "/Database.php";

class UserRepository
{
    private Database $db;
    private Logger $logger;

    public function __construct(Logger $logger)
    {
        $this->db = Database::getInstance();
        $this->logger = $logger;
        $this->db->createTable("users", ["id", "name", "email", "active"]);
    }

    public function create(string $name, string $email): array
    {
        $user = [
            "id" => $this->db->count("users") + 1,
            "name" => $name,
            "email" => $email,
            "active" => true,
        ];
        $this->db->insert("users", $user);
        $this->logger->info("created user: $name");
        return $user;
    }

    public function findAll(): array
    {
        return $this->db->select("users");
    }

    public function findByEmail(string $email): ?array
    {
        foreach ($this->db->select("users") as $user) {
            if ($user["email"] === $email) return $user;
        }
        return null;
    }

    public function count(): int
    {
        return $this->db->count("users");
    }
}
