#/usr/bin/env python
#coding=utf-8

import argparse
import sys
import os
import json
import shutil
import re
import logging
import traceback

logging.basicConfig(level=logging.INFO ,
                    format="%(asctime)s %(levelname)s [%(lineno)5d] : %(message)s")

def enum(**enums) :
    return type('Enum',(),enums)

DepType = enum(FILE="file",DIR="dir",CMAKELISTS="cmakelists")
DepChangeState = enum(MODIFIED="MODIFIED",NO_CHANGE="NO_CHANGE" , ADD="ADD" , SYNC="SYNC")

def is_hidden_file(fpath) :
    if os.name == 'nt' :
        import win32api , win32con
        attribute = win32api.GetFileAttributes(fpath)
        return attribute & ( win32con.FILE_ATTRIBUTE_HIDDEN | win32con.FILE_ATTRIBUTE_SYSTEM)
    else :
        basename = os.path.split(fpath)[1]
        return basename.startswith('.')

def get_segmentor_dependency(dep_f) :
    '''
    return > dep_s : [
        {
            type : ["file"|"dir"|"cmakelists"] 
            path : ["path/to/obj",...] 
            change_state : ["MODIFIED"|"UN_CHANGE"|"ADD"|"SYNC"]
        }
    ]
    '''
    dep_s = {}
    all_dep_s = json.load(dep_f , encoding="utf-8")
    try :
        dep_s = all_dep_s["subproject"]["segmentor"]
    except KeyError , e :
        traceback.print_exc()
        exit(1)
    return dep_s

def add_directory_hierarchy(vdh , dep_path , is_dir=False) :
    part_list = []
    path_tmp = dep_path
    while True :
        head , tail = os.path.split(path_tmp)
        part_list.append(tail)
        if head == '' :
            break
        path_tmp = head
    parent_dir = vdh
    for i in range(len(part_list)-1 , 0 , -1) :
        cur_dir_name = part_list[i]
        if cur_dir_name not in parent_dir :
            parent_dir[cur_dir_name] = {}
        parent_dir = parent_dir[cur_dir_name]
    basename = part_list[0]
    if not is_dir :
        parent_dir[basename] = None
    else :
        parent_dir[basename] = {"*":"full_dir_flag"}
    logging.info("add virtual directory hierarchy for %s : %s" %("direcotory" if is_dir else "file" , dep_path))

def rm_file_or_dir(path) :
    if not os.path.exists(path) :
        logging.info("file to be removed is not exists : %s" %(path))
        return
    is_dir = os.path.isdir(path)
    try :
        if is_dir :
            shutil.rmtree(path)
        else :
            os.remove(path)
    except Exception , e:
        logging.warning('remove path %s error. details : %s' %(path , e))
        return
    logging.info("remove %s : %s" %("directory" if is_dir else "file" , path))

def copy_file_or_dir(src_path , dst_path , is_dir) :
    '''
    copy src to dst . 
    Attention ! we'll first check if dst path is exists && is dir , if so , we'll firstly remove it !  
    '''
    if not os.path.exists(src_path) :
        logging.warning("source path : %s is not exists . Copy Aborted !" %(src_path))
        return False
    physically_is_dir = os.path.isdir(src_path)
    copy_file_type = "directory" if physically_is_dir else "file"
    if physically_is_dir != is_dir : 
        logging.warning("path : %s is actually %s , dependency file config wrong" %(src_path ,copy_file_type ))
    try :
        if physically_is_dir :
            if os.path.exists(dst_path) :
                shutil.rmtree(dst_path)
            shutil.copytree(src_path , dst_path) # ensure dst_path do not exists
        else :
            head_path = os.path.split(dst_path)[0]
            if not os.path.exists(head_path) :
                os.makedirs(head_path)
            shutil.copy2(src_path , dst_path) # ensure dst_path's dir be exists
    except Exception , e :
        logging.warning("copy process error when copy %s : %s . detail info : %s" %(copy_file_type , src_path , e))
        return False
    logging.info("copy %s : %s done ." %(copy_file_type , src_path))
    return True

def sync_file_or_dir(src_path , dst_path , path_type , sync_strategy) :
    copy_ret = True
    if sync_strategy == DepChangeState.NO_CHANGE :
        if not os.path.exists(dst_path) :
            copy_ret = copy_file_or_dir(src_path , dst_path , path_type==DepType.DIR)
        else :
            copy_ret = False
    else :
        copy_ret = copy_file_or_dir(src_path , dst_path , path_type==DepType.DIR)
    return copy_ret

def copy_needed_file_and_build_new_virtual_directory_hierarchy(src_root_path , dst_root_path , dep_s , vdh) :
    copy_counter = 0
    all_counter = 0
    for dep in dep_s :
        dep_type = dep['type']
        dep_paths = dep['path'] if type(dep['path']) == list else [dep['path']]
        dep_change_state = dep['change_state']
        for dep_path in dep_paths :
            logging.info("path : %s ; type : %s ; change_state : %s" %(dep_path , dep_type , dep_change_state))
            src_path = os.path.join(src_root_path , dep_path)
            dst_path = os.path.join(dst_root_path , dep_path)
            
            add_directory_hierarchy(vdh , dep_path , dep_type==DepType.DIR )
            sync_state = sync_file_or_dir(src_path , dst_path ,  dep_type , dep_change_state) 
            all_counter += 1
            if sync_state :
                copy_counter += 1
    print "copy result : %d/%d copied" %(copy_counter,all_counter)

