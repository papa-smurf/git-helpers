#!/usr/bin/env bash

# TODO: Error handling and input validation/sanitation

function vcs(){
    # Show the usage help in case no arguments (or the help flag) were provided
    if [ -z ${1+x} ] || ([ $1 == '-h' ] || [ $1 == '--help' ]); then

        cat << EOF

Usage:
    vcs
    vcs [-help | --help]|[method] [arguments]

Example:
    vcs search sprint_70

General methods:
    discard                                     Discard all (un)staged local changes
    commit-all [MESSAGE]                        Commit all (un)stashed changes
    commit-all-push [MESSAGE]                   Commit all (un)stashed changes and push them remotely
    commit-history [MAXCOUNT]                   Show a list of recent commits (default 5)
    push                                        Push all stashed commits to the origin branch

Branching methods:
    current-branch                              Display the currently active branch name
    checkout [BRANCH]                           Checkout a branch that already exists locally or remotely, if the branch doesn't exist a search is performed instead
    checkout-new [BRANCH] [? BASE]              Checkout a new branch that doesnt exist locally or remotely, you can also provide a base other than the current branch
    search [BRANCH] [-s | --shallow]            Search for a branch, include -s or --shallow to limit searches to local branches only

    branch-rename [NEWNAME]|[OLDNAME NEWNAME] [? -f --force]
    Rename the current branch or a given branch name locally, use the force flag (-f | --force) to rename the branch on remote as well

    branch-delete [BRANCH] [-f | --force]       Delete a given branch name locally, use the force flag (-f | --force) to delete the branch from remote as well, use with caution!
    merge [BRANCH] [? INTO]                     Merge a given 'from' branch in the 'into' branch. Behaves as a regular git merge if 'into' is omitted

Workflow methods:
    master                                      Checkout the master branch
    pull-request                                Create a pull request for the active branch
EOF

        return 0
    fi

    # Method shorthand dictionary
    declare -A METHOD_DICTIONARY=(
        [bd]=branch-delete
        [br]=branch-rename
        [c]=checkout
        [ca]=commit-all
        [cb]=current-branch
        [ch]=commit-history
        [cn]=checkout-new
        [cap]=commit-all-push
        [capr]=commit-all-pull-request
        [cn]=checkout-new
        [d]=discard
        [me]=merge
        [ma]=master
        [p]=push
        [pr]=pull-request
        [s]=search
    )

    METHOD="$1"

    # Check if the given method name exists
    TYPE="$(type -t vcs-${METHOD})"

    # If the given method does not exist we first check if a shorthand was provided instead
    if [ "$TYPE" != "function" ]; then
        METHOD=${METHOD_DICTIONARY[${METHOD}]}
        TYPE="$(type -t vcs-${METHOD})"
    fi

    if [ "$TYPE" == "function" ]; then
        METHOD="vcs-$METHOD"

        # Call the appropriate vcs method
        # Remove the first argument (which would normally include the method name)
        set -- "${@:2}"

        $METHOD "$@"
        return 0
    fi

    # If a method is given but doesn't exist within vcs, we pass everything on to git instead
    git "$@"
}

function vcs-current-branch() {
    BRANCH=$(vcs rev-parse --abbrev-ref HEAD)
    echo "$BRANCH"
}

function vcs-checkout(){
    BRANCH=$1
    git fetch origin "$BRANCH" &> /dev/null

    BRANCH_EXISTS=$(vcs branch-exists "$BRANCH")

    # The given branch name exists, perform and checkout and abort
    if [ "$BRANCH_EXISTS" == 'true' ]; then
        git checkout "$BRANCH"
        return 0
    fi

    PHRASE="$BRANCH"

    # The branch name did not exist, continue with a search instead
    BRANCHES=$(vcs search $PHRASE)
    BRANCH=$(vcs select-result $BRANCHES)

    if [ -z $BRANCH ]; then
        echo "No branch found for phrase '$PHRASE'"
        return 0
    fi

    git checkout $BRANCH
}

function vcs-checkout-new(){
    # By default we use the current branch as base
    BASE=$(vcs current-branch)

    # A second argument was provided, use it as base
    if [ ! -z $2 ] && [ "$2" != "$BASE" ] ; then
        vcs checkout "$2" && vcs pull &> /dev/null
    fi

    BRANCH=$(vcs sanitize-branch-name "$1")
    git checkout -b "$BRANCH"
}

