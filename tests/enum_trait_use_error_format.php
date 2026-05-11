<?php
trait Labelable {
    public function asLabel(): string {
        return "[" . $this->name . "]";
    }
}

enum Tag: string {
    use Labelable;
    case Foo = "foo";
    case Bar = "bar";
}

echo Tag::Foo->asLabel(), "\n";
echo Tag::Bar->asLabel(), "\n";
foreach (Tag::cases() as $t) echo $t->asLabel(), " ";
echo "\n";

enum Status: string {
    case Active = "active";
    case Pending = "pending";
}

try {
    Status::from("missing");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

try {
    Status::from(123);
} catch (Throwable $e) {
    echo get_class($e), "\n";
}

echo Status::tryFrom("active")->name, "\n";
var_dump(Status::tryFrom("nope"));

trait Renderer {
    public function render(): string {
        return "render " . $this->name;
    }
}
trait Describer {
    public function describe(): string {
        return "describe " . $this->name;
    }
}

enum Multi: string {
    use Renderer, Describer;
    case A = "a";
    case B = "b";
}

echo Multi::A->render(), "\n";
echo Multi::A->describe(), "\n";
echo Multi::B->render(), "\n";
