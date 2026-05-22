<?php
// covers: late static binding - new static(), static:: method dispatch,
//   static:: on static properties (per-class storage), static::class vs
//   self::class, parent::, static:: inside trait methods, static:: inside a
//   closure created in a static method, abstract static methods resolved
//   through static::, the static return type

require __DIR__ . '/Models.php';

final class User extends Model
{
    use Timestamped;

    protected static array $rows = [];

    public static function kind(): string
    {
        return 'user';
    }

    public static function tag(): string
    {
        return parent::tag() . ':user';
    }
}

final class Post extends Model
{
    use Timestamped;

    protected static array $rows = [];

    public static function kind(): string
    {
        return 'post';
    }
}

echo "== factories (new static) ==\n";
$u = User::make(['name' => 'ada']);
$p = Post::make(['title' => 'hello']);
User::make(['name' => 'grace']);
echo 'u is ' . get_class($u) . "\n";
echo 'p is ' . get_class($p) . "\n";

echo "== per-class static storage ==\n";
echo 'users: ' . User::count() . "\n";
echo 'posts: ' . Post::count() . "\n";
echo 'first user: ' . User::first()->get('name') . "\n";

echo "== static:: vs self:: ==\n";
echo $u->lineage() . "\n";
echo $p->lineage() . "\n";

echo "== parent:: ==\n";
echo 'User::tag = ' . User::tag() . "\n";
echo 'Post::tag = ' . Post::tag() . "\n";

echo "== static:: in trait methods ==\n";
echo $u->describe() . "\n";
echo $p->describe() . "\n";

echo "== static:: in a closure ==\n";
print_r(User::decorateAll(['a', 'b']));
print_r(Post::decorateAll(['x', 'y']));

echo "== resolved kinds ==\n";
echo User::kind() . ' / ' . Post::kind() . "\n";

echo "done\n";