function vcs-commit-all() {
    MESSAGE=$1
    git add . && git commit -m "$MESSAGE"
}

function vcs-commit-all-pull-request() {
    vcs-commit-all-push $1 && vcs-pull-request $2
}

function vcs-commit-all-push() {
    MESSAGE=$1
    vcs commit-all "$MESSAGE" && vcs push
}

function vcs-commit-history() {
    MAXCOUNT=5

    if [ ! -z $1 ]; then
        MAXCOUNT="$1"
    fi

    git log  --decorate=short --max-count="$MAXCOUNT"
}

# Supports:
#
# vcs branch-delete master
# vcs branch-delete master -f|--force
function vcs-branch-delete() {
    # TODO: Bulk delete

    if [ "$1" == $(vcs current-branch) ]; then
        echo "You can't delete a branch you're currently checked out at!"
        return 0
    fi

    git branch -D "$1"

    # Determine if the force flag was provided, and remove branch remotely if so
    if [ ! -z $2 ] && ([ "$2" == '-f' ] || [ "$2" == '--force' ]); then
        git push origin --delete "$1"
    fi
}

function vcs-branch-exists() {
    BRANCH=$1

    EXISTS=$(git rev-parse --verify "$1" 2>&1 >/dev/null)

    if [[ $EXISTS == *"fatal:"* ]]; then
        echo 'false'
        return 0
    fi

    echo 'true'
}

# Supports:
#
# vcs branch-rename newname
# vcs branch-rename newname -f|--force
# vcs branch-rename oldname newname
# vcs branch-rename oldname newname -f|--force
function vcs-branch-rename() {
    PARAM1=$(vcs sanitize-branch-name "$1")
    PARAM2=$(vcs sanitize-branch-name "$2")
    PARAM3=$(vcs sanitize-branch-name "$3")
    FORCE='false'

    # Determine if the force flag was provided
    if ([ "$PARAM2" == '-f' ] || [ "$PARAM2" == '--force' ]) || ([ "$PARAM3" == '-f' ] || [ "$PARAM3" == '--force' ]); then
        FORCE='true'
    fi

    # vcs branch-rename newname
    if [ "$PARAM2" == '' ]; then
        git branch -m "$PARAM1"
        return 0
    fi

    # vcs branch-rename newname -f
    if [ "$PARAM3" == '' ] && [ "$FORCE" == 'true' ]; then
        OLDNAME=$(vcs current-branch)
        git branch -m "$PARAM1" && git push origin ":$OLDNAME" "$PARAM1"
        return 0
    fi

    # vcs branch-rename oldname newname
    if [ "$PARAM3" == '' ]; then
        git branch -m "$PARAM1" "$PARAM2"
        return 0
    fi

    # vcs branch-rename oldname newname -f
    if [ "$FORCE" == 'true' ]; then
        git branch -m "$PARAM1" "$PARAM2" && git push origin ":$PARAM1" "$PARAM2"
    fi
}

function vcs-discard() {
    git checkout . && git reset --hard
}

function vcs-master() {
    vcs checkout master && vcs pull
}

function vcs-merge() {
    # No second argument was provided, perform default git merge
    if [ -z $2 ]; then
        git merge $1
        return 0
    fi

    CURRENTBRANCH=$(vcs current-branch)
    FROM=$1
    TO=$2
    FROM_EXISTS=$(vcs branch-exists "$FROM")
    TO_EXISTS=$(vcs branch-exists "$TO")

    if [ "$FROM" == "$TO" ]; then
        echo "The 'from' and 'to' branch may not be equal!"
        return 0
    fi

    if [ "$FROM_EXISTS" != 'true' ]; then
        echo "Branch '$FROM' doesn't exists"
        return 0
    fi

    if [ "$TO_EXISTS" != 'true' ]; then
        echo "Branch '$TO' doesn't exists"
        return 0
    fi

    # Stash all (un)stashed files before we continue
    STASHED_CHANGES=$(vcs stash -u)

    # We chain what happens next so that execution is terminated on failure
    vcs checkout "$FROM" && vcs pull && vcs checkout "$TO" && vcs pull && vcs merge "$FROM"

    # Should we push?
    if [ "$3" == "--push" ] ; then
        WHICH=$(vcs current-branch)

        # Make absolutely sure we're about to push the correct branch
        if [ "$WHICH" == "$TO" ]; then
            vcs push
        fi
    fi

    # Make sure the user end where he started: on his own branch with his own stuff
    if [ "$TO" != "$CURRENTBRANCH" ]; then
        vcs checkout "$CURRENTBRANCH"
    fi

    # If there were any stashed changes pop them back on the branch
    if [ "$STASHED_CHANGES" != 'No local changes to save' ]; then
        vcs stash pop
    fi
}

