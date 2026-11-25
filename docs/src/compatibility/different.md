# What Works Differently

zphp is not a drop-in replacement for every PHP application. Test your application and its dependencies against both runtimes, especially when they rely on extension behavior or reflection details.

## Timezones

zphp resolves timezone data using a built-in table, system zoneinfo, and an embedded IANA database fallback. `timezone_identifiers_list()` and `timezone_abbreviations_list()` are implemented.

The identifier list is fixed in the implementation, and the abbreviation list is derived from the built-in table rather than all historical IANA records. The identifier-list implementation does not apply PHP's group or country filters. Do not assume these listings match the PHP version or timezone database installed on your machine.

## Named arguments

User-defined functions support named arguments. Built-in functions use a signature table that covers only part of the standard library; unlisted built-ins fall back to positional arguments. Use positional arguments when a built-in's named-argument behavior has not been verified.

## Polling backends

On Linux, `Io\Poll\Context` offers the epoll and poll backends, and `Backend::Auto` picks epoll, as PHP does. zphp has no kqueue or event ports backend. On macOS and the BSDs, `Backend::Auto` uses poll(2), `Backend::Kqueue` reports itself unavailable, and edge-triggered watchers are refused. On Windows, the WSAPoll backend watches sockets only, as PHP's does. A stream that zphp does not back with a descriptor, such as one that `popen()` returns, cannot be added to a context.

## Package tooling

The built-in package manager reads parts of `composer.json`, but does not implement Composer's full behavior. It skips PHP and extension version constraints, so a successful install does not establish runtime compatibility. Its lock file is not used to pin subsequent installs. See [Package Manager](../tools/packages.md).

## Compatibility checks

The [test coverage](same.md#test-coverage) is evidence for the scenarios exercised, not a guarantee for arbitrary applications. When reporting a difference, include a small PHP script and the output from both runtimes.
