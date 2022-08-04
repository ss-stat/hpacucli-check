<#
		.SYNOPSIS
		    Check array controller, arrays, physical and logical drives with hpacucli utility
			
        .DESCRIPTION
		    Check the status of array controller, arrays, physical and logical drives on a HP Server
		    with hpacucli (HP Array Configuration Utility Client) installed
		    and send an email with errors.
								
        .EXAMPLE
            hpacucli-check-win.ps1

        .NOTES
			Author	: Shambo
			Created : 01/08/2022
			
		.LINK
			https://github.com/ss-stat/hpacucli-check
#>

$HPACUCLI="c:\zabbix\Bin\hpacucli.exe"
$IGNORE_Battery_ERROR=$true # Ignore failed cache battery errors
$MAIL=""

$ERROR_FOUND=$false
$EmailMessage = ""

$HOSTNAME = Invoke-Expression -Command 'hostname'

#$pass = ConvertTo-SecureString “” -AsPlainText -Force
#$EmailCreds = New-Object System.Management.Automation.PSCredential(“” , $pass)

<#
$MailServerParams = @{
    SmtpServer = "smtp.gmail.com"
    From = ""
    Port = 587
    UseSsl = $true
    Credential =  $EmailCreds
}
#>

# Simple option for mail relay without auth 
$MailServerParams = @{
    SmtpServer = ""
    From = ""
}


$Result = & $HPACUCLI ctrl all show | Select-String -SimpleMatch "Array"

############################################################################
# We do not consider the situation of a RAID controller absence (in slot).
# And we only have one RAID controller, so we don't need to iterate over them.

$Result[0] -match '.+Slot ([0-9]).*' | Out-Null
$slot=$Matches[1]


## Controller (Slot) Status ##

$Result = & $HPACUCLI ctrl slot=$slot show status | Select-String -SimpleMatch "Status"

foreach ($line in $Result) {
    
    $msg = ""
    
    if ( $IGNORE_Battery_ERROR -And ( $line -match 'Cache' -Or $line -match 'Battery' )){
    break
    }
    
    if ($line -match 'OK') {
    $msg="[OK] RAID controller slot $slot -> $line"
    } 
    else {
    $ERROR_FOUND=$true
    $msg="[ERROR] RAID controller slot $slot -> $line"
    }
    Write-Host $msg
    $EmailMessage = $EmailMessage, $msg -join '<br />'
}

Write-Host ""
$EmailMessage = $EmailMessage, "" -join '<br />'

## Arrays Status ##

$Arrays = & $HPACUCLI ctrl slot=$slot array all show | Select-String -CaseSensitive 'array'

#-> Arrays
foreach ($line in $Arrays) {
    
    
    $line -match '.*array ([A-z]).*' | Out-Null
    $array = $Matches[1] 

    # Array Status
	$ArrayStatus = & $HPACUCLI ctrl slot=$slot array $array show status | Select-String -CaseSensitive 'array'
    
  #  foreach ($array_line in $ArrayStatus) {

        $msg = ""
        if ($ArrayStatus -match 'OK') {
        $msg="[OK] RAID controller slot $slot array $array -> $ArrayStatus"
        } 
        else {
        $ERROR_FOUND=$true
        $msg="[ERROR] RAID controller slot $slot array $array -> $ArrayStatus"
        }
        Write-Host $msg
         $EmailMessage = $EmailMessage, $msg -join '<br />'

        # Physical Drives (Disks) Status
        $ArrayHDDs = & $HPACUCLI ctrl slot=$slot array $array physicaldrive all show | Select-String -CaseSensitive 'physicaldrive'

        #-> HDDs
        foreach ($hdd_line in $ArrayHDDs) {
    
            $hdd_line -match '.*physicaldrive (.*\:.*\:.*) \(' | Out-Null
            $physicaldrive=$Matches[1]

            # Particular Physical Disk Status
            $HDD_Status = & $HPACUCLI ctrl slot=$slot physicaldrive $physicaldrive show | Select-String -CaseSensitive 'Status: OK'
   
            $msg = ""
            if ($HDD_Status -match 'OK') {
                $msg="_[OK] RAID controller slot #$slot physicaldrive $physicaldrive -> $hdd_line"
            } 
            else {
                $ERROR_FOUND=$true
                $msg="_[ERROR] RAID controller slot #$slot physicaldrive $physicaldrive -> $hdd_line"
            }
            Write-Host $msg
             $EmailMessage = $EmailMessage, $msg -join '<br />'
        }#<- HDDs


        ## Logical Drives Status
        $ArrayLogicalDrives = & $HPACUCLI ctrl slot=$slot array $array logicaldrive all show  | Select-String -CaseSensitive 'logicaldrive'
        #-> LDs
        foreach ($ld_line in $ArrayLogicalDrives) {

        
            $ld_line -match '.*logicaldrive ([0-9]).*' | Out-Null
            $logicaldrive=$Matches[1]
        
            # Particular Logical Drive Status
            $LD_Status = & $HPACUCLI ctrl slot=$slot array $array logicaldrive $logicaldrive show
        
             $msg = ""
            if ($LD_Status -match 'OK') {
                $msg="__[OK] RAID controller slot #$slot array $array drive #$logicaldrive -> $ld_line"
            } 
            else {
                $ERROR_FOUND=$true
                $msg="__[ERROR] RAID controller slot #$slot array $array drive #$logicaldrive -> $ld_line"
            }
            Write-Host $msg
             $EmailMessage = $EmailMessage, $msg -join '<br />'
        } #<- LDs


Write-Host ""
$EmailMessage = $EmailMessage, "" -join '<br />'
} #<- Arrays

#Write-Host $EmailMessage

if ($ERROR_FOUND) {

$msg = "<strong>(!) For more info use [$HPACUCLI ctrl all show config detail] on $HOSTNAME (!)</strong>"
$EmailMessage = $EmailMessage, $msg -join '<br />'

#$EmailBody = $EmailMessage # | ConvertTo-Html | out-string


$MessageParams = @{
    'To' = $MAIL+", "+$HL_MAIL
    'Subject' = "RAID Report : [ERRORS] detected on $HOSTNAME ["+(Get-Date).ToString('dd-MM-yyyy HH:mm')+"]" 
    'Body' = $EmailMessage
}

Try {
    Send-MailMessage @MailServerParams @MessageParams -BodyAsHtml -ErrorAction Stop;
} 
Catch { 
    Write-Host $sendErr
    Write-Host "Email sending ERROR"
 }
 } 

 