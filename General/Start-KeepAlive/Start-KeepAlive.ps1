<#
.Synopsis
   This is a pecking bird function, a press on the <Ctrl> key will run every 5 minues.
.DESCRIPTION
   This function will run a background job to keep your computer alive. By default a KeyPess of the <Ctrl> key will be pushed every 5 minutes.
   Please be aware that this is a short term workaround to allow you to complete an otherwise impossible task, such as download a large file.
   This function should only be run when your computer is locked in a secure location.
.EXAMPLE
   Start-KeepAlive
   Id     Name            PSJobTypeName   State         HasMoreData     Location            
   --     ----            -------------   -----         -----------     --------            
   90     KeepAlive       BackgroundJob   Running       True            localhost           

   KeepAlive set to run until 10/01/2012 00:35:03

   By default the keepalive will run for 1 hour, with a keypress every 5 minutes.
.EXAMPLE
   Start-KeepAlive -KeepAliveHours 3
   Id     Name            PSJobTypeName   State         HasMoreData     Location            
   --     ----            -------------   -----         -----------     --------            
   92     KeepAlive       BackgroundJob   Running       True            localhost           

   KeepAlive set to run until 10/01/2012 02:36:12
   
   You can specify a longer KeepAlive period using the KeepAlive parameter E.g. specify 3 hours
.EXAMPLE
   Start-KeepAlive -KeepAliveHours 2 -SleepSeconds 600
   
   You can also change the default period between each keypress, here the keypress occurs every 10 minutes (600 Seconds).
.EXAMPLE
   KeepAliveHours -Query
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 19.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 14.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 9.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 4.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around -0.04 Minutes

   KeepAlive has now completed.... job will be cleaned up.

   KeepAlive has now completed.

   Run with the Query Switch to get an update on how long the timout will have to run.
.EXAMPLE
   KeepAliveHours -Query
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 19.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 14.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 9.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around 4.96 Minutes
   Job will run till 09/30/2012 17:20:05 + 5 minutes, around -0.04 Minutes

   KeepAlive has now completed.... job will be cleaned up.

   KeepAlive has now completed.
   
   The Query switch will also clean up the background job if you run this once the KeepAlive has complete..EXAMPLE
.EXAMPLE
   KeepAliveHours -EndJob
   KeepAlive has now ended...
   
   Run Endjob once you download has complete to stop the Keepalive and remove the background job.
.EXAMPLE
   KeepAliveHours -EndJob
   KeepAlive has now ended...

   Run EndJob anytime to stop the KeepAlive and remove the Job.
.INPUTS
   KeepAliveHours - The time the keepalive will be active on the system
.INPUTS
   SleepSeconds - The time between Keypresses. This should be less than the timeout of your computer screensaver or lock screen.
.OUTPUTS
   This cmdlet creates a background job, when you Query the results the status from the background job will be outputed on the screen to let you know how long the KeepAlive will run for.
.NOTES
   Original Script: https://gallery.technet.microsoft.com/scriptcenter/Keep-Alive-Simulates-a-key-9b05f980
.COMPONENT
   This is a standlone cmdlet, you may change the keystroke to do something more meaningful in a different scenario that this was originally written.
.ROLE
   This utility should only be used in the privacy of your own home or locked office.
.FUNCTIONALITY
   Call this function to enable a temporary KeepAlive for your computer. Allow you to download a large file without sleepin the computer.

   If the KeepAlive ends and you do not run -Query or -EndJob, then the completed job will remain.

   You can run Get-Job to view the job. Get-Job -Name KeepAlive | Remove-Job will cleanup the Job.

   By default you cannot create more than one KeepAlive Job, unless you provide a different JobName. There should be no reason to do this. With Query or EndJob, you can cleanup any old Jobs and then create a new one.
#>
param (
    $KeepAliveHours = 8,
    $SleepSeconds = 60,
    $JobName = "KeepAlive",
    [Switch]$EndJob,
    [Switch]$Query,
    $KeyToPress = '^' # Default KeyPress is <Ctrl>
    # Reference for other keys: http://msdn.microsoft.com/en-us/library/office/aa202943(v=office.10).aspx
    # newer reference: https://docs.microsoft.com/en-us/dotnet/api/system.windows.forms.sendkeys?view=netframework-4.7.2
)

Add-Type -AssemblyName System.Windows.Forms
#[System.Windows.Forms.SendKeys]::SendWait("%n{TAB}{ENTER}")

$Endtime = (Get-Date).AddHours($KeepAliveHours)

function FindKeepAliveJob() {
    Get-Job -Name $JobName -ErrorAction SilentlyContinue
}


function DoEndJob() {
    Write-Host ""
    if (FindKeepAliveJob)
    {
        Stop-Job -Name $JobName
        Remove-Job -Name $JobName
        write-host "$JobName has now ended..." -ForegroundColor Green
    }
    else
    {
        write-host "No job $JobName." -ForegroundColor Yellow
    }
}


function DoQuery() {
    Write-Host ""
    try {
        if ((Get-Job -Name $JobName -ErrorAction Stop).PSEndTime) {
            Receive-Job -Name $JobName
            Remove-Job -Name $JobName
            write-host "$JobName has now completed."
        }
        else {
            Receive-Job -Name $JobName -Keep
        }
    }
    catch {
        Receive-Job -Name $JobName -ErrorAction SilentlyContinue
        write-host "$JobName has ended or is not running"
        FindKeepAliveJob | Remove-Job
    }
}


function DoWork() {
    $Job = {
        param ($Endtime, $SleepSeconds, $JobName, $KeyToPress)

        "Starttime is $(Get-Date)"
        Add-Type -AssemblyName System.Windows.Forms
                
        While ((Get-Date) -le (Get-Date $EndTime)) {
            # Wait SleepSeconds to press (This should be less than the screensaver timeout)
            Start-Sleep -Seconds $SleepSeconds

            $Remaining = [Math]::Round( ( (Get-Date $Endtime) - (Get-Date) | Select-Object -ExpandProperty TotalMinutes ),2 )
            "Job will run till $EndTime + $([Math]::Round( $SleepSeconds/60 ,2 )) minutes, around $Remaining Minutes"

            # This is the sending of the KeyStroke
            #$x = New-Object -COM WScript.Shell
            #$x.SendKeys($KeyToPress)
            [System.Windows.Forms.SendKeys]::SendWait("^")
        }
    }

    $JobProperties =@{
        ScriptBlock  = $Job
        Name         = $JobName
        ArgumentList = $Endtime,$SleepSeconds,$JobName,$KeyToPress
    }

    Start-Job @JobProperties

    "`nKeepAlive set to run until $EndTime"
}

# Manually end the job and stop the KeepAlive.
if ($EndJob.IsPresent) {
    DoEndJob
    return
}

# Query the current status of the KeepAlive job.
if ($Query.IsPresent)
{
    DoQuery
    return
}

if (FindKeepAliveJob) {
    write-host "$JobName already started, please use: Start-Keepalive -Query" -ForegroundColor Cyan
    return
}

DoWork