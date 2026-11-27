<?php
// at shutdown every object is destructed in handle order, and an
// SplFileObject closes its stream as it is (spl_filesystem's dtor_obj): a
// later object's destructor using it finds it uninitialized

class Target
{
    public function __construct(public $file, public string $name) {}

    public function __destruct()
    {
        try {
            $this->file->fwrite("x");
            echo "{$this->name}: wrote\n";
        } catch (Error $e) {
            echo "{$this->name}: ", $e->getMessage(), "\n";
        }
    }
}

class Run
{
    public static $file;
    public static $early;
    public static $late;
}

// made before the file, so destructed while it is still open
Run::$early = new Target(null, 'early');
Run::$file = new SplTempFileObject();
Run::$early->file = Run::$file;
Run::$late = new Target(Run::$file, 'late');
echo "end\n";
