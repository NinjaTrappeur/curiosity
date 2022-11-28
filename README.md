# Curiosity - A prototype application for Smart

This repository contains a prototype application for the
[Smart](https://github.com/smartcoop/) cooperative. What we hear about
"prototype" is written in `commence`'s
[README](https://github.com/hypered/commence#readme).

A demonstration instance of Curiosity is running at
[smartcoop.sh](https://smartcoop.sh). It contains
[documentation](https://smartcoop.sh/documentation) that complements this
README.

# Related repositories

- The prototype uses [`design-hs`](https://github.com/hypered/smart-design-hs/) as
  a component library to create HTML pages.

- It also uses [`commence`](https://github.com/hypered/commence) as a
  kind of base "framework" to organize the prototype.

# Content

Curiosity offers multiple tools compiled as a single executable.  The main
command is a web server. In particular it uses the `servant` and `stm`
libraries. The `stm` library is used instead of a regular relational database
(e.g. PostgreSQL). This means the whole state of the application is in memory
instead of in the database.

In addition of the web application, some other commands are provided to better
demonstrate and explore the features of the application.

- `cty serve` run the web application.
- `cty repl` is similar but exposes a REPL instead of a HTTP server to run
  commands and interact with the state.
- `cty-sock` offers a text interface similar to `cty repl` but through a
  UNIX-domain socket, and accepts multiple clients.
- Other commands of `cty` are meant as a client for the `cty-sock` server. It
  can also be run against a local state file.
- `cty parse` is a helper command to play with the command parser used in
  `cty repl`.

**Note**: The commands that can be typed in the REPL are using the same syntax
used by `cty` itself. E.g. `cty state` typed in a shell, is similar to `state`
typed in the Curiosity REPL.

# Tests

Tests covering (partially) the library can be run by entering the Nix shell and
using `cabal`:

```
$ nix-shell
$ cabal test --test-show-details=direct --test-option=--format=checks
```

The same thing can be accomplished with a convenience script:
`scripts/run-tests.sh`, which takes care of entering the Nix shell.

The test suite uses `hspec`, so its [command-line
options](https://hspec.github.io/options.html) apply.

# Running

It is possible to load the code in GHCi (but this exposes the Parse module,
instead of Main):

```
$ nix-shell
$ cabal repl curiosity
```

Instead it's possible to use a helper script to call `:main` with GHCi.

```
$ script/ghci.sh
ghci> :main --help
```

We can also use Cabal to run the example:

```
$ nix-shell
$ cabal run -- cty --help
```

The binary can be built and run also this way, which bypass building the tests:

```
$ cabal build curiosity
$ ./dist-newstyle/build/x86_64-linux/ghc-8.6.5/curiosity-0.1.0.0/x/curiosity/build/curiosity/cty --help
```

We can build a binary with Nix:

```
$ nix-build -A curiosity
$ ./result/bin/cty --help
```

We can have a shell populated with the Curiosity binaries and man pages with:

```
$ nix-shell default.nix -A shell
$ cty --help
```

We can run a local environment running `cty serve` and a Nginx reverse proxy
using:

```
$ nix-build -A run
$ result/bin/run-full-environment
```

The `run-full-environment` script is also available from the above shell:

```
$ nix-shell default.nix -A shell
$ run-full-environment
```

It is also possible to only run Nginx in that shell with `run-nginx`. This is
useful for instance to proxy a `cty serve` running from GHCi.

The `run-vm-test` attribute let's you run a NixOS VM integration test
that mirrors the production setup. You can run it either interactively
or non-interactively:

```sh
$ nix-build -A run-vm-test
# ^ Will run the VM test in a non interactive fashion.
$ nix-build -A run-vm-test.driverInteractive && ./result/bin/nixos-test-driver
> start_all( )
# ^ Will open two qemu windows, one for the server, one for the client.

```

You can use the root account to interactively log in the VMs. The
client can access to the server using the smartcoop.sh domain name.
You can read the relevant [NixOS manual
section](https://nixos.org/manual/nixos/stable/index.html#sec-running-nixos-tests-interactively)
for more informations.

Note: these VMs are not connected to internet, smartcoop.sh refers to
the server VM, not the production machine in that context.

And finally, we can run a local virtual machine running `cty serve` and a Nginx
reverse proxy using [see below](#qemu):

```
$ nix-build -A runvm
$ result/bin/run-nixos-vm
```


# Example REPL commands

The repl can be quit with `exit` (this is configurable) or `Ctrl-d`.

```
> all
> viz user UserLogin "1" "pass"
```

```
> mod user UserCreate "1" "alice" "pass"
UsersModified
    [ UserProfile
        { _userProfileId = UserId "1"
        , _userProfileName = "name"
        , _userProfilePassword = UserPassword Secret :: Text
        }
    ]
```

```
> viz user SelectUserById "1"
UsersVisualised []
```

# `cty`

`cty` is the main command-line tool to interact against a server running on the
same host (through a UNIX-domain socket), or against a state file. Note that
modifying a state file used by a running server should be avoided.

By default, `cty` interacts against a state file called `state.json`. Use the
`--state` option to override the file name. Use the `--socket` option to
instead interact against a running server.

```
$ cty init
State file 'state.json' created.

$ cty state
Right (FullStmDbVisualised (Db {_dbUserProfiles = Identity [], _dbTodos = Identity []}))

$ cty user get alice
Right (UsersVisualised [])

$ cty user create alice pass alice@example.com
Right (UsersModified [UserProfile {_userCreds = UserCreds {_userCredsId = UserId "alice", _userCredsPassword = Password Secret :: Text}, _userProfileName = "alice@example.com"}])

$ cty user get alice
Right (UsersVisualised [UserProfile {_userCreds = UserCreds {_userCredsId = UserId "alice", _userCredsPassword = Password Secret :: Text}, _userProfileName = "alice@example.com"}])

```

# Nix Cache

You can re-use the curiosity binaries built by the CI through a custom Nix binary cache.

On a NixOS system add the following snippet to your system configuration:

```nix
nix.settings = {
  substituters = [ "https://s3.eu-central-003.backblazeb2.com/curiosity-store/" "https://cache.nixos.org/" ];
  trusted-public-keys = [ "curiosity-store:W3LXUB+6DjtZkKV0gEfNXGtTjA+hMqjPUoK6mzzco+w=" "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
}
```

On a non-NixOS system, you can edit the `/etc/nix/nix.conf` file and set the `substituters` and `trusted-public-keys` configuration attributes to:

```
substituters = https://s3.eu-central-003.backblazeb2.com/curiosity-store/ https://cache.nixos.org/
trusted-public-keys = curiosity-store:W3LXUB+6DjtZkKV0gEfNXGtTjA+hMqjPUoK6mzzco+w= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

# Docker image

A Docker image can be built to experiment with the `cty` program, and have
access to man pages. By default, running the image will run Bash.

```
$ nix-build -A docker
$ docker load < result
$ docker run --privileged -it -p 9000:9000 curiosity:vsj9an994jjrw47kv9fj0icjs2f6xq6r
```

Note: the image tag will be different as it depends on the actual image
content.

Note: `-p 9000:9000` is necessary only for `cty serve`.

# Virtual machine images

## QEMU

A virtual machine image that can be run with QEMU can be built and run with:

```
$ nix-build -A runvm
$ result/bin/run-nixos-vm
```

Within the VM, Nginx is setup as a reverse-proxy in front of `cty serve`. You
should be able to confirm that with e.g.:

```
# curl -v 127.0.0.1
# systemctl status nginx
# systemctl status app
```

The VM contains other binaries to help interact with the system, and local
documentation is available as man pages:

```
# cty --help
# man curiosity
```

Use `ctrl-a x` to quit QEMU.

**Note**: when using the `run-nixos-vm` script, a disk file called
`nixos.qcow2` is created. It is re-used on the next call, and may create some
conflicts. Thus it is sometimes necessary to delete it before running the
script again.

## Digital Ocean

An image suitable for Digital Ocean can also be built:

```
$ nix-build -A image
$ ls result/
nixos.qcow2.gz
```

Its weight is about 870MB.


# The `smartcoop.sh` host

These are raw notes about how `smartcoo.sh` was deployed. I (Thu) have used 4
scripts that come from my [nix-notes](https://github.com/noteed/nix-notes)
repository.

Those scripts require some environment variables for authentication, and some
configuration to point to the right services (DigitalOcean instead of AWS). I'm
using `.envrc` and a `s3-config` file, that are not versioned.

-   `upload-image.sh` is used to upload the DigitalOcean image to Spaces
    (similar to S3). This gives us a URL from where the image can be downloaded
    for the next step.

-   `import-image.sh` is used to import the image as a "custom image" into
    DigitalOcean. This requires a URL from which DO will download the file.
    This was provided by the previous step. The command returns quickly, but the
    image will show as "Pending" in the DO web interface for quite a while.

    ```
    $ scripts/import-image.sh
    ID           Name         Type      Distribution    Slug    Public    Min Disk
    110021225    curiosity    custom    Unknown OS              false     0
    ```

    The returned image ID is important for the next step.

-   `create-droplet.sh` is used to create a Drople (i.e. a VM) at DO. The image
    ID from the previous step is hard-coded in the script. In addition, a
    public SSH key of mine, already known by DO, is specified in the script to
    be copied in the Droplet. After that, I note its IP address.

    I've confirmed I could SSH into it:

    ```
    $ ssh root@146.190.30.165
    ```

    I've also confirmed that the same commands shown above for the QEMU case
    also work.

    It seems only 4.4GB are used on the 25GB disk.

-   `deploy.sh` is used to deploy changes to the Droplet, without needing to
    rebuild an image or create a new Droplet. Note that I specified
    `smartcoop.sh` into the script instead of its IP address. See below.

# The `smartcoop.sh` domain

I've bought the domain at Namecheap on 2022-06-08 and configured Namecheap to
use DO's name servers. I've created the `smartcoop.sh` domain manually within
the DO web interface (within the curiosity project). And then created an A
record for `@`, associated to the above IP address.
