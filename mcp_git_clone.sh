#!/bin/bash

#=====================================================================
#
# The primary purpose of this tool is to clone in MCP GitLab an
# existing remote repository, which is not already in MCP GitLab.
# Currently (07/14/2023), git cannot directly clone a remote git
# repository at another remote location; therefore, to do such a
# cloning, this tool first clones the source remote repository in the
# local system, where this tool is used, and then clones the local
# repository at MCP GitLab.  However, this tool can behave in three
# different major ways depending on the single optional positional
# argument PATH.
#
# The single positional argument PATH can be one of the following:
#   1) The URL of a remote git repository
#   2) The path to a local subdirectory which is a git repo
#   3) The path to a local subdirectory which is not a git repo
# If the optional argument PATH is not provided, then it is assumed
# to be the current working directory '.' in the local system.
#
# In the first case, this tool
#   a) clones the remote git repo locally
#   b) "disables" remote 'origin' push for the local repo
#   c) clones the local copy of the repo in MCP GitLab
#   d) creates remote 'mcp' push and fetch
#
# In the second case, this tool
#   a) "disables" remote 'origin' push for the local repo, if
#      remote 'origin' exists
#   b) clones the local copy of the repo in MCP GitLab
#   c) creates remote 'mcp' push and fetch
#
# In the third case, this tool
#   a) converts the entire subdirectory and its contents into a
#      git repo
#   b) clones the local copy of the repo in MCP GitLab
#   c) creates remote 'mcp' push and fetch
# The user of this tool must delete all unwanted files rooted at
# PATH before using this tool.
#
# Other non-positional arguments:
#
#   -b BRANCH is optional, has a default value of 'main' and is
#      only used when PATH is a local subdirectory which is not a
#      git repository.
#
#   -m MESSAGE is optional, has a default value of 'initial version'
#      and is only used when PATH is a local subdirectory which is
#      not a git repository.
#
#   -t TOKEN_NAME:TOKEN is colon ':' separated MCP GitLab user-ID
#      and access token.  This is an optional MCP GitLab
#      authentication method.
#
#   -p PIPELINE is optional and no action is taken if not used.  The
#      purpose of this optional argument is to supply a pipeline YML
#      file to the repository cloned in MCP GitLab.  The argument
#      should be a pipeline file (.gitlab-ci.yml) in the local system
#      that the user would like to add it to the local repo before
#      cloning the repo in MCP GitLab.  Regardless of how the
#      argument file is named, its copy added to the local repo is
#      named .gitlab-ci.yml.  The pipeline file is added to the repo
#      on a new branch named "mcp_main" to avoid modifying the
#      original contents of the source repository to be cloned.
#
# WARNING:
#  - There is no strong error checking implemented yet.
#  - There are no prompts to confirm the users actions yet.
#
# NOTES:
#  - These script uses the following tools:
#      > realpath
#      > wget
#      > git
#      > git-lfs
#    The tool "realpath is already widely available in many unix/linux
#    systems.  Git is also commonly installed in many systems;
#    however, git version 2.10 or greater is needed due to the use of
#    "-o ci.skip" option.  Install any of the above listed tools that
#    does not exist in your system.  Afte installing git and git-lfs,
#    you must run the command
#      > git lfs install
#    to initialize git-lfs before using this script.


# Prints usage message
#
usage() {
  echo "Usage: $0 [ PATH ] [ -b BRANCH ] [ -m MESSAGE ] [ -t TOKEN_NAME:TOKEN ] [ -p PIPELINE ]" 1>&2 
}

# This function is for error exit.
#
exit_abnormal() {
  usage
  exit 1
}


#=============== Get some optional input parameters ===============

# Default values for non-positional input arguments.
#
branch="main"
message="initial revision"
tauthentication=""
pipeline=""

ipos=0
while [ $# -gt 0 ]; do
    unset OPTIND
    unset OPTARG
    while getopts hb:m:t:p: opt; do
       if [[ ${OPTARG} =~ ^-.*$ ]]; then
            echo "ERROR:  Option argument cannot start with '-'"
            exit_abnormal
        fi
        case "$opt" in
            h) usage; exit 0;;
            b) branch=${OPTARG};;
            m) message=${OPTARG};;
            t) tauthentication=${OPTARG};;
            p) pipeline=`realpath ${OPTARG}`;;
            *) echo "ERROR:  Unknown option."; exit_abnormal;;
        esac
    done
    shift $((OPTIND-1))
    (( ipos=ipos+1 ))
    case $((ipos)) in
        1) path="$1";;
        *) [ ! -z "$1" ] && echo "ERROR:  Incorrect number of positional arguments!" && exit_abnormal;;
    esac
    shift
