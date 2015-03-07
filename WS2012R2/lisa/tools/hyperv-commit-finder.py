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
import os
from itertools import groupby
import sys
import subprocess
from collections import OrderedDict

#####################################################################################
def run(a):
 return os.system(a)
######################################################################################
def writefile(filename,data):
 with open(filename, "w") as file:
  file.write(data)
  return filename

######################################################################################
def appendfile(filename,data):
 with open(filename, "a") as file:
  file.write(data)

#####################################################################################
def difffile(source1 , source2 ,filenamediff):
 print (" diff -u" + " " + source1 + " " + source2 + " >" + " " + filenamediff)
 diff = run(" diff -u" + " " + source1 + " " + source2 + " >" + " " + filenamediff)
 return True

######################################################################################
# process the diff file to remove all other unneccsary lines keep only + and - line . 
def processdifffile(filenamediff):
 done=False
 file = open(filenamediff)
 lines=file.readlines()
 filelist=list(OrderedDict.fromkeys(lines))
 for line in filelist :
  if line.startswith('++') or line.startswith('--'):
   continue
  if line.endswith('+\n') or line.endswith('-\n'):
   continue
  if line.startswith('+{') or line.startswith('+}') or line.startswith('-}') or line.startswith('-{') :
   continue
  if line.startswith('+') or line.startswith('-'):
   appendfile(processedfilename,line)
   done=True
 file.close()
 return done

######################################################################################
def block_start(line, start=[None]):
 if line.startswith('commit'):
  start[0] = not start[0]
 return start[0]

######################################################################################
def newfilename(filename,filecounter):
 newfile = ("%s%s"  %(filename, filecounter) )
 newfilenamelist.append(newfile)
 return newfile

#####################################################################################
def get_patches(filename):
 with open(filename) as file:
   block_sizes = [sum(1 for line in block) # find number of lines in a block
                 for _, block in groupby(file, key=block_start)] # group
 file.close()
 blockcounter=0
 linecounter=0
 filecounter=0

 for block in block_sizes :
  linecounter = block + linecounter
  newfile=writefile(newfilename(filename,filecounter),"")
  filecounter = filecounter + 1
  with open(filename) as file:
   for idx,item in enumerate(file):
    if ( blockcounter <= idx and linecounter >= idx) :
     appendfile(newfile ,item)
     if idx == linecounter-1 :
      blockcounter=linecounter
      break
 return True 

#####################################################################################
def printoutfile():
 for item in outfile:
  writefile(commitids, item)

#####################################################################################
def compareline(newfilenamelist):

 # Covert processedfilename to list for better manipulation.
 opendiffilelist=[]
 opendiffile = open(processedfilename,'r')
 opendiffilelist=opendiffile.readlines()
 opendiffile.close()

 # this list will contain all missed commit id .
 outfile=[]
 # Create a dup list to modify removal of element this is required becasue we can not modify the original list if we iterating over it .
 duplist= list(opendiffilelist)

 done = False
 for filename in newfilenamelist:
  openfilename = open (filename)
  openfilenamelist=openfilename.readlines()
  openfilename.close()
  if done:
   break
  for list1 in opendiffilelist:
   if  not duplist :
    print "List is empty"
    done = True
    break
   for line in openfilenamelist:
    if line.startswith('commit'):
     commitid=line
    if list1 in line :
     if list1 not in duplist:
      duplist.remove(list1)
     if commitid not in outfile: 
      outfile.append(commitid)

 return outfile

######################################################################## Entry Point for this script ############################################################################################

source1path = raw_input("please enter path to distro source code: ")
source2path = raw_input("please enter path to linux-next source code: ")

# Create a directory where this script will run and process file
home=os.environ['HOME']
tmp=home+"/test"
if not os.path.exists(tmp):
 os.makedirs(tmp)

# Creating list from config file, it will contain all the file name we need to process
configfilename="/root/config"

outfilename=home+"/commit-result"
if os.path.isfile(outfilename):
 os.remove(outfilename)

with open(configfilename) as configfile:
 for line in configfile:
  filename=subprocess.check_output("echo " +line.rstrip()+ " | rev | cut -d '/' -f1 | rev",shell=True).rstrip() 
  filepath=line.rstrip()
  source1=source1path+filepath
  source2=source2path+filepath
  filenamediff=tmp+"/"+filename+".diff"

  # create a new file to keep lines which has only + and - from filenamediff
  processedfilename=tmp+"/processed"+filename
  writefile(processedfilename,"")

  # Now do the diff of source file, if there is any error exit the program.
  status=difffile(source1 , source2, filenamediff)
  if status : 
   print "Done diffing the source file"
  else :
   print "Error in diffing of source file exiting now.."
   sys.exit(1)

  if processdifffile(filenamediff):
   print "done processing file"+ filenamediff
  else:
   print "Error processing file" + filenamediff
  
  # updating filename with git prefix this file will contain git logs
  filename_diff = tmp+"/git_"+filename

  #### now  write git log file .
  os.chdir(home+"/linux-next")
  run("git log -p " + filepath + " >" + filename_diff)

  # create a list to store newfile name this will be used in compareline()
  newfilenamelist=[]

  # Git log will give one big file of all the commit's , we have to extract single commit .
  if get_patches(filename_diff):
   print "Patches extracted successfully"
  else: 
   print "Error extracting patches exiting now"
   sys.exit(1) 
  #function to get missing commit id's. 
  outfile=compareline(newfilenamelist)
 
  #Now write the lis to file to read it later . 
  for output in outfile:
   with open (outfilename, "a")  as file:
    file.write(filename+" : ")
    file.write(output)
 

       







