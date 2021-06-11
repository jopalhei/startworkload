<#
ToDo : 
- Parameters 
- Comments and Help
- only use -c if file doesn't exists or ins't the required size
- Check if CSV are balanced otherwyse throw a warning
#>

param(
   
   $DiskSpdpath = "C:\Temp\DiskSpd.exe",
   $b = "4"+"K",
   $d = "60",
   $Cache = "-Sh",
   $O = "2",
   $t = "Auto",
   $p = "r",
   $w = "0",
   $file = "testDiskSpd",
   $filesize = "1G"
)

$nodes = Get-ClusterNode

switch(($filesize.Substring($filesize.Length-1)))
{
    "K" {$filesizebytes = (($filesize.Substring(0,$filesize.Length-1)).ToInt32($null))*1Kb}
    "M" {$filesizebytes = (($filesize.Substring(0,$filesize.Length-1)).ToInt32($null))*1Mb}
    "G" {$filesizebytes = (($filesize.Substring(0,$filesize.Length-1)).ToInt32($null))*1Gb}
}

$Workpath = $DiskSpdpath.Substring(0,$DiskSpdpath.LastIndexOf("\"))
$timestamp = Get-Date -UFormat "%Y%m%d%H%M%S"
$respath = $Workpath + "\diskspdresult" + $timestamp + ".txt"

#### Let's Check if DiskSpd is present on all nodes and copy it if not
##checking local node - script should fail if not present on the expected location

If(!(Get-ChildItem $DiskSpdpath -ErrorAction SilentlyContinue))
{
   Write-Host $DiskSpdpath " file not found. Please download diskspd from aka.ms/diskspd" -ForegroundColor Red
   Break 
}
#### Checking on each Node

$errorfound = $false

foreach ($node in $nodes){
   #Frist let's check if Directory Exists
   If(!(Invoke-Command  -ScriptBlock {param($path) Get-Item -Path $path } -ArgumentList $workpath -ComputerName $node -ErrorAction SilentlyContinue))
   {
      Write-Host $Workpath " not found on " $node.Name " will create it now." -ForegroundColor Yellow 
      try{
         Invoke-Command  -ScriptBlock {param($path) New-Item -Path $path -ItemType Directory } -ArgumentList $workpath -ComputerName $node -ErrorAction Stop
      }
      catch{
         $errorfound = $true
         Write-Host "Error found while trying to create the directory " $Workpath " on node " $node.Name
         Write-Host "Error Message: " $_.Exception.Message
         Write-Host "Error was " $_.InvocationInfo.Line
         Break
      }
   }
   
   #Let's Check now if Diskspd is already present on the remote machine
   If(!(Invoke-Command  -ScriptBlock {param($DiskSpdpath) Get-Item -Path $DiskSpdpath } -ArgumentList $DiskSpdpath -ComputerName $node -ErrorAction SilentlyContinue))
   {
      Write-Host "DiskSpd not found on " $node.Name " will copy it now." -ForegroundColor Yellow
      $UncPatch = "\\" + $Node + "\c$" + $DiskSpdpath.Substring(($DiskSpdpath.IndexOf("\")),($DiskSpdpath.Length - ($DiskSpdpath.IndexOf("\"))))
      
      try{
         Copy-Item -Path $DiskSpdpath -Destination $UncPatch
      }
      catch{
         $errorfound = $true
         Write-Host "Error found while trying to copy diskspd.exe to node " $node.Name
         Write-Host "Error Message: " $_.Exception.Message
         Write-Host "Error was " $_.InvocationInfo.Line
         Break
      }

   }
}

if ($errorfound)
{
   Break
}

$csvs = Get-ClusterSharedVolume | where name  -NotLike "*Collect*"

## Let's adjust the number of Threads if Auto was set.
## The number of Threads will be the Number of Logical Processors / Number of CSV's (Targets)
## We assume that all Cluster Nodes have the same CPU's
if ($t -eq "Auto")
{
    $cs = Get-WmiObject -class Win32_ComputerSystem
    $Cores=$cs.numberoflogicalprocessors
    [int]$t = $cores / $csvs.Count
    ## Just in case we have more CSV's then CPU's, shouldn't happen but worth checking
    if ($t -eq 0){
        $t = 1
    }
}

$worklist = @()
foreach ($node in $nodes){
   $server = $node.Name
   $number = $node.Id
   $targets = $null
   foreach($csv in $csvs)
   {
      
      $CSVPath = $csv.SharedVolumeInfo.FriendlyVolumeName
      $destfile = $CSVPath + "\" + $file + $number + ".vhdx "
      $targets = $targets + $destfile
      $destfile = Get-ChildItem -Path $destfile -ErrorAction SilentlyContinue

      if ($destfile -ne $null -and $destfile.Length -eq $filesizebytes)
      {
            $c = $null
      }
      else { $c = " -c" + $filesize}


   }
   $cmd = $DiskSpdpath +" -b" + $B + " -d" + $d +" " +  $Cache + " -o" + $O + " -t" + $t + " " + "-" + $p + " -w" + $w + $c + " " + $targets +" > " + $respath

   $work = [PSCustomObject]@{
        Server = $server
        Cmd = $cmd}
   
   $worklist += $work   
}

foreach($task in $worklist)
{
    $server = $task.Server
    $cmd = $task.Cmd
    $jobs = Start-Job -Name DiskSpd -ScriptBlock {param ($server,$cmd) Invoke-Command -ComputerName $server -ScriptBlock  {param($cmd) &cmd /c $cmd } -ArgumentList $cmd} -ArgumentList $Server,$cmd
}


Start-Sleep -Seconds 3
Get-Job -State Running