# Standalone Executables

`zphp build --compile` produces a single executable that contains both the zphp runtime and your compiled PHP bytecode. The result is a self-contained binary that runs anywhere without needing zphp or PHP installed.

## Usage

```
$ zphp build --compile app.php
```

This produces an executable called `app` (the input filename without the extension):

```
$ ./app
Hello from my PHP application
```

## What this means for deployment

Your PHP application becomes a single file you can copy to a server and run. No runtime installation, no dependency management on the target machine, no configuration.

```
$ scp app server:/usr/local/bin/
$ ssh server '/usr/local/bin/app'
```

This works for both scripts (`zphp run` style) and servers (`zphp serve` style). A compiled server binary includes the full HTTP server, TLS support, and everything else `zphp serve` provides.
