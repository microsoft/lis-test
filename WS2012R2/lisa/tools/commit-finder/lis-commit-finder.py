###################################################################################
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
####################################################################################
# 
# hyperv-commit-finder.py
#
# Discription:
# This script to find missing commit id's in distro source code compared to linux-next
# You need to provide distro source and linux next saource 
# e.g.  source1path="/root/src/linux-3.10.0-223.el7/"
#       source2path="/root/linux-next/" 
# This script has dependecies on config file which contain the files to be comapred
# currently config is provided with this script, you should edit it if you want to 
# compare something else. 
# it will create a result file in your HOME directory names commit-result.
#
####################################################################################

##################################################################################
import os 
import glob
import filecmp
import shutil
from itertools import groupby 
import sys 
import subprocess 
from collections import OrderedDict 

######################################################################################
def run(a):
    return os.system(a)


######################################################################################
def block_start(line, start=[None]): 
    if line.startswith('commit'):
        start[0] = not start[0] 
    return start[0]  


######################################################################################
def diffblock_start(line, start=[None]): 
    if line.startswith('@@'): 
        start[0] = not start[0]
    return start[0] 


#####################################################################################
def difffile(source1 , source2 ,filenamediff):
    print(" diff -u" + " " + source1 + " " + source2 + " >" + " " + filenamediff)
    diff = run(" diff -u" + " " + source1 + " " + source2 + " >" + " " + filenamediff)
    return True


######################################################################################
def appendfile(filename,data): 
    with open(filename, "a") as file: 
        file.write(data) 


######################################################################################
def writefile(filename,data): 
    with open(filename, "w") as file: 
        file.write(data) 
    return filename 
 

######################################################################################
def newfilename(filename,filecounter, filenamelist): 
    newfile = ("%s%s" % (filename, filecounter)) 
    filenamelist.append(newfile) 
    return newfile 
 
 
 #####################################################################################
def update_finaldifflist(filenamelist): 
    for filen in filenamelist:
        f = open(filen, 'r')
        lines = f.readlines()
        f.close()
        with open(filen, 'w') as f:
            f.write("".join(lines[1:]))
            f.close()


#####################################################################################
def get_Diffpatches(filename, listname, functiontocall): 
    with open(filename) as file: 
        block_sizes = [sum(1 for line in block) # find number of lines in a block 
                  for _, block in groupby(file, key=functiontocall)] # group
    file.close() 
    blockcounter = 0 
    linecounter = 0 
    filecounter = 0  

    for block in block_sizes :
        linecounter = block + linecounter
        newfile = writefile(newfilename(filename, filecounter, listname),"")
        filecounter = filecounter + 1 
        with open(filename) as file: 
            for idx,item in enumerate(file):
                if (blockcounter <= idx and linecounter >= idx) :
                    appendfile(newfile ,item)
                    if idx == linecounter - 1 :
                        blockcounter = linecounter
                        break
    return True 


#####################################################################################
def get_commitfile():
    for filename in newfilenamelist:
        with open(filename) as file:
            for line in file:
                if line.startswith('commit'):
                    newfile = line.strip()
        
        k = filename.rfind("/")
        new_string = filename[:k + 1]
        check = new_string + newfile
        os.rename(filename, check)
        commitfilelist.append(check)


#####################################################################################
def get_subject():
    for filename in commitfilelist:
        with open(filename) as file:
            lines = file.readlines()
        for number in range(0,len(lines)):
                if lines[number].startswith('Date'):
                    for currentnumber in range(number+1,len(lines)):
                        if lines[currentnumber] != '\n':
                            k = filename.rfind("/")
                            commitID = filename[k+1:]
                            commitinfo_dict[commitID] = lines[currentnumber]
                            break

   
#####################################################################################
def get_filestrip(filelist):
    for filename in filelist:
        with open(filename) as file:
            lines = file.readlines()
        open(filename, 'w').close()
        with open(filename, 'w') as filen:
            for line in lines:
                line = line.rstrip()
                filen.writelines(line)


