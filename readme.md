## About git-helpers

The git-helpers project is essentially a set of utilities that can help you be more productive and make working with Git fun again.

## Is this for you?

This is meant for those of you who have a decent understanding of git and shell script and create-, merge-, pull- and push branches regularly.

## Requirements

This was built- and tested using bash version 4.4.12

## Installation

I encourage you to clone this repository locally and link directly to `git-helpers.sh` in your `.bashrc` or similar using:

```shell
source "your_path/git-helpers/git-helpers.sh"
```

Alternatively you can put the contents of `git-helpers.sh` directly in your `.bashrc`. Keep in mind however that you could potentially miss out on important updates.

## Usage

###### A more detailed how-to guide will follow shortly!

One thing that helps git-helpers stand out is the ability to find and select branches. When using the `checkout` helper for example you are not required to specify the entire branch name:

```shell
$ vc checkout bug/
1) bug/something_fixed
2) bug/something_different_fixed
Pick a number [1-2]:
``` 

This is very helpful in situations where you have a large number of branches and aren't able to keep track of all of them.

## Why vc?

VC stands for version control. In case you'd rather use something else, like `gh` for example, you can easily do so by defining an alias:

```shell
alias gh='vc'
```

## Disclaimer

I am by no means a veteran when it comes to shell scripting and as such this tool is not as fool-proof as I'd like it to be. If you have any suggestions or improvements I'd appreciate it if you use the issues section or create a pull-request. Thanks!