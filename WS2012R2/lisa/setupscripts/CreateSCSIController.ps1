param([string] $vmName, [string] $hvServer, [string] $testParams)

############################################################################
#
# CreateController
#
# Description
#     Create a SCSI controller if one with the ControllerID does not
#     already exist.
#
############################################################################
function CreateController([string] $vmName, [string] $server, [string] $controllerID)
{
    #
    # Hyper-V only allows 4 SCSI controllers - make sure the Controller ID is valid
    #
    if ($ControllerID -lt 0 -or $controllerID -gt 3)
    {
        write-output "    Error: Bad SCSI controller ID: $controllerID"
        return $false
    }

    #
    # Check if the controller already exists
    # Note: If you specify a specific ControllerID, Get-VMDiskController always returns
    #       the last SCSI controller if there is one or more SCSI controllers on the VM.
    #       To determine if the controller needs to be created, count the number of
    #       SCSI controllers.
    #
    $maxControllerID = 0
    $createController = $true
    $controllers = Get-VMScsiController -VMName $vmName -ComputerName $server

    if ($controllers -ne $null)
    {
        if ($controllers -is [array])
        {
            $maxControllerID = $controllers.Length
        }
        else
        {
            $maxControllerID = 1
        }

        if ($controllerID -lt $maxControllerID)
        {
            "Info : Controller exists - controller not created"
            $createController = $false
        }
    }

    #
    # If needed, create the controller
    #
    if ($createController)
    {
        $ctrl = Add-VMSCSIController -VMName $vmName -ComputerName $server -Confirm:$false
        if($? -ne $true)
        {
            "Error: Add-VMSCSIController failed to add 'SCSI Controller $ControllerID'"
            return $false
        }
        else
        {
            return $true
        }
    }
}

$retval = CreateController $vmName $hvServer 1

if (-not $retval)
{
    "Error: Unable to create the SCSI controller"
    return $retVal
}

$retval = $true
"SCSI Controller successfully added"
return $retval
