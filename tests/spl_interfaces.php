<?php
// php's SPL interfaces exist and the built-in classes implement them;
// ReflectionClass::isInternal tells built-ins from declarations in scripts
foreach (['SeekableIterator', 'OuterIterator', 'SplObserver', 'SplSubject', 'RecursiveIterator', 'Countable'] as $name) {
    $r = new ReflectionClass($name);
    echo $name, ': ', var_export(interface_exists($name), true), ' ', var_export($r->isInternal(), true), "\n";
}
foreach (['ArrayIterator', 'SplObjectStorage', 'DirectoryIterator', 'FilesystemIterator', 'IteratorIterator', 'RecursiveIteratorIterator'] as $class) {
    $interfaces = array_keys(class_implements($class));
    sort($interfaces);
    echo $class, ': ', implode(', ', array_intersect($interfaces, ['OuterIterator', 'SeekableIterator', 'Iterator', 'Traversable'])), "\n";
}

class Feed implements SplSubject {
    private array $observers = [];
    public function attach(SplObserver $observer): void { $this->observers[] = $observer; }
    public function detach(SplObserver $observer): void {}
    public function notify(): void { foreach ($this->observers as $o) $o->update($this); }
}
class Reader implements SplObserver {
    public function update(SplSubject $subject): void { echo 'updated by ', get_class($subject), "\n"; }
}
$feed = new Feed;
$feed->attach(new Reader);
$feed->notify();

interface Mine {}
trait Helper {}
enum Suit { case Hearts; }
foreach (['Feed', 'Mine', 'Helper', 'Suit', 'stdClass', 'ArrayObject', 'Closure', 'Generator'] as $name) {
    echo $name, ': ', var_export((new ReflectionClass($name))->isInternal(), true), ' ', var_export((new ReflectionClass($name))->isUserDefined(), true), "\n";
}
var_dump((new ReflectionMethod('Feed', 'notify'))->isInternal(), (new ReflectionMethod('ArrayIterator', 'seek'))->isInternal());
