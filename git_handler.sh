#/bin/sh

#####interface
# function logging_error(err_msg)
# function set_path_to_root()
# function clone_repository(repo_url , repo_path)
# function pull_repository(repo_path)
# function sync_to_upstream(repo_path , upstream_url)
# function push_repository(repo_path)
# function init_repository(repo_path , repo_url)
# function sync_repository(repo_path , repo_url)
function logging_error()
{
    echo $@ >> /dev/stderr
}

ROOT_PATH="`pwd`"
function set_path_to_root()
{
    if [ "$ROOT_PATH" = "" ];then
        logging_error "ROOT PATH has not been set . set to `pwd`"
        ROOT_PATH="`pwd`"
    fi
    cd "$ROOT_PATH"
}
## Git handler

GIT_NO_ERROR="true"
function git_error_handler()
{
    if [ "$GIT_NO_ERROR" = "true" ];then
        exit 1
    fi
}

function check_if_repo_url_is_same()
{
    ### Note
    # because repo url may have authentication info , such as https://username:passwd@github.com/user_or_organization/repo , 
    #                                                         https://username@github.com/user_or_organization/repo ,
    #                                                         https://github.com/user_or_organization/repo
    # so we JUST CHECK the last 2 fields splited by '/' , that is to say , the user_or_organization and repo . 
    # but a normalized repo url is needed ! we think it should be .
    url1="$1"
    url2="$2"
    echo $url1
    echo $url2
    token_1="`echo "$url1" | awk -F'/' '{print $(NF-1)"/"$NF}'`"
    token_2="`echo "$url2" | awk -F'/' '{print $(NF-1)"/"$NF}'`"
    [ "$token_1" = "$token_2" ]
    return $?
}

function clone_repository()
{
    repo_path=$1
    repo_url=$2
    CUR_PATH="`pwd`"
    set_path_to_root
    git clone $repo_url $repo_path
    if [ $? -eq 0 ]; then
        logging_error "clone `basename $repo_path` repository done." 
    else 
        logging_error "clone `basename $repo_path` repository failed"
        logging_error "Exit!"
        exit 1
    fi
    cd "$CUR_PATH"
}

function pull_repository()
{
    repo_path=$1
    CUR_PATH="`pwd`"
    set_path_to_root ; cd $repo_path
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
    set_path_to_root ; cd "$repo_path"
    remote_list="`git remote`" 
    find_upstream_rst="`echo "$remote_list" | grep upstream | tr -d [:space:]`"
    has_set_upstream=0
    [ -n "$find_upstream_rst" ] && has_set_upstream=1
    ret=0
    if [ $has_set_upstream -eq 1 ];then 
        origin_upstream_url="`git remote -v | egrep upstream | tr [:space:] " " | cut -d " " -f 2`"
        if check_if_repo_url_is_same $origin_upstream_url $upstream_url ;then
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
        set_path_to_root ; cd "$repo_path"
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
    set_path_to_root ; cd $repo_path
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
    set_path_to_root ;
    if [ ! -e $repo_path ] ;then
        clone_repository  "$repo_path" "$repo_url"
    else
        cd $repo_path ; git status >/dev/null
        if [ $? -ne 0 ] ; then
            logging_error "repository `basename $repo_path` is damaged . remove it and reclone it!" 
            rm -rf $repo_path
            clone_repository "$repo_path" "$repo_url"
        else
            ## Now we should check the remote origin is same the the repo_url
            origin_url="`git remote -v | sed -n 's/origin[[:space:]]\+\(.*\)[[:space:]]\+.*/\1/p' | head -1`"
            if check_if_repo_url_is_same $origin_url $repo_url ; then
                git remote set-url origin $repo_url # still set to the repo url
            else
                logging_error "repository `basename $repo_path` located at $repo_path has a different origin url($origin_url) from config repo_url($repo_url) . This conflict should be handled manually !"
                logging_error "Exit !"
                exit 1
            fi
            logging_error "repository `basename $repo_path` has already ok "
        fi
    fi
    logging_error "repository `basename $repo_path` initialized ." 
    cd "$CUR_PATH" # may be the dir has been changed 
}

function sync_repository()
{
    repo_path="$1"
    upstream_url="$2"
    CUR_PATH="`pwd`"
    set_path_to_root
    cd "$repo_path"
    origin_url="`git remote -v | sed -n 's/origin[[:space:]]\+\(.*\)[[:space:]]\+.*/\1/p' | head -1`"
    if check_if_repo_url_is_same $origin_url $upstream_url ; then
        logging_error "remote origin is the upstream , just pull it for sync"
        pull_repository "$repo_path"
    else 
        logging_error "current repository `basename $repo_path` is a fork of upstream . remote upstream should be set up before sync"
        sync_to_upstream "$repo_path" "$upstream_url" 
    fi
    cd "$CUR_PATH"
}
