#/bin/sh

## Static Config

###Path config
ROOT_PATH="`pwd`"
PRE_PATH="."
REPOSITORY_PATH="$PRE_PATH/repositories"
TMP_LOG_FILE="/tmp/tmp_`date +%Y%M%S`"

###GitHub authentication config
GITHUB_NAME="memeda"
GITHUB_PASSWD="0"
AUTH="${GITHUB_NAME}:${GITHUB_PASSWD}@"

### Repository config
LTP_REPO_NAME="ltp"
LTP_REPO_PATH="$REPOSITORY_PATH/$LTP_REPO_NAME"
LTP_REPO_URL="https://${AUTH}github.com/memeda/ltp"
LTP_REPO_UPSTREAM_URL="https://github.com/HIT-SCIR/ltp"

LTPCWS_REPO_NAME="ltpcws"
LTPCWS_REPO_PATH="$REPOSITORY_PATH/$LTPCWS_REPO_NAME"
LTPCWS_REPO_URL="https://${AUTH}github.com/memeda/ltp-cws"
LTPCWS_REPO_UPSTREAM_URL="https://github.com/HIT-SCIR/ltp-cws"

### dependency file and keep stable file config
LTP_SUBPROJECT_DEPENDENCY_PATH="$LTP_REPO_PATH/subproject.d.json"
LTPCWS_KEEP_STABLE_PATH="$LTPCWS_REPO_PATH/keep_stable.txt"

### scripts config
SYNC_SCRIPT="python $PRE_PATH/sync_project.py "
GIT_HANDLER_SCRIPT="$PRE_PATH/git_handler.sh"

### workflow  error config
GIT_NO_ERROR="true"

# Git handler
. "$GIT_HANDLER_SCRIPT"

# function logging_error(err_msg)
# function clone_repository(repo_url , repo_path)
# function pull_repository(repo_path)
# function sync_to_upstream(repo_path , upstream_url)
# function push_repository(repo_path)
# function init_repository(repo_path , repo_url)


function ready_all_repositories()
{
    mkdir -p $REPOSITORY_PATH
    init_repository $LTP_REPO_PATH $LTP_REPO_URL
    init_repository $LTPCWS_REPO_PATH $LTPCWS_REPO_URL
    sync_to_upstream $LTP_REPO_PATH $LTP_REPO_UPSTREAM_URL
    #sync_to_upstream $LTPCWS_REPO_PATH $LTPCWS_REPO_UPSTREAM_URL
    pull_repository $LTPCWS_REPO_PATH 
}

function sync_dependency_repositories()
{
    src_repo_path=$1
    dst_repo_path=$2
    dep_file=$3
    keep_stable_file=$4
    if [[ ! -e "$src_repo_path" ]] || [[ ! -e "$dst_repo_path" ]] || [[ ! -e "$dep_file" ]] ; then
        logging_error "At least one of the path ($src_repo_path , $dst_repo_path , $dep_file ) is not exists"
        logging_error "sync dependency repositories Exit!"
        exit 1
    fi
    params="-src $src_repo_path -dst $dst_repo_path -d $dep_file "
    if [ -e "$keep_stable_file" ];then
        params="$params -k $keep_stable_file"
    fi
    $SYNC_SCRIPT $params
    if [ $? -eq 0 ];then
        logging_error "sync dependency repositories done."
    else
        logging_error "sync dependency repositories failed."
        logging_error "Exit !"
        exit 1
    fi
}

function commit_and_push_repository_update()
{
    repo_path=$1
    CUR_PATH="`pwd`"
    cd "$repo_path"
    git add --all ./ >$TMP_LOG_FILE 2>&1
    if [ $? -ne 0 ];then
        logging_error "repository `basename $repo_path` : git add error . details : " "`cat $TMP_LOG_FILE`"
        exit 1
    fi
    git status > $TMP_LOG_FILE 2>&1
    commit_info="`cat $TMP_LOG_FILE | tr -d "#\t " | awk '/^$/{if(flag==0){flag=1}else{flag=0}} /.+/{if(flag==1){print $0}}' | awk -F':' '{list[$1]=list[$1]" "$2}END{for( x in list){print x" :"list[x]}}'`"
    logging_error "$commit_info"
    git commit -m "$commit_info"
    if [ $? -eq 0 ];then
        logging_error "repository `basename $repo_path` commit done."
    else
        logging_error "repository `basename $repo_path` commit failed"
        logging_error "Exit !"
        rm $TMP_LOG_FILE
        exit 1
    fi
    
    push_repository $repo_path
    cd "$CUR_PATH"
    rm $TMP_LOG_FILE
}
function main()
{
    read -p "user name and passwd should be specified. is it ready?[y/n]" ans
    if [ "$ans" != "y" ];then
        logging_error "Exit !"
    fi
    ready_all_repositories
    sync_dependency_repositories $LTP_REPO_PATH $LTPCWS_REPO_PATH $LTP_SUBPROJECT_DEPENDENCY_PATH $LTPCWS_KEEP_STABLE_PATH
    commit_and_push_repository_update $LTPCWS_REPO_PATH
}

main
