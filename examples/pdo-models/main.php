<?php
// covers: PDO with sqlite :memory:, prepared statements (named and positional),
//   FETCH_ASSOC, execute/fetch/fetchAll, transactions (begin/commit/rollback),
//   exec for DDL, query for SELECT, lastInsertId, repository pattern

class Database
{
    private $pdo;

    public function __construct(string $dsn)
    {
        $this->pdo = new PDO($dsn);
    }

    public function getPdo()
    {
        return $this->pdo;
    }

    public function exec(string $sql): int
    {
        return $this->pdo->exec($sql);
    }
}

class UserRepository
{
    private $db;

    public function __construct(Database $db)
    {
        $this->db = $db;
    }

    public function createTable(): void
    {
        $this->db->exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL, age INTEGER)");
    }

    public function insert(string $name, string $email, int $age): bool
    {
        $stmt = $this->db->getPdo()->prepare("INSERT INTO users (name, email, age) VALUES (:name, :email, :age)");
        return $stmt->execute(["name" => $name, "email" => $email, "age" => $age]);
    }

    public function findById(int $id): ?array
    {
        $stmt = $this->db->getPdo()->prepare("SELECT * FROM users WHERE id = ?");
        $stmt->execute([$id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row === false) return null;
        return $row;
    }

    public function findByEmail(string $email): ?array
    {
        $stmt = $this->db->getPdo()->prepare("SELECT * FROM users WHERE email = :email");
        $stmt->execute(["email" => $email]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row === false) return null;
        return $row;
    }

    public function all(): array
    {
        $stmt = $this->db->getPdo()->query("SELECT * FROM users ORDER BY name");
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    public function count(): int
    {
        $stmt = $this->db->getPdo()->query("SELECT COUNT(*) as cnt FROM users");
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return (int) $row["cnt"];
    }

    public function updateAge(int $id, int $age): bool
    {
        $stmt = $this->db->getPdo()->prepare("UPDATE users SET age = ? WHERE id = ?");
        return $stmt->execute([$age, $id]);
    }

    public function delete(int $id): bool
    {
        $stmt = $this->db->getPdo()->prepare("DELETE FROM users WHERE id = ?");
        return $stmt->execute([$id]);
    }
}

// setup
$db = new Database("sqlite::memory:");
$repo = new UserRepository($db);
$repo->createTable();

// insert users
$repo->insert("Alice", "alice@example.com", 30);
$repo->insert("Bob", "bob@example.com", 25);
$repo->insert("Charlie", "charlie@example.com", 35);
echo "inserted 3 users\n";
echo "count: " . $repo->count() . "\n";

// find by id
$user = $repo->findById(1);
echo "by id: " . $user["name"] . " " . $user["email"] . "\n";

// find by email
$user = $repo->findByEmail("bob@example.com");
echo "by email: " . $user["name"] . " age " . $user["age"] . "\n";

// list all
$all = $repo->all();
foreach ($all as $u) {
    echo "  " . $u["name"] . " (" . $u["email"] . ")\n";
}

// update
$repo->updateAge(2, 26);
$updated = $repo->findById(2);
echo "updated age: " . $updated["age"] . "\n";

// delete
$repo->delete(3);
echo "after delete: " . $repo->count() . "\n";

// transaction test
$db->getPdo()->beginTransaction();
$repo->insert("Dave", "dave@example.com", 40);
$db->getPdo()->rollBack();
echo "after rollback: " . $repo->count() . "\n";

$db->getPdo()->beginTransaction();
$repo->insert("Eve", "eve@example.com", 28);
$db->getPdo()->commit();
echo "after commit: " . $repo->count() . "\n";

echo "done\n";
