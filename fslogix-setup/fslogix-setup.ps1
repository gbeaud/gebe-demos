# This script installs fslogix and sets the registry to point to the folder where profiles are located. It can be applied at scale or directly from the Azure portal using Run Command on the VMs.

#Variables: replace these with your domain-joined storage account unique name and profile folder name
$storageAccountName = "saavdfslogix"
$profileFolderName = "userprofile"

#Create Directories
$LabFilesDirectory = "C:\LabFiles"

if(!(Test-path -Path "$LabFilesDirectory")){
New-Item -Path $LabFilesDirectory -ItemType Directory |Out-Null
}
if(!(Test-path -Path "$LabFilesDirectory\FSLogix")){
New-Item -Path "$LabFilesDirectory\FSLogix" -ItemType Directory |Out-Null
}

#Download FSLogix Installation bundle

if(!(Test-path -Path "$LabFilesDirectory\FSLogix_Apps_Installation.zip")){
      Invoke-WebRequest -Uri "https://experienceazure.blob.core.windows.net/templates/wvd/FSLogix_Apps_Installation.zip" -OutFile     "$LabFilesDirectory\FSLogix_Apps_Installation.zip"

#Extract the downloaded FSLogix bundle
function Expand-ZIPFile($file, $destination){
    $shell = new-object -com shell.application
    $zip = $shell.NameSpace($file)
    foreach($item in $zip.items()){
    $shell.Namespace($destination).copyhere($item)
    }
}

Expand-ZIPFile -File "$LabFilesDirectory\FSLogix_Apps_Installation.zip" -Destination "$LabFilesDirectory\FSLogix"

}
  #Install FSLogix
  if(!(Get-WmiObject -Class Win32_Product | where vendor -eq "FSLogix, Inc." | select Name, Version)){
      $pathvargs = {C:\LabFiles\FSLogix\x64\Release\FSLogixAppsSetup.exe /quiet /install }
      Invoke-Command -ScriptBlock $pathvargs
  }
  #Create registry key 'Profiles' under 'HKLM:\SOFTWARE\FSLogix'
  $registryPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
  if(!(Test-path $registryPath)){
      New-Item -Path $registryPath -Force | Out-Null
  }

  #Add registry values to enable FSLogix profiles, add VHD Locations, Delete local profile and FlipFlop Directory name
  New-ItemProperty -Path $registryPath -Name "VHDLocations" -Value "\\$storageAccountName.file.core.windows.net\$profileFolderName" -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $registryPath -Name "Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $registryPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $registryPath -Name "FlipFlopProfileDirectoryName" -Value 1 -PropertyType DWord -Force | Out-Null

  #Display script completion in console
  Write-Host "Script Executed successfully"