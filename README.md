# fast

A minimal command-line tool for quickly opening and interacting with projects.

## Installation

**fast** is written in [Odin](https://github.com/odin-lang/Odin) and requires the compiler in order to build.

1. Run `./build.sh` to build the binary, `fast`.
2. Move or link the binary to make it available from your `$PATH` (e.g., `/usr/local/bin`).
3. Configure the wrapper shell script:
  - `fish`: Move or link `f.fish` to `~/.config/fish/functions`
4. For editing projects from the command line, make sure your preferred `$EDITOR` environment variable is set (e.g., `vim`)

## Usage

Save the current directory as a project (**fast** data is stored at `~/.fstore`):

```
$ f -s project1
```

Switch to a saved project directory from anywhere:

```
$ f project1
```

Enter a substring and **fast** will prompt to disambiguate as needed:

```
$ f -s project2
Saved project "project2"

$ f proj
Which project should be loaded?

project1  /Users/me/Documents/MyApp
project2  /Users/me/Developer/secret_project

Enter project: 2
Switching to "project2"
```

You can use the `-o` flag to open a project directory in a system application or IDE (e.g., Xcode) that **fast** recognizes. Otherwise, it defaults to opening in your configured `$EDITOR`.

```
$ f -o my_ios_app
Opening "my_ios_app" in Xcode...
```

If the directory contains a `start` script, **fast** will automatically run that instead, allowing you to configure exactly how your project opens.