#######################################################################################
def get_commitblock():
    for filename in commitfilelist:
        with open(filename) as file:
            lines = file.readlines()
        open(filename, 'w').close()
        with open(filename, 'w') as filen:
            for number in range(0,len(lines)):
                if lines[number].startswith('@@'):
                    filen.write(lines[number])
                    for currentnumber in range(number + 1,len(lines)):
                        if lines[currentnumber].startswith('@@'):
                            break
                        else :
                            filen.write(lines[currentnumber])
                    break

#########################################################################################
def preSet():
    update_finaldifflist(difffilelist)
    get_commitfile()
    get_subject()
    get_commitblock()
    update_finaldifflist(commitfilelist)
    get_filestrip(difffilelist)
    get_filestrip(commitfilelist)


#########################################################################################
def get_missinglist():
    for diffile in difffilelist:
#        missinglist.append(commitfile)
    	for commitfile in commitfilelist:
            if filecmp.cmp(commitfile, diffile):
                missinglist.append(commitfile)
                commitfilelist.remove(commitfile)
                break

#########################################################################################
def listtofile():
    for listdata in missinglist:
       k = listdata.rfind("/")
       new_string = listdata[k + 1:]
       with open(outfilename, "a")  as file:
         file.write(filename + " : " + new_string + " : " + commitinfo_dict[new_string])
        
            
######################################################################## Entry Point for this script ############################################################################################

source1path = raw_input("please enter path to distro source code: ")
source2path = raw_input("please enter path to linux-next source code: ")

if not source1path.endswith('/'):
    source1path=source1path+'/'

if not source2path.endswith('/'):
    source2path=source2path+'/'

# Create a directory where this script will run and process file
home = os.environ['HOME']
tmp = home + "/test"
if not os.path.exists(tmp):
    os.makedirs(tmp)

# Creating list from config file, it will contain all the file name we need to
# process
configfilename = "/root/config"

outfilename = home + "/commit-result"
if os.path.isfile(outfilename):
    os.remove(outfilename)

with open(configfilename) as configfile:
    for line in configfile:
        if line == '\n':
            continue
        filename = subprocess.check_output("echo " + line.rstrip() + " | rev | cut -d '/' -f1 | rev",shell=True).rstrip() 
        filepath = line.rstrip()
        source1 = source1path + filepath
        source2 = source2path + filepath
        filenamediff = tmp + "/" + filename + ".diff"

        # Now do the diff of source file, if there is any error exit the program.
        status = difffile(source1 , source2, filenamediff)
        if status : 
            print("Done diffing the source file")
        else :
            print("Error in diffing of source file exiting now..")
            sys.exit(1)

        # updating filename with git prefix this file will contain git logs
        filename_diff = tmp + "/git_" + filename

        #### now write git log file .
        os.chdir(home + "/linux-next")
        run("git log -p " + filepath + " >" + filename_diff)

        # create a list to store newfile name
        newfilenamelist = [] 
        difffilelist = []
        commitfilelist = []
        missinglist = []
        commitinfo_dict = {}

        # Git log will give one big file of all the commit's , we have to extract
        # single commit .
        if(get_Diffpatches(filename_diff, newfilenamelist, block_start)):
            print("Commit Patches extracted successfully")
        else: 
            print("Error extracting commit patches exiting now")
            sys.exit(1)

        del newfilenamelist[-1]

        # Diff log will give one big file of all the difference betwwen upstream and
        # lis , we have to extract single difference block .
        if(get_Diffpatches(filenamediff, difffilelist, diffblock_start)):
            print("Diff Patches extracted successfully")
        else:
            print("Error extracting Diff patches exiting now")
            sys.exit(1)

        # Pre set before verifying the missing commit
        preSet()

        # check for the missing commit
        get_missinglist()

        # Missing commit output file
        listtofile()

        # clean up
#        tfiles = glob.glob(tmp+'/*')
#        for delitem in tfiles:
#            os.remove(delitem)
#        newfilenamelist[:] = []
#        difffilelist[:] = []
#        commitfilelist[:] = []
#        missinglist[:] = []
#        commitinfo_dict.clear()

#shutil.rmtree(tmp)
