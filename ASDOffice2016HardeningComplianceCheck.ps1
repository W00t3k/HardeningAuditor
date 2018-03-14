﻿[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string[]]$ComputerName = $env:COMPUTERNAME,
    [switch]$ShowAllInstalledProducts,
    [System.Management.Automation.PSCredential]$Credentials
)

Function Get-OfficeVersion {
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true, Position=0)]
    [string[]]$ComputerName = $env:COMPUTERNAME,
    [switch]$ShowAllInstalledProducts,
    [System.Management.Automation.PSCredential]$Credentials
)

begin {
    $HKLM = [UInt32] "0x80000002"
    $HKCR = [UInt32] "0x80000000"

    $excelKeyPath = "Excel\DefaultIcon"
    $wordKeyPath = "Word\DefaultIcon"
   
    $installKeys = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                   'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'

    $officeKeys = 'SOFTWARE\Microsoft\Office',
                  'SOFTWARE\Wow6432Node\Microsoft\Office'

    $defaultDisplaySet = 'DisplayName','Version', 'ComputerName'

    $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$defaultDisplaySet)
    $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
}

process {

 $results = new-object PSObject[] 0;
 $MSexceptionList = "mui","visio","project","proofing","visual"

 foreach ($computer in $ComputerName) {
    if ($Credentials) {
       $os=Get-WMIObject win32_operatingsystem -computername $computer -Credential $Credentials
    } else {
       $os=Get-WMIObject win32_operatingsystem -computername $computer
    }

    $osArchitecture = $os.OSArchitecture

    if ($Credentials) {
       $regProv = Get-Wmiobject -list "StdRegProv" -namespace root\default -computername $computer -Credential $Credentials
    } else {
       $regProv = Get-Wmiobject -list "StdRegProv" -namespace root\default -computername $computer
    }

    [System.Collections.ArrayList]$VersionList = New-Object -TypeName System.Collections.ArrayList
    [System.Collections.ArrayList]$PathList = New-Object -TypeName System.Collections.ArrayList
    [System.Collections.ArrayList]$PackageList = New-Object -TypeName System.Collections.ArrayList
    [System.Collections.ArrayList]$ClickToRunPathList = New-Object -TypeName System.Collections.ArrayList
    [System.Collections.ArrayList]$ConfigItemList = New-Object -TypeName  System.Collections.ArrayList
    $ClickToRunList = new-object PSObject[] 0;

    foreach ($regKey in $officeKeys) {
       $officeVersion = $regProv.EnumKey($HKLM, $regKey)
       foreach ($key in $officeVersion.sNames) {
          if ($key -match "\d{2}\.\d") {
            if (!$VersionList.Contains($key)) {
              $AddItem = $VersionList.Add($key)
            }

            $path = join-path $regKey $key

            $configPath = join-path $path "Common\Config"
            $configItems = $regProv.EnumKey($HKLM, $configPath)
            if ($configItems) {
               foreach ($configId in $configItems.sNames) {
                 if ($configId) {
                    $Add = $ConfigItemList.Add($configId.ToUpper())
                 }
               }
            }

            $cltr = New-Object -TypeName PSObject
            $cltr | Add-Member -MemberType NoteProperty -Name InstallPath -Value ""
            $cltr | Add-Member -MemberType NoteProperty -Name UpdatesEnabled -Value $false
            $cltr | Add-Member -MemberType NoteProperty -Name UpdateUrl -Value ""
            $cltr | Add-Member -MemberType NoteProperty -Name StreamingFinished -Value $false
            $cltr | Add-Member -MemberType NoteProperty -Name Platform -Value ""
            $cltr | Add-Member -MemberType NoteProperty -Name ClientCulture -Value ""
            
            $packagePath = join-path $path "Common\InstalledPackages"
            $clickToRunPath = join-path $path "ClickToRun\Configuration"
            $virtualInstallPath = $regProv.GetStringValue($HKLM, $clickToRunPath, "InstallationPath").sValue

            [string]$officeLangResourcePath = join-path  $path "Common\LanguageResources"
            $mainLangId = $regProv.GetDWORDValue($HKLM, $officeLangResourcePath, "SKULanguage").uValue
            if ($mainLangId) {
                $mainlangCulture = [globalization.cultureinfo]::GetCultures("allCultures") | where {$_.LCID -eq $mainLangId}
                if ($mainlangCulture) {
                    $cltr.ClientCulture = $mainlangCulture.Name
                }
            }

            [string]$officeLangPath = join-path  $path "Common\LanguageResources\InstalledUIs"
            $langValues = $regProv.EnumValues($HKLM, $officeLangPath);
            if ($langValues) {
               foreach ($langValue in $langValues) {
                  $langCulture = [globalization.cultureinfo]::GetCultures("allCultures") | where {$_.LCID -eq $langValue}
               } 
            }

            if ($virtualInstallPath) {

            } else {
              $clickToRunPath = join-path $regKey "ClickToRun\Configuration"
              $virtualInstallPath = $regProv.GetStringValue($HKLM, $clickToRunPath, "InstallationPath").sValue
            }

            if ($virtualInstallPath) {
               if (!$ClickToRunPathList.Contains($virtualInstallPath.ToUpper())) {
                  $AddItem = $ClickToRunPathList.Add($virtualInstallPath.ToUpper())
               }

               $cltr.InstallPath = $virtualInstallPath
               $cltr.StreamingFinished = $regProv.GetStringValue($HKLM, $clickToRunPath, "StreamingFinished").sValue
               $cltr.UpdatesEnabled = $regProv.GetStringValue($HKLM, $clickToRunPath, "UpdatesEnabled").sValue
               $cltr.UpdateUrl = $regProv.GetStringValue($HKLM, $clickToRunPath, "UpdateUrl").sValue
               $cltr.Platform = $regProv.GetStringValue($HKLM, $clickToRunPath, "Platform").sValue
               $cltr.ClientCulture = $regProv.GetStringValue($HKLM, $clickToRunPath, "ClientCulture").sValue
               $ClickToRunList += $cltr
            }

            $packageItems = $regProv.EnumKey($HKLM, $packagePath)
            $officeItems = $regProv.EnumKey($HKLM, $path)

            foreach ($itemKey in $officeItems.sNames) {
              $itemPath = join-path $path $itemKey
              $installRootPath = join-path $itemPath "InstallRoot"

              $filePath = $regProv.GetStringValue($HKLM, $installRootPath, "Path").sValue
              if (!$PathList.Contains($filePath)) {
                  $AddItem = $PathList.Add($filePath)
              }
            }

            foreach ($packageGuid in $packageItems.sNames) {
              $packageItemPath = join-path $packagePath $packageGuid
              $packageName = $regProv.GetStringValue($HKLM, $packageItemPath, "").sValue
            
              if (!$PackageList.Contains($packageName)) {
                if ($packageName) {
                   $AddItem = $PackageList.Add($packageName.Replace(' ', '').ToLower())
                }
              }
            }

          }
       }
    }

    foreach ($regKey in $installKeys) {
        $keyList = new-object System.Collections.ArrayList
        $keys = $regProv.EnumKey($HKLM, $regKey)

        foreach ($key in $keys.sNames) {
           $path = join-path $regKey $key
           $installPath = $regProv.GetStringValue($HKLM, $path, "InstallLocation").sValue
           if (!($installPath)) { continue }
           if ($installPath.Length -eq 0) { continue }

           $buildType = "64-Bit"
           if ($osArchitecture -eq "32-bit") {
              $buildType = "32-Bit"
           }

           if ($regKey.ToUpper().Contains("Wow6432Node".ToUpper())) {
              $buildType = "32-Bit"
           }

           if ($key -match "{.{8}-.{4}-.{4}-1000-0000000FF1CE}") {
              $buildType = "64-Bit" 
           }

           if ($key -match "{.{8}-.{4}-.{4}-0000-0000000FF1CE}") {
              $buildType = "32-Bit" 
           }

           if ($modifyPath) {
               if ($modifyPath.ToLower().Contains("platform=x86")) {
                  $buildType = "32-Bit"
               }

               if ($modifyPath.ToLower().Contains("platform=x64")) {
                  $buildType = "64-Bit"
               }
           }

           $primaryOfficeProduct = $false
           $officeProduct = $false
           foreach ($officeInstallPath in $PathList) {
             if ($officeInstallPath) {
                try{
                $installReg = "^" + $installPath.Replace('\', '\\')
                $installReg = $installReg.Replace('(', '\(')
                $installReg = $installReg.Replace(')', '\)')
                if ($officeInstallPath -match $installReg) { $officeProduct = $true }
                } catch {}
             }
           }

           if (!$officeProduct) { continue };
           
           $name = $regProv.GetStringValue($HKLM, $path, "DisplayName").sValue          

           $primaryOfficeProduct = $true
           if ($ConfigItemList.Contains($key.ToUpper()) -and $name.ToUpper().Contains("MICROSOFT OFFICE")) {
              foreach($exception in $MSexceptionList){
                 if($name.ToLower() -match $exception.ToLower()){
                    $primaryOfficeProduct = $false
                 }
              }
           } else {
              $primaryOfficeProduct = $false
           }

           $clickToRunComponent = $regProv.GetDWORDValue($HKLM, $path, "ClickToRunComponent").uValue
           $uninstallString = $regProv.GetStringValue($HKLM, $path, "UninstallString").sValue
           if (!($clickToRunComponent)) {
              if ($uninstallString) {
                 if ($uninstallString.Contains("OfficeClickToRun")) {
                     $clickToRunComponent = $true
                 }
              }
           }

           $modifyPath = $regProv.GetStringValue($HKLM, $path, "ModifyPath").sValue 
           $version = $regProv.GetStringValue($HKLM, $path, "DisplayVersion").sValue

           $cltrUpdatedEnabled = $NULL
           $cltrUpdateUrl = $NULL
           $clientCulture = $NULL;

           [string]$clickToRun = $false

           if ($clickToRunComponent) {
               $clickToRun = $true
               if ($name.ToUpper().Contains("MICROSOFT OFFICE")) {
                  $primaryOfficeProduct = $true
               }

               foreach ($cltr in $ClickToRunList) {
                 if ($cltr.InstallPath) {
                   if ($cltr.InstallPath.ToUpper() -eq $installPath.ToUpper()) {
                       $cltrUpdatedEnabled = $cltr.UpdatesEnabled
                       $cltrUpdateUrl = $cltr.UpdateUrl
                       if ($cltr.Platform -eq 'x64') {
                           $buildType = "64-Bit" 
                       }
                       if ($cltr.Platform -eq 'x86') {
                           $buildType = "32-Bit" 
                       }
                       $clientCulture = $cltr.ClientCulture
                   }
                 }
               }
           }
           
           if (!$primaryOfficeProduct) {
              if (!$ShowAllInstalledProducts) {
                  continue
              }
           }

           $object = New-Object PSObject -Property @{DisplayName = $name; Version = $version; InstallPath = $installPath; ClickToRun = $clickToRun; 
                     Bitness=$buildType; ComputerName=$computer; ClickToRunUpdatesEnabled=$cltrUpdatedEnabled; ClickToRunUpdateUrl=$cltrUpdateUrl;
                     ClientCulture=$clientCulture }
           $object | Add-Member MemberSet PSStandardMembers $PSStandardMembers
           $results += $object

        }
    }
  }

  $results = Get-Unique -InputObject $results 

  return $results;
}

}