function vcs-pull-request() {
    BRANCH=$(vcs current-branch)
    ENDPOINT=''
    PUSH_URL=$(git remote get-url --push origin)

    # We need to push first to make sure we have a remote push url
    vcs push

    # Render the PR endpoint for github
    if [[ $PUSH_URL == *"github.com"* ]]; then
        REPOSITORY=$(echo "$PUSH_URL" | grep -o -P '(?<=\:).*(?=\.git)')
        ENDPOINT="https://github.com/${REPOSITORY}/compare/${BRANCH}?expand=1"
    # Render the PR endpoint for bitbucket
    elif [[ $PUSH_URL == *"bitbucket.org"* ]]; then
        REPOSITORY=$(echo "$PUSH_URL" | grep -o -P '(?<=bitbucket.org\/).*(?=\.git)')
        ENDPOINT="https://bitbucket.org/${REPOSITORY}/pull-requests/new?source=${REPOSITORY}:${BRANCH}"
    fi

    # Without an endpoint there's no reason to continue
    if [ "$ENDPOINT" == '' ]; then
        echo "Couldn't determine the repository host for push url '$PUSH_URL'"
        return 0
    fi

    METHOD='start'
    TYPE="$(type -t ${METHOD})"

    if [ "$TYPE" != "file" ]; then
        METHOD='open'
    fi

    $METHOD $ENDPOINT
}

function vcs-push() {
    BRANCH=$(vcs current-branch)
    git push -u origin $BRANCH
}

function vcs-sanitize-branch-name() {
    BRANCH=$1
    BRANCH=$(echo $BRANCH | sed -e "s/\&/ and /g")
    BRANCH=$(echo $BRANCH | sed -e "s/\ /_/g")

    echo "$BRANCH"
}

function vcs-search() {
    IFS=$'\n'
    PHRASE=$1
    DONTFETCH=$2;

    # Grep the results and remove all whitespaces
    RESULTS=$(git branch -a | grep -i "$PHRASE" | grep -v -F "*" | sed -e "s/\ //g")

    # Check if there's a result
    COUNTER=0
    for RESULT in $RESULTS; do
        if (( COUNTER > 0 )); then
            break
        fi

        ((COUNTER++))
    done

    # There's no result, fetch all branches and retry
    if [ ${COUNTER} == 0 ]; then
        # If the dontfetch flag was provided and equals shallow we end the search and
        # don't perform a fetch, this prevents the script from entering an infinite loop
        if [ "$DONTFETCH" == '-s' ] || [ "$DONTFETCH" == '--shallow' ]; then
            return 0
        fi

        vcs fetch --all &> /dev/null && vcs search $PHRASE -s
        return 0
    fi

    # Create a new array with all branch names and strip 'remotes/origin' prefixes
    NEWRESULTS=()
    for RESULT in $RESULTS; do
        RESULT=$(echo $RESULT | sed -e "s/remotes\/origin\///g")
        NEWRESULTS+=("$RESULT")
    done

    # Make sure we only show branches once, even when they exists both locally and -remotely
    UNIQUERESULTS=($(printf "%s\n" "${NEWRESULTS[@]}" | sort -u))

    for RESULT in "${UNIQUERESULTS[@]}"; do
        echo "$RESULT"
    done
}

function vcs-select-result() {
    RESULTS=$1
    RESULTCOUNT=0
    RESULTREMAP=()

    # Filter all empty results
    for OPT in "$@"; do
        if [ ! -z $OPT ]; then
            RESULTCOUNT=$((RESULTCOUNT+1))
            RESULTREMAP+=($OPT)
        fi
    done

    # There's only 1 result, echo it
    if [ "$RESULTCOUNT" -eq "1" ]; then
        RESULT=$(echo $1| sed -e "s/\ //g")
        echo "$RESULT"
        return 0
    fi

    # Loop through all results and add numeric identifiers the user can choose from
    # PS3 the prompt for the select command and can not be renamed!
    PS3="Pick a number [1-$RESULTCOUNT]: "
    select opt in "${RESULTREMAP[@]}"
    do
        RESULT=$(echo $opt | sed -e "s/\ //g")
        echo "$RESULT"
        break
    done
}