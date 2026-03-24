<?php
namespace App\Services;

use App\Models\User;
use App\Models\Post;

class ContentService {
    private $cache;
    private $ttl = 3600;
    private static $instance = null;

    public function __construct($cache, int $ttl = 3600) {
        $this->cache = $cache;
        $this->ttl = $ttl;
    }

    public static function getInstance($cache) {
        if (self::$instance === null) {
            self::$instance = new ContentService($cache);
        }
        return self::$instance;
    }

    public function getPostsForUser($user, int $page = 1, int $perPage = 20): array {
        $cacheKey = "user_posts_" . $user->getId() . "_" . $page . "_" . $perPage;
        $cached = $this->cache->get($cacheKey);

        if ($cached !== null) {
            return $cached;
        }

        $posts = $this->fetchPosts($user, $page, $perPage);
        $this->cache->set($cacheKey, $posts, $this->ttl);
        return $posts;
    }

    private function fetchPosts($user, int $page, int $perPage): array {
        $offset = ($page - 1) * $perPage;
        $raw = [];

        return array_map(function($post) use ($user) {
            return $this->transformPost($post, $user);
        }, $raw);
    }

    private function transformPost($post, $author): array {
        $tags = array_map(fn($tag) => $tag->getName(), $post->getTags());

        $status = match($post->getStatus()) {
            'draft' => 'Draft',
            'published' => 'Published',
            'archived' => 'Archived',
            default => 'Unknown'
        };

        return [
            'id' => $post->getId(),
            'title' => $post->getTitle(),
            'slug' => $this->generateSlug($post->getTitle()),
            'excerpt' => $this->truncate($post->getBody(), 200),
            'author' => [
                'id' => $author->getId(),
                'name' => $author->getName(),
                'avatar' => $author->getAvatar(),
            ],
            'tags' => $tags,
            'status' => $status,
            'created_at' => $post->getCreatedAt(),
            'updated_at' => $post->getUpdatedAt(),
            'is_featured' => $post->isFeatured(),
            'comment_count' => $post->getCommentCount(),
        ];
    }

    private function generateSlug(string $title): string {
        $slug = strtolower($title);
        $slug = preg_replace('/[^a-z0-9]+/', '-', $slug);
        $slug = trim($slug, '-');
        return $slug;
    }

    private function truncate(string $text, int $length): string {
        if (strlen($text) <= $length) {
            return $text;
        }
        $truncated = substr($text, 0, $length);
        $lastSpace = strrpos($truncated, ' ');
        if ($lastSpace !== false) {
            $truncated = substr($truncated, 0, $lastSpace);
        }
        return $truncated . '...';
    }
}

interface Repository {
    public function find(int $id);
    public function findAll(array $criteria = []): array;
    public function save($entity): bool;
    public function delete(int $id): bool;
}

class BaseRepository implements Repository {
    protected $table;
    protected $connection;

    public function __construct($connection) {
        $this->connection = $connection;
    }

    public function find(int $id) {
        $results = $this->connection->query(
            "SELECT * FROM " . $this->table . " WHERE id = ?",
            [$id]
        );
        return count($results) > 0 ? $this->hydrate($results[0]) : null;
    }

    public function findAll(array $criteria = []): array {
        $where = '';
        $params = [];

        if (count($criteria) > 0) {
            $conditions = [];
            foreach ($criteria as $key => $value) {
                if (is_array($value)) {
                    $placeholders = implode(', ', array_fill(0, count($value), '?'));
                    $conditions[] = $key . " IN (" . $placeholders . ")";
                    foreach ($value as $v) {
                        $params[] = $v;
                    }
                } elseif ($value === null) {
                    $conditions[] = $key . " IS NULL";
                } else {
                    $conditions[] = $key . " = ?";
                    $params[] = $value;
                }
            }
            $where = ' WHERE ' . implode(' AND ', $conditions);
        }

        $results = $this->connection->query(
            "SELECT * FROM " . $this->table . $where,
            $params
        );

        return array_map(fn($row) => $this->hydrate($row), $results);
    }

    public function save($entity): bool {
        $data = $this->extract($entity);

        if ($entity->getId() !== null) {
            $sets = [];
            $params = [];
            foreach ($data as $key => $value) {
                if ($key === 'id') {
                    continue;
                }
                $sets[] = $key . " = ?";
                $params[] = $value;
            }
            $params[] = $entity->getId();
            $sql = "UPDATE " . $this->table . " SET " . implode(', ', $sets) . " WHERE id = ?";
            return $this->connection->execute($sql, $params);
        }

        $columns = implode(', ', array_keys($data));
        $placeholders = implode(', ', array_fill(0, count($data), '?'));
        $sql = "INSERT INTO " . $this->table . " (" . $columns . ") VALUES (" . $placeholders . ")";
        return $this->connection->execute($sql, array_values($data));
    }

    public function delete(int $id): bool {
        return $this->connection->execute(
            "DELETE FROM " . $this->table . " WHERE id = ?",
            [$id]
        );
    }

    protected function hydrate(array $row) {
        return $row;
    }

    protected function extract($entity): array {
        return [];
    }
}

class UserRepository extends BaseRepository {
    protected $table = 'users';

    protected function hydrate(array $row) {
        $user = new User();
        $user->setId($row['id']);
        $user->setName($row['name']);
        $user->setEmail($row['email']);
        $user->setCreatedAt($row['created_at']);
        return $user;
    }

    protected function extract($entity): array {
        return [
            'name' => $entity->getName(),
            'email' => $entity->getEmail(),
            'password_hash' => $entity->getPasswordHash(),
            'created_at' => $entity->getCreatedAt(),
            'updated_at' => date('Y-m-d H:i:s'),
        ];
    }

    public function findByEmail(string $email) {
        $results = $this->findAll(['email' => $email]);
        return count($results) > 0 ? $results[0] : null;
    }

    public function findActive(): array {
        return $this->findAll(['is_active' => 1]);
    }
}

trait Timestampable {
    private $createdAt;
    private $updatedAt;

    public function getCreatedAt(): ?string {
        return $this->createdAt;
    }

    public function setCreatedAt(string $value): void {
        $this->createdAt = $value;
    }

    public function getUpdatedAt(): ?string {
        return $this->updatedAt;
    }

    public function setUpdatedAt(string $value): void {
        $this->updatedAt = $value;
    }

    public function touch(): void {
        $this->updatedAt = date('Y-m-d H:i:s');
    }
}

trait SoftDeletable {
    private $deletedAt = null;

    public function softDelete(): void {
        $this->deletedAt = date('Y-m-d H:i:s');
    }

    public function restore(): void {
        $this->deletedAt = null;
    }

    public function isDeleted(): bool {
        return $this->deletedAt !== null;
    }
}

class EventDispatcher {
    private $listeners = [];

    public function listen(string $event, callable $callback, int $priority = 0): void {
        $this->listeners[$event][] = [
            'callback' => $callback,
            'priority' => $priority,
        ];
    }

    public function dispatch(string $event, array $payload = []): array {
        if (!isset($this->listeners[$event])) {
            return [];
        }

        $sorted = $this->listeners[$event];
        usort($sorted, function($a, $b) {
            return $b['priority'] - $a['priority'];
        });

        $results = [];
        foreach ($sorted as $listener) {
            $result = ($listener['callback'])($payload);
            if ($result !== null) {
                $results[] = $result;
            }
            if (isset($payload['_stop']) && $payload['_stop'] === true) {
                break;
            }
        }

        return $results;
    }

    public function hasListeners(string $event): bool {
        return isset($this->listeners[$event]) && count($this->listeners[$event]) > 0;
    }

    public function removeListeners(string $event): void {
        unset($this->listeners[$event]);
    }
}

class Validator {
    private $rules = [];
    private $errors = [];

    public function addRule(string $field, string $rule, $param = null) {
        $this->rules[] = [
            'field' => $field,
            'rule' => $rule,
            'param' => $param,
        ];
        return $this;
    }

    public function validate(array $data): bool {
        $this->errors = [];

        foreach ($this->rules as $rule) {
            $field = $rule['field'];
            $value = $data[$field] ?? null;

            switch ($rule['rule']) {
                case 'required':
                    if ($value === null || $value === '') {
                        $this->errors[$field][] = $field . " is required";
                    }
                    break;
                case 'email':
                    if ($value !== null && strpos($value, '@') === false) {
                        $this->errors[$field][] = $field . " must be a valid email";
                    }
                    break;
                case 'min_length':
                    if ($value !== null && strlen($value) < $rule['param']) {
                        $this->errors[$field][] = $field . " must be at least " . $rule['param'] . " characters";
                    }
                    break;
                case 'max_length':
                    if ($value !== null && strlen($value) > $rule['param']) {
                        $this->errors[$field][] = $field . " must be at most " . $rule['param'] . " characters";
                    }
                    break;
                default:
                    break;
            }
        }

        return count($this->errors) === 0;
    }

    public function getErrors(): array {
        return $this->errors;
    }
}

function processItems(array $items, callable $transform, callable $filter): array {
    $result = [];

    for ($i = 0; $i < count($items); $i++) {
        $item = $transform($items[$i]);
        if ($filter($item)) {
            $result[] = $item;
        }
    }

    return $result;
}

function buildTree(array $items, $parentId = null): array {
    $tree = [];

    foreach ($items as $item) {
        if ($item['parent_id'] === $parentId) {
            $children = buildTree($items, $item['id']);
            if (count($children) > 0) {
                $item['children'] = $children;
            }
            $tree[] = $item;
        }
    }

    return $tree;
}

function memoize(callable $fn): callable {
    $cache = [];
    return function() use ($fn, $cache) {
        $key = "memoized";
        if (!isset($cache[$key])) {
            return $fn();
        }
        return $cache[$key];
    };
}

function retry(callable $fn, int $maxAttempts = 3) {
    $lastException = null;

    for ($attempt = 1; $attempt <= $maxAttempts; $attempt++) {
        try {
            return $fn();
        } catch (\Exception $e) {
            $lastException = $e;
        }
    }

    throw $lastException;
}

function pipeline(array $stages): callable {
    return function($input) use ($stages) {
        $result = $input;
        foreach ($stages as $stage) {
            $result = $stage($result);
        }
        return $result;
    };
}
