# fast

Quickly open and interact with project directories from the command-line. Supports easily opening a project in it's relevant system application (e.g., Xcode projects) or conveniently run start scripts.

## Getting Started

Save the current directory as a project:

```shell
$ f -s project1
```

Switch to a saved project directory from anywhere:

```shell
$ f project1
```

You can also enter a substring and `fast` will prompt to disambiguate as needed:

```shell
$ f -s project2
Saved project "project2"

$ f proj
Which project should be loaded?

project1  /Users/me/Documents/MyApp
project2  /Users/me/Developer/secret_project

Enter project query: 2
Switching to "project2"
```

If `fast` recognizes the project directory can be opened in a system application (e.g., Xcode projects), you can use the `-o` flag to open it directly from the command line.

```shell
$ f -o cool_ios_app
Opening "cool_ios_app" in Xcode...
```