$officetemp = Get-OfficeVersion | select -ExpandProperty version
$officeversion = $officetemp.Substring(0,4)


$officeuserhive = Get-ChildItem -Path "Registry::HKCU\Software\Policies\Microsoft\Office\$officeversion\" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name 
$officelocalhive = Get-ChildItem -Path "Registry::HKLM\Software\Policies\Microsoft\Office\$officeversion\" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name 

if ($officeuserhive -eq $null -and $officelocalhive -eq $null)
{
write-host "No Microsoft Office group policies were detected, this script will now exit" -ForegroundColor Yellow
pause
break
}

write-host "`r`n####################### ATTACK SURFACE REDUCTION #######################`r`n"

write-host "`r`n####################### MACROS #######################`r`n"

Get-ChildItem -Path "Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Office\$officeversion\" | Select-Object -ExpandProperty Name | ForEach-Object{
$officename = ($_).Split('\')[6]
if ($officename.Contains("outlook") -or $officename.Contains("common") -or $officename.Contains("firstrun") -or $officename.Contains("onenote") -or $officename.Contains("Registration"))
{
    #donothing
}
else
{
    $appsetting = Get-ItemProperty -Path Registry::$_\Security -ErrorAction SilentlyContinue| Select-Object -ExpandProperty VBAWarnings -ErrorAction SilentlyContinue

If ($appsetting -eq $null)
{
    write-host "Macro settings have not been configured in $officename"
}
    elseif ($appsetting -eq "4")
    {
        write-host "Macros are disabled in $officename" -ForegroundColor Green
    }
    elseif ($appsetting -eq "1")
      {
            Write-Host "Macros are not disabled in $officename, set to Enable all Macros ($appsetting)" -ForegroundColor Red
      }
      elseif ($appsetting -eq "2")
      {
            Write-Host "Macros are not disabled in $officename, Disable all Macros with notification ($appsetting)" -ForegroundColor Red
      }
      elseif ($appsetting -eq "3")
      {
            Write-Host "Macros are not disabled in $officename, Disable all Macros except those digitally signed ($appsetting)" -ForegroundColor Red
      }
      else 
      {
            Write-Host "Macros are not disabled in $officename, value is unknown and set to $appsetting" -ForegroundColor Red
      }

$apptoscan = $_

$tldisable = Get-ItemProperty -Path "Registry::$apptoscan\Security\Trusted Locations" -Name alllocationsdisabled -ErrorAction SilentlyContinue|Select-Object -ExpandProperty alllocationsdisabled

if ($tldisable -eq '1')
{
write-host "Trusted Locations for $officename are disabled" -ForegroundColor Green
}
else
{

write-host "Trusted Locations For $officename are enabled" -ForegroundColor Yellow
foreach($_ in 1..50)
{
    $i++
    $trustedlocation = Get-ItemProperty -Path "Registry::$apptoscan\Security\Trusted Locations\location$_" -Name path -ErrorAction SilentlyContinue|Select-Object -ExpandProperty path
    If ($trustedlocation -ne $null)
    {
        write-host "$trustedlocation" -ForegroundColor Magenta
    }
}
}
}
}


#Outlook has unique macro settings so we check them separately here
$macrooutlook = Get-ItemProperty -Path Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Office\$officeversion\outlook\Security -ErrorAction SilentlyContinue| Select-Object -ExpandProperty level -ErrorAction SilentlyContinue

If ($macrooutlook -eq $null)
{
write-host "Macro settings have not been configured in Microsoft Outlook"
}
elseif ($macrooutlook -eq "4"){
    write-host "Macros are disabled in Microsoft Outlook" -ForegroundColor Green
    }
    elseif ($macrooutlook -eq"1")
      {Write-Host "Macros are not disabled in Microsoft Outlook, set to Enable all Macros" -ForegroundColor Red}
      elseif ($macrooutlook -eq"2")
      {Write-Host "Macros are not disabled in Microsoft Outlook, set to Disable all Macros with notification" -ForegroundColor Red}
      elseif ($macrooutlook -eq"3")
      {Write-Host "Macros are not disabled in Microsoft Outlook, set to Disable all Macros except those digitally signed" -ForegroundColor Red}
      else {Write-host "Macros are not disabled in Microsoft Outlook, value is unknown and set to $macrooutlook" -ForegroundColor Red}

#MS Outlook

$tldisable = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Office\$officeversion\Security\Trusted Locations" -Name alllocationsdisabled -ErrorAction SilentlyContinue|Select-Object -ExpandProperty alllocationsdisabled

if ($tldisable -eq '1')
{
write-host "Trusted Locations for Outlook are disabled" -ForegroundColor Green
}
else
{

write-host "Trusted Locations For Outlook are enabled" -ForegroundColor Yellow
foreach($_ in 1..50)
{
    $i++
    $trustedlocation = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Office\$officeversion\Outlook\Security\Trusted Locations\location$_" -Name path -ErrorAction SilentlyContinue|Select-Object -ExpandProperty path
    If ($trustedlocation -ne $null)
    {
        write-host "$trustedlocation" -ForegroundColor Magenta
    }
}
}

write-host "`r`n####################### PATCHING #######################`r`n"

write-host "`r`n####################### ACTIVE-X #######################`r`n"

write-host "`r`n####################### ADD-INS #######################`r`n"

write-host "`r`n####################### EXTENSION HARDENING #######################`r`n"

write-host "`r`n####################### FILE TYPE BLOCKING #######################`r`n"

write-host "`r`n####################### HIDDEN MARKUP #######################`r`n"  -ForegroundColor Cyan

#Powerpoint - Make Hidden Markup Visible

$hiddenmarkupppt = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\powerpoint\options" -Name markupopensave -ErrorAction SilentlyContinue|Select-Object -ExpandProperty markupopensave

if ($hiddenmarkupppt -eq $null)
{
write-host "Make hidden markup visible for Powerpoint is not configured"
}

else-if ($hiddenmarkupppt -eq '1')
{
write-host "Make hidden markup visible for Powerpoint is enabled" -ForegroundColor Green
}
else
{
write-host "Make hidden markup visible for Powerpoint is disabled" -ForegroundColor Red
}


#Word - Make Hidden Markup Visible

$hiddenmarkupword = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\word\options" -Name showmarkupopensave -ErrorAction SilentlyContinue|Select-Object -ExpandProperty showmarkupopensave

if ($hiddenmarkupword -eq $null)
{
write-host "Make hidden markup visible for Word is not configured"
}

else-if ($hiddenmarkupword -eq '1')
{
write-host "Make hidden markup visible for Word is enabled" -ForegroundColor Green
}
else
{
write-host "Make hidden markup visible for Word is disabled" -ForegroundColor Red
}


write-host "`r`n####################### OFFICE FILE VALIDATION #######################`r`n"  -ForegroundColor Cyan

#Turn off error reporting for files that fail file validation

$disablereporting = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\common\security\filevalidation" -Name disablereporting -ErrorAction SilentlyContinue|Select-Object -ExpandProperty disablereporting

if ($disablereporting -eq $null)
{
write-host "Turn off error reporting for files that fail file validation is not configured"
}

else-if ($disablereporting -eq '1')
{
write-host "Turn off error reporting for files that fail file validation is enabled" -ForegroundColor Green
}
else
{
write-host "Turn off error reporting for files that fail file validation is disabled" -ForegroundColor Red
}


#Turn off file validation - excel

$filevalidationexcel = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\excel\security\filevalidation" -Name enableonload -ErrorAction SilentlyContinue|Select-Object -ExpandProperty enableonload

if ($filevalidationexcel -eq $null)
{
write-host "Turn off file validation is not configured in Excel"
}

else-if ($filevalidationexcel -eq '1')
{
write-host "Turn off file validation is disabled in Excel" -ForegroundColor Green
}
else
{
write-host "Turn off file validation is enabled in Excel" -ForegroundColor Red
}


#Turn off file validation - Powerpoint

$filevalidationppt = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\powerpoint\security\filevalidation" -Name enableonload -ErrorAction SilentlyContinue|Select-Object -ExpandProperty enableonload

if ($filevalidationppt -eq $null)
{
write-host "Turn off file validation is not configured in Powepoint"
}

else-if ($filevalidationppt -eq '1')
{
write-host "Turn off file validation is disabled in Powepoint" -ForegroundColor Green
}
else
{
write-host "Turn off file validation is enabled in Powepoint" -ForegroundColor Red
}

#Turn off file validation - Word

$filevalidationword = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\word\security\filevalidation" -Name enableonload -ErrorAction SilentlyContinue|Select-Object -ExpandProperty enableonload

if ($filevalidationword -eq $null)
{
write-host "Turn off file validation is not configured in Word"
}

else-if ($filevalidationppt -eq '1')
{
write-host "Turn off file validation is disabled in Word" -ForegroundColor Green
}
else
{
write-host "Turn off file validation is enabled in Word" -ForegroundColor Red
}


write-host "`r`n####################### PROTECTED VIEW #######################`r`n"  -ForegroundColor Cyan

#Do not open files from the Internet zone in Protected View - Excel

$disableifexcel = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\excel\security\protectedview" -Name disableinternetfilesinpv -ErrorAction SilentlyContinue|Select-Object -ExpandProperty disableinternetfilesinpv

if ($disableifexcel -eq $null)
{
write-host "Do not open files from the Internet zone in Protected View is not configured in Excel"
}

else-if ($disableifexcel -eq '0')
{
write-host "Do not open files from the Internet zone in Protected View is disabled in Excel" -ForegroundColor Green
}
else-if ($disableifexcel -eq '1')
{
write-host "Do not open files from the Internet zone in Protected View is enabled in Excel" -ForegroundColor Red
}
else
{
write-host "Do not open files from the Internet zone in Protected View is set to an unknown configuration in Excel" -ForegroundColor Red
}



#Do not open files from the Internet zone in Protected View - Powerpoint

$disableifpowerpoint = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\powerpoint\security\protectedview" -Name disableinternetfilesinpv -ErrorAction SilentlyContinue|Select-Object -ExpandProperty disableinternetfilesinpv

