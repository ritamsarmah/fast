# fast

A minimal command-line tool for quickly opening and interacting with projects.

## Installation

_fast_ is written in [Odin](https://github.com/odin-lang/Odin) and requires the compiler in order to build. Run `./build.sh` to build the binary for *fast*, `f`.

```
$ git clone https://github.com/ritamsarmah/fast
$ cd fast
$ ./build.sh
```

## Usage

Save the current directory as a project (_fast_ data is stored at `~/.fstore`):

```
$ f -s project1
```

Switch to a saved project directory from anywhere:

```
$ f project1
```

Enter a substring and _fast_ will prompt to disambiguate as needed:

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

You can use the `-o` flag to open a project directory in a system application or IDE (e.g., Xcode) that *fast* recognizes. Otherwise, it defaults to opening in your configured `$EDITOR`.

```
$ f -o my_ios_app
Opening "my_ios_app" in Xcode...
```

If the directory contains a `start` script, *fast* will automatically run that instead, allowing you to configure exactly how your project opens.