def build_keep_stable_virtual_directory_hierarchy(keep_stable_describe_f ) :
    vdh = {}
    if keep_stable_describe_f == None :
        return vdh
    for line in keep_stable_describe_f :
        path = line.strip()
        add_directory_hierarchy(vdh , path , os.path.isdir(path) )
    return vdh

def rm_redundant_files_and_dirs(dst_root_path , new_vdh , keep_stable_vdh) :
    if dst_root_path == "" or not os.path.isdir(dst_root_path) : 
        return
    if new_vdh is None or "*" in new_vdh : # is file or is full dir
        return
    names = os.listdir(dst_root_path)
    for fname in names :
        fpath = os.path.join(dst_root_path , fname)
        if is_hidden_file(fpath) : continue
        if fname in new_vdh :
            ## recursive call to clear redundant in sub dir
            next_dst_root_path = fpath
            next_new_vdh = new_vdh[fname]
            next_keep_stable_vdh = keep_stable_vdh.get(fname , {})
            rm_redundant_files_and_dirs(next_dst_root_path , next_new_vdh , next_keep_stable_vdh)
        else :
            if fname not in keep_stable_vdh :
                rm_file_or_dir(fpath)

def sync_cmakelists(dep_s , dst_root_path) :
    '''
    logic : first , abstract cmakelists paths which need to be sync from dependency struct .  
                  that means : type == cmakelists && change_state == sync (for more stable , we set change_state != NO_CHANGE to replace)
            then , sync all the cmakelists get in former
                  we did follow simple logic : 
                     read line from cmakelists 
                     if match RegEx '*?add_subdirectory\((.+)?\).*' 
                         then check the matched pattern , that should be the dir name . 
                         we check if this dir is exits .
                            if not , we skip this line ,
                            else we rewrite to a tmp file .
                      else 
                          rewrite to a tmp file .  
    '''
    cmakelists_paths = []
    for dep in dep_s :
        if dep['type'] == DepType.CMAKELISTS and dep['change_state'] != DepChangeState.NO_CHANGE :
            for dep_path in dep['path'] :
                cmakelists_paths.append(dep_path)
    for fname in cmakelists_paths :
        fpath = os.path.join(dst_root_path , fname)
        if not os.path.exists(fpath) :
            logging.warning("cmakelists path : %s does not exists" %(fpath))
            continue
        ftmppath = fpath + ".tmp"
        try :
            fpi = open(fpath)
            fpo = open(ftmppath , 'w')
        except IOError , e :
            logging.warning("read cmakelists file : %s , or write file : %s failed . details: %s" %(fpath , ftmppath , e))
        subdir_pattern = re.compile(r".*?add_subdirectory.*?\((.*?)\).*")
        subdir_root_path = os.path.split(fpath)[0]
        for line in fpi :
            match_rst = subdir_pattern.match(line)
            if match_rst is not None and len(match_rst.groups()) > 0 :
                for match_str in match_rst.groups() :
                    dir_name = match_str.strip("\" '")
                    dir_path = os.path.join(subdir_root_path , dir_name)
                    if os.path.exists(dir_path) :
                        fpo.write(line)
                    else :
                        logging.info("cmakelists %s : remove line : %s" %(fpath,line.strip()))
            else :
                fpo.write(line)
        fpi.close()
        fpo.close()
        os.remove(fpath)
        os.rename(ftmppath , fpath)

def main(src_root_path , dst_root_path , dep_f , keep_stable_describe_f ) :
    dep_s = get_segmentor_dependency(dep_f)
    keep_stable_vdh = build_keep_stable_virtual_directory_hierarchy(keep_stable_describe_f)
    new_vdh = {}
    copy_needed_file_and_build_new_virtual_directory_hierarchy(src_root_path , dst_root_path , dep_s , new_vdh )
    rm_redundant_files_and_dirs(dst_root_path , new_vdh , keep_stable_vdh)
    sync_cmakelists(dep_s , dst_root_path)

if __name__ == "__main__" :
    argp = argparse.ArgumentParser(description="keep two dirs synchronization")
    argp.add_argument('-src' , "--src_path" , help="source dir root path" , required=True , type=str)
    argp.add_argument('-dst' , "--dst_path" , help="destination dir root path",required=True , type=str)
    argp.add_argument("-d" , "--dependency_file" , help="the file that describe the dependency of the dest dir , from the src dir . JSON formated. detail info please see the example json file.",required=True , type=argparse.FileType('r'))
    argp.add_argument('-k' , "--keep_stable_file" , help="the file that describe which files and dirs of dest dir shoule be kept stable . one line contains a dir or file path , path is relative to the root dest dir path ",required=False , type=argparse.FileType('r'))
    args = argp.parse_args()
    main(args.src_path , args.dst_path , args.dependency_file , args.keep_stable_file)

    args.dependency_file.close()
    args.keep_stable_file != None and args.keep_stable_file.close()