if ($disableifpowerpoint -eq $null)
{
write-host "Do not open files from the Internet zone in Protected View is not configured in powerpoint"
}

else-if ($disableifpowerpoint -eq '0')
{
write-host "Do not open files from the Internet zone in Protected View is disabled in powerpoint" -ForegroundColor Green
}
else-if ($disableifpowerpoint -eq '1')
{
write-host "Do not open files from the Internet zone in Protected View is enabled in powerpoint" -ForegroundColor Red
}
else
{
write-host "Do not open files from the Internet zone in Protected View is set to an unknown configuration in powerpoint" -ForegroundColor Red
}


#Do not open files from the Internet zone in Protected View - word

$disableifword = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\word\security\protectedview" -Name disableinternetfilesinpv -ErrorAction SilentlyContinue|Select-Object -ExpandProperty disableinternetfilesinpv

if ($disableifword -eq $null)
{
write-host "Do not open files from the Internet zone in Protected View is not configured in word"
}

else-if ($disableifword -eq '0')
{
write-host "Do not open files from the Internet zone in Protected View is disabled in word" -ForegroundColor Green
}
else-if ($disableifword -eq '1')
{
write-host "Do not open files from the Internet zone in Protected View is enabled in word" -ForegroundColor Red
}
else
{
write-host "Do not open files from the Internet zone in Protected View is set to an unknown configuration in word" -ForegroundColor Red
}


#Do not open files in unsafe locations in Protected View - Excel

$disableifulexcel = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\excel\security\protectedview" -Name disableunsafelocationsinpv -ErrorAction SilentlyContinue|Select-Object -ExpandProperty disableunsafelocationsinpv

if ($disableifulexcel -eq $null)
{
write-host "Do not open files in unsafe locations in Protected View is not configured in Excel"
}

else-if ($disableifulexcel -eq '0')
{
write-host "Do not open files in unsafe locations in Protected View is disabled in Excel" -ForegroundColor Green
}
else-if ($disableifulexcel -eq '1')
{
write-host "Do not open files in unsafe locations in Protected View is enabled in Excel" -ForegroundColor Red
}
else
{
write-host "Do not open files in unsafe locations in Protected View is set to an unknown configuration in Excel" -ForegroundColor Red
}



#Do not open files in unsafe locations in Protected View - Powerpoint

$disableifulpowerpoint = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\powerpoint\security\protectedview" -Name disableunsafelocationsinpv -ErrorAction SilentlyContinue|Select-Object -ExpandProperty disableunsafelocationsinpv

if ($disableifulpowerpoint -eq $null)
{
write-host "Do not open files in unsafe locations in Protected View is not configured in powerpoint"
}

else-if ($disableifulpowerpoint -eq '0')
{
write-host "Do not open files in unsafe locations in Protected View is disabled in powerpoint" -ForegroundColor Green
}
else-if ($disableifulpowerpoint -eq '1')
{
write-host "Do not open files in unsafe locations in Protected View is enabled in powerpoint" -ForegroundColor Red
}
else
{
write-host "Do not open files in unsafe locations in Protected View is set to an unknown configuration in powerpoint" -ForegroundColor Red
}


#Do not open files in unsafe locations in Protected View - word

$disableifulword = Get-ItemProperty -Path "Registry::HKEY_CURRENT_USER\software\policies\microsoft\office\$officeversion\word\security\protectedview" -Name disableunsafelocationsinpv -ErrorAction SilentlyContinue|Select-Object -ExpandProperty disableunsafelocationsinpv

if ($disableifulword -eq $null)
{
write-host "Do not open files in unsafe locations in Protected View is not configured in word"
}

else-if ($disableifulword -eq '0')
{
write-host "Do not open files in unsafe locations in Protected View is disabled in word" -ForegroundColor Green
}
else-if ($disableifulword -eq '1')
{
write-host "Do not open files in unsafe locations in Protected View is enabled in word" -ForegroundColor Red
}
else
{
write-host "Do not open files in unsafe locations in Protected View is set to an unknown configuration in word" -ForegroundColor Red
}


write-host "`r`n####################### TRUSTED DOCUMENTS #######################`r`n"  -ForegroundColor Cyan

write-host "`r`n####################### REPORTING INFORMATION #######################`r`n" -ForegroundColor Cyan
