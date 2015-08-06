#/bin/sh

#####interface
# function logging_error(err_msg)
# function clone_repository(repo_url , repo_path)
# function pull_repository(repo_path)
# function sync_to_upstream(repo_path , upstream_url)
# function push_repository(repo_path)
# function init_repository(repo_path , repo_url)

function logging_error()
{
    echo $@ >> /dev/stderr
}
## Git handler

function git_error_handler()
{
    if [ "$GIT_NO_ERROR" = "true" ];then
        exit 1
    fi
}

function clone_repository()
{
    repo_path=$1
    repo_url=$2
    git clone $repo_url $repo_path
    if [ $? -eq 0 ]; then
        logging_error "clone `basename $repo_path` repository done." 
    else 
        logging_error "clone `basename $repo_path` repository failed"
        logging_error "Exit!"
        exit 1
    fi
}

function pull_repository()
{
    repo_path=$1
    local CUR_PATH="`pwd`"
    cd $repo_path
    git pull origin master
    local ret=$?
    if [ $ret -ne 0 ];then
        logging_error "pull request `basename $repo_path` error"
        git_error_handler 
    fi
    logging_error "repository `basename $repo_path` pull request done."
    cd "$CUR_PATH"
    return $ret
}

function add_repository_remote_upstream()
{
    repo_path="$1"
    upstream_url="$2"
    CUR_PATH="`pwd`"
    cd "$repo_path"
    remote_list="`git remote`" 
    find_upstream_rst="`echo "$remote_list" | grep upstream | tr -d [:space:]`"
    has_set_upstream=0
    [ -n "$find_upstream_rst" ] && has_set_upstream=1
    ret=0
    if [ $has_set_upstream -eq 1 ];then 
        origin_upstream_url="`git remote -v | egrep upstream | tr [:space:] " " | cut -d " " -f 2`"
        if [ "$origin_upstream_url" = "$upstream_url" ];then
            logging_error "repository `basename $repo_path` has already set upstream"
            ret=0
        else
            logging_error "repository `basename $repo_path` upstream remote has a different url : $origin_upstream_url . change it . "
            git remote set-url upstream "$upstream_url"
            ret=$?
        fi
    else
        git remote add upstream "$upstream_url"
        ret=$?
    fi
    if [ $ret -eq 0 ];then
        logging_error "repository `basename $repo_path` add remote upstream done."
    else
        logging_error "repository `basename $repo_path` add remote upstream failed."
        git_error_handler
    fi
    cd "$CUR_PATH"
    return $ret
}

function sync_to_upstream()
{
    repo_path="$1"
    upstream_url="$2"
    CUR_PATH="`pwd`"
    add_repository_remote_upstream $repo_path $upstream_url 
    ret=0
    if [ $ret -eq 0 ]; then
        cd "$repo_path"
        git fetch upstream
        git checkout master
        git merge upstream/master
        ret=$?
    fi
    cd "$CUR_PATH"
    if [ $ret -eq 0 ];then
        logging_error "repository `basename $repo_path` sync to upstream done."
    else 
        logging_error "repository `basename $repo_path` sync to upstream failed."
        git_error_handler
    fi
    return $ret
}

function push_repository()
{
    repo_path=$1
    CUR_PATH="`pwd`"
    cd $repo_path
    git push origin master
    if [ $? -eq 0 ];then
        logging_error "push repository `basename $repo_path` done."
    else
        logging_error "push repository `basename $repo_path` falied."
        git_error_handler
    fi
    cd "$CUR_PATH"
}

function init_repository()
{
    repo_path=$1
    repo_url=$2
    CUR_PATH="`pwd`"
    if [ ! -e $repo_path ] ;then
        clone_repository  "$repo_path" "$repo_url"
    else
        cd $repo_path ; git status >/dev/null
        if [ $? -ne 0 ] ; then
            logging_error "repository `basename $repo_path` is damaged . remove it and reclone it!" 
            rm -rf $repo_path
            clone_repository "$repo_path" "$repo_url"
        else 
            logging_error "repository `basename $repo_path` has already ok "
        fi
    fi
    logging_error "repository `basename $repo_path` initialized ." 
    cd "$CUR_PATH" # may be the dir has been changed 
}