done

# Default values for positional input arguments.
#
if [ -z $path ]; then
    path='.'
fi

echo "branch   '$branch'"
echo "message  '$message'"
echo "token    '$tauthentication'"
echo "pipeline '$pipeline'"
echo "path     '$path'"


#=============== Check if "$path" is a valid URL ===============

# Boolean: true if $path is a valid URL that can be found, false otherwise.
#
path_valid_url=$(! wget --spider "$path" > /dev/null 2>&1; echo $?)

# Check whether or not the path is a valid URL
#
if (( $path_valid_url )); then
    echo "INFO:  Verified URL '$path'"
else
    echo "INFO:  Cannot be verified as a URL, '$path'"
fi


#=============== Check if $path is a Git repo URL ===============
# If it is a Git repo URL,
#   1) clone it
#   2) set $path to be the locally cloned subdirectory name
# It may not be an error if $path is not a Git repo URL that can be
# found.  It could be a path pointing at a location in the local
# file system.

# Boolean: true if $path is a valid git repo, false otherwise.
# This flag will be true if $path is either
#   - a URL for a remote git repository
#   - or a path to a local git repository
#
path_valid_git=$(! git ls-remote "$path" > /dev/null 2>&1; echo $?)

# Here we assume that $path is a URL pointing at a public repository
# and no authentication is necessary.  Just $path_valid_git being
# true is not enough here.  $path_valid_git would be true if $path
# were a path to a git repository in the local filesystem.  Just
# $path_valid_url being true is not enough either.  For example,
# $path_valid_url would be true if $path were "https://www.apple.com",
# which is not a git project URL.  Therefore, both flags must be true
# for us to conclude that $path is the URL of a remote git repository.
#
# If in the working directory there is a file or subdirectory named
# $reponame, cloning will fail (see the 'if' block).  We may want to
# handle this in a different way.
#
just_cloned=false
if (( $path_valid_git && $path_valid_url )); then
    echo "INFO:  Verified a git repository '$path'"
    basename=$(basename $path)
    reponame=${basename%.*}
    #extension=${basename##*.}
    echo "INFO:  Repository name is '$reponame'."
    git clone $path
    if [ $? -ne 0 ]; then
        echo "ERROR:  Command 'git clone $path' failed!"
        exit $?
    fi
    just_cloned=true
    git -C $reponame remote set-url --push origin DISABLED
    path=$reponame
else
    echo "INFO:  Could not be verified as a remote git repository '$path'"
fi


#=============== Check if $path is a local filesystem subdirectory ===============
# At this point, path must be an existing local subdirectory.

# If not a valid directory, just exit.  If not exited, the process
# steps into $path.
#
if [ ! -d $path ]; then
    echo "ERROR:  '$path' must be an existing directory!"
    exit_abnormal
fi

cd $path


#=============== Not a Git repo? Then convert into a Git repo ===============
# If the working directory (folder) is inside a git repository, which
# was not recently cloned, then perhaps the caller wanted to pull
# updates from the original remote and push it into MCP.  The code 
# block here follows this assumption, but it only pulls updates from
# remote 'origin' if available.  However, if the current subdirectory
# (folder) is not inside a git repository, then convert it (and its
# contents) into a git repository.  The caller must eliminate all
# unwanted files, links, subdirectories ... before calling this script.

# Boolean: true if at the top level of a local git repo, false otherwise.
#
git_repo_top_level=$(! [[ "`git rev-parse --git-dir 2> /dev/null`" == ".git" ]]; echo $?)

# Boolean: true if somewhere inside a git repo, false otherwise.
#
git_repo_somewhere=$(! git rev-parse --git-dir > /dev/null 2>&1; echo $?)

if (( $git_repo_somewhere )); then
    echo "INFO:  Already in a git repository: $PWD"
    if [[ "$just_cloned" = false ]]; then
        # If this git repository was already cloned before calling this
        # script, then simply pull updates only from remote 'origin'
        # to be pushed into MCP later.
        
        original_remote_name="origin"
        result="`git remote | grep $original_remote_name 2> /dev/null`"
        if [ -z "$result" ]; then
            echo "WARN:  There is no remote named '$original_remote_name' for updates."
        else
            # The following disabling may not be necessary.
            git remote set-url --push $original_remote_name DISABLED
            echo "INFO:  Pulling updates from remote '$original_remote_name' for MCP push later."
            git pull $original_remote_name
            if [ $? -ne 0 ]; then
                echo "ERROR:  Command 'git pull $original_remote_name' failed!"
                exit $?
            fi
        fi
    fi
else
    echo "INFO:  Converting to a local git repository: $PWD"

    # Initializing as a git repository.  This should be done
    # only if the current location is not a git repository.
    #   git branch -m <name>     just renames the current branch
    #
    git init
    git branch -m "$branch"
    git add *
    git commit -m "$message"
fi


#=============== Working directory must be a local Git repository ===============
# At this point, the working directory must be a git repository;
# otherwise, something is wrong.

# The following flag must be false at this point.
#
not_a_git_repo=$( git rev-parse --git-dir > /dev/null 2>&1; echo $? )
if (( $not_a_git_repo )); then
    echo "ERROR:  The working directory must be inside a git repository."
    exit_abnormal
fi


#=============== Determine current branch name ===============

branch="`git branch --show-current 2> /dev/null`"
if [ $? -ne 0 ]; then
    echo "ERROR:  Could not obtain current branch name."
    exit $?
elif [ -z "$branch" ]; then
    echo "ERROR:  Current branch name is null."
    exit 1
else
    echo "INFO:  Curent branch name is '$branch'."
fi


#=============== Add MCP remote link if it does not exist. ===============

# Remote name for MCP GitLab Ultimate
#
name="mcp"

result="`git remote | grep $name 2> /dev/null`"
if [ -z "$result" ]; then
    echo "INFO:  Remote '$name' does not exist.  Creating remote '$name' link."

    # Creating an MCP URL for the new project.

    if [ "$tauthentication" = "" ]; then
        gitlaburl="https://gitlab.mcp.nasa.gov/unity/"
    else
        gitlaburl="https://$tauthentication@gitlab.mcp.nasa.gov/unity/"
    fi

    # The current subdirectory name (last token of PWD) is
    # chosen as the project name.
    #
    project=${PWD##*/}

    # And finally the project URL:
    #
    mcp_projecturl=$gitlaburl$project.git
    echo "INFO:  MCP URL for cloning is '$mcp_projecturl'"

    # Create the remote link.
    #
    git remote add "$name" "$mcp_projecturl"

    # Ideally, I would like to disable mcp fetch, I don't know how
    # to do it.  The following command only works for --push.
    #
    #git remote set-url --fetch "$name" DISABLE

else
    echo "INFO:  Remote '$name' already exists."
fi


#=============== Push into MCP GitLab ===============

# The "git push" command here pushes the original contents of the
# $path to MCP as is on the branch "$branch".  On this branch,
# nothing is modified, not even the original YML file (if any).

# Do not add "-u" option for "git push ..." command.
#
echo "INFO:  Executing the command"
echo "   git push -o ci.skip $name $branch"
git push -o ci.skip "$name" "$branch"



#=============== Additional updates to the cloned repo. ===============

# Additional updates to the MCP cloned repo will be done on the
# branch $mcp_branch.  In this way, the "main/master" branch will
# remain the exact copy of the source repository.
#
mcp_branch="mcp_main"
git checkout -b $mcp_branch


#=============== Add pipeline YAML file if given. ===============

# If pipeline yml file provided, copy it to destination. Here, we
# assume that the input pipeline filename may or may not the
# expected ".gitlab-ci.yml".  Therefore, we need to make sure
# that it is named ".gitlab-ci.yml" when copied.
#
ymlfn_copy=".gitlab-ci.yml"
ymlfn_original=""
if [ ! -z $pipeline ]; then
    if [ -f $pipeline ]; then
        cp $pipeline ./$ymlfn_copy
        ymlfn_original=$(basename $pipeline)
    else 
        echo "ERROR:  $pipeline does not exist."
        exit_abnormal
    fi
else
    echo "INFO:  No pipeline YML file provided."
fi


# Here $ymlfn_original is only used like a flag to see whether or
# not a pipeline file was given as an optional input.  The name
# of the copied versoin of the pipeline YML file is given by
# $ymlfn_copy.
#
if [ ! -z $ymlfn_original ]; then
    if [ -f $ymlfn_copy ]; then
        git add $ymlfn_copy
        git commit -m "added pipeline yml file"
    else 
        echo "ERROR: '$ymlfn_copy' should be a valid file at this point!  Coding error!"
        exit_abnormal
    fi
fi


echo "INFO:  Executing the command"
echo "   git push $name $mcp_branch"
git push "$name" "$mcp_branch"


git checkout $branch

exit 0
