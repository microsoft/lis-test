########################################################################
#
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
########################################################################

import sys, getopt

#
# Getting Arguments
#

argv = sys.argv[1:]

html_file = ''
output_file = ''
order_file = ''
html = []

opts, args = getopt.getopt(argv,"h:O:o:")

for opt, arg in opts:
        if opt == '-h':
                html_file = arg
        elif opt in ("-O"):
                order_file = arg
        elif opt in ("-o"):
                output_file = arg

if html_file == '':
	print ("You need to specify input file (-h)")
	exit(1)
if output_file == '':
	print ("you need to specify output file (-o)")
	exit(1)
if order_file == '':
	print ("you need to specify order file (-O)")
	exit(1)

#
# Open html file
#

file = open(html_file, 'r')
text = file.read()
html = text.split('\n')

#
# The script needs to get only the <tr></tr>s from center table  
#

center = []
reach_center = 0

for row in html:
    if row.find('<table width="80%" cellpadding=1 cellspacing=1 border=0>') != -1:
        reach_center = 1
    if row.find(" </table>") != -1:
        reach_center = 0
        center.append(row)
    if reach_center == 1:
        center.append(row)

#
# Grouping every <tr></tr> in its own list 
# 
      
lines = [[]]
reach_tr = 0

for row in center:
    if row.find(" <tr>") != -1:
        line = []
        reach_tr = 1
    if row.find(" </tr>") != -1:
        reach_tr = 0
        line.append(row)
        lines.append(line)
    if reach_tr == 1:
        line.append(row)
        
#
# Open the order file
#

file = open(order_file, 'r')
text = file.read()
order = text.split('\n')

#
# Sorting <tr></tr>s after data from the order file
#

newLines = [[]]
groupHead=("    <tr>", '        <td class="lineno"><pre>subs</pre></td>', "    </tr>")

# No need to sort the first 3 <tr></tr>s

for i in range (0, 3):
    newLines.append(lines[i])

for row in order:
    try:
        if row[0] == '#':
            tempHead = list(groupHead)
            tempHead[1] = tempHead[1].replace("subs", row.replace("#", ""))
            newLines.append(tempHead)
            continue    
        else:
            for i in range(3, len(lines) - 1):
                if lines[i][1].count(row) > 0:
                    newLines.append(lines[i])
                    lines.pop(i)
    except:
        continue

# Putting the <tr></tr>s with unspecified file parameter at the end of the table
                
if len(lines) > 4:
    tempHead = list(groupHead)
    tempHead[1] = tempHead[1].replace("subs", "Others")
    newLines.append(tempHead)
    for i in range(3, len(lines) - 1):
        newLines.append(lines[i])

# No need to sort the last <tr></tr>
        
newLines.append(lines[len(lines) - 1])
newLines.pop(0)

#
# Building new html
#

reach_table = 0        

# Remove old table

for i in range(0, len(html)):
    if html[i].find('<table width="80%" cellpadding=1 cellspacing=1 border=0>') != -1:
        i += 1
        while html[i].find(' </table>') == -1:
            html.pop(i)
        break

# Add sorted table
        
for i in range(0, len(html)):
    if html[i].find('<table width="80%" cellpadding=1 cellspacing=1 border=0>') != -1:
        i += 1
        for k in range(len(newLines) - 1, -1, -1):
            html.insert(i ,"")
            for j in range (len(newLines[k]) - 1, -1, -1):
                html.insert (i, newLines[k][j])

# Convert from list to sting and add line terminator
                
newHtml = ""
for row in html:
    newHtml += row + '\n'

#
# Write output file
#
   
file = open(output_file, "w")
file.write(newHtml)
