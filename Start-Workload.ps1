<#
ToDo : 
- Parameters 
- Comments and Help
- only use -c if file doesn't exists or ins't the required size
- Check if CSV are balanced otherwyse throw a warning


#>

param(
   
   $path = (Get-Location).Path,
   $B = "64"+"K",
   $D = "600",
   $Cache = "-Sh",
   $O = "12",
   $t = "32",
   $p = "-r",
   $w = "50",
   $file = "test",
   $filesize = "10G"
)



$nodes = Get-ClusterNode
switch(($filesize.Substring($filesize.Length-1)))
{
    "K" {$filesizebytes = (($filesize.Substring(0,$filesize.Length-1)).ToInt32($null))*1Kb}
    "M" {$filesizebytes = (($filesize.Substring(0,$filesize.Length-1)).ToInt32($null))*1Mb}
    "G" {$filesizebytes = (($filesize.Substring(0,$filesize.Length-1)).ToInt32($null))*1Gb}
}
$expath = $path + "\diskspd.exe"
$timestamp = Get-Date -UFormat "%Y%m%d%H%M%S"
$respath = $path + "\diskspdresult" + $timestamp + ".txt"


foreach ($node in $nodes){
   $server = $node.Name
   $number = $node.Id
   $targets = $null
   foreach($csv in (Get-ClusterSharedVolume | where name  -NotLike "*Collect*"))
   {
      
      $CSVPath = $csv.SharedVolumeInfo.FriendlyVolumeName
      $destfile = $CSVPath + "\" + $file + $number + ".dat "
      $targets = $targets + $destfile
      $destfile = Get-ChildItem -Path $destfile -ErrorAction SilentlyContinue

      if ($destfile -ne $null -and $destfile.Length -eq $filesizebytes)
      {
            $c = $null
      }
      else { $c = " -c" + $filesize}


   }
   $cmd = $exPath +" -b" + $B + " -d" + $d +" " +  $Cache + " -o" + $O + " -t" + $t + " " + $p + " -w" + $w + $c + " " + $targets +" > " + $respath
   Start-Job -Name DiskSpd -ScriptBlock {param ($server,$cmd) Invoke-Command -ComputerName $server -ScriptBlock  {param($cmd) &cmd /c $cmd } -ArgumentList $cmd} -ArgumentList $Server,$cmd
}
