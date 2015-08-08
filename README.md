# update_ltpcws_from_ltp

##使用方法

1. 根据具体情况更新repo_config.sh配置文件
    
    GITHUB_NAME 需要设置
    
    GITHUB_PASSWD可以为空（运行中需要输入密码），或者设置
    
    设置LTP，LTPCWS的仓库本地存储路径（本地仓库可以存在，也可以不存在；如果不存在，会从远端克隆）
    
    设置LTP，LTPCWS的远端仓库路径（origin），upstream路径（用于更新）。orgin可以是upstream。
    
    设置从LTP到LTPCWS构建所需要的subproject.d.json路径，默认是在LTP项目内；设置LTPCWS仓库保持稳定（防止自动化处理被删除）的keep_stable.txt路径，默认在LTPCWS项目内。

2. 运行workflow.sh脚本。

    如果出现merge错误、commit错误，如有必要，需要根据错误信息手动修改。



