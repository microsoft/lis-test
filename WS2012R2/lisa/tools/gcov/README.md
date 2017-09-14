These scripts does coverage data collecting and processing for the LIS daemons and drivers

Tested on CentOS 7 with the Kvp test suite.

## Requirements.
~~~
Python 2.7
pip
Gcovr
~~~
## Stepts to install gcovr.
~~~
# Download get-pip.py from https://bootstrap.pypa.io/get-pip.py
python get-pip.py
python -m pip install gcovr
# See notes for details
~~~

## Steps to use the coverage feature.
~~~
1.Modify the xml test with the postTest parameter and the SourcePath parameter as in example #1.
    GcovDataCollect.ps1 is used to collect coverage data from VM.
    SourcePath is used to specify the path to the linux kernel sources that were built for coverage.
2.Add one more <test> entry for the coverage data processing part as in example #2.
    GcovGroupFile is used to specify the grouping of the coverage files in the output html (see #3 for details).
    Python2 is used to specify the path to Python 2.7 in the system (see Notes for details).
3.Modify ./tools/gcov/gcov_group file with the order and grouping rules as in example #3.
4.Modify ./remote-scrips/ica/collect_gcov_data.sh with the desired files that will be collected.
~~~

## Examples.
1)
~~~
    <test>
        <testName>SQM_Basic</testName>
        <testScript>SetupScripts\SQM_Basic.ps1</testScript>
        <postTest>SetupScripts\GcovDataCollect.ps1</postTest>
        <timeout>600</timeout>
        <onError>Continue</onError>
        <noReboot>False</noReboot>
        <testparams>
            <param>TC_COVERED=SQM-01</param>
            <param>SourcePath=/root/linux-4.13.0-rc6-01699-g0874b58</param>
        </testparams>
    </test>
~~~
2)
~~~
    <suiteTests>
        <!-- Suite Tests -->
        <suiteTest>GCOVR</suiteTest>
    </suiteTests>
    
    <testCases>
        <!-- Suite TestCases -->
        <test>
            <testName>GCOVR</testName>
            <testScript>setupscripts\GCOV_Data_Group.ps1</testScript>>
            <timeout>3600</timeout>
            <testparams>
                <param>GcovGroupFile=gcov_group</param>
                <param>Python2=C:\Python27</param>
            </testparams>
        </test>
    </testCases>
~~~
3)
~~~
#Daemons
hv_kvp_daemon.c
hv_vss_daemon.c
#Network
netvsc.c
~~~


## Notes.

   If you want to use gcovr outside lisa you must run it as:  
   python "$pathToPython27\Scripts\gcovr" #Where $pathToPython27 is the complete path to python 2.7

   The python based tools (gcovr and gcovr-group.py) only work with python 2.7 so if you
don't have it in Path, specify the path to python 2.7 using the Python2 parameter.

   The coverage files that are uploaded but are missing in the gcov_group file will appear
in the "Others" section of the resulting html coverage file.

   The repo is already set to run Kvp test suite with the coverage feature using GcovKvpTests suite.
