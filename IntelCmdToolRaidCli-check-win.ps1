 <#
		.SYNOPSIS
		    Check array controller, arrays, physical and logical drives with CmdTool2 utility
			
        .DESCRIPTION
		    Check the status of array controller, arrays, physical and logical drives on a Intel Server
		    with CmdTool2 (Intel(R) RAID Command Line Utilities Version 2) installed
		    and send an email with errors.
								
        .EXAMPLE
            IntelCmdToolRaidCli-check-win.ps1

        .NOTES
			Author	: Shambo
			Created : 01/08/2022
			
		.LINK
			https://github.com/ss-stat/hpacucli-check
#>

$CmdTool2 = "C:/raid/CmdTool2-64.exe"
$MAIL="***@gmail.com"
$HL_MAIL="***"
$HOSTNAME = Invoke-Expression -Command 'hostname'

$MailServerParams = @{
    SmtpServer = "192.168.2.1" # Mail relay
    From = "SRV3  <srv3@***>"
}

$SumResult=@(
    "================"
    " Error counters "
    "================")
    
    
$ERROR_FOUND=$false


## Adapter Error Counters ##

$Result = & $CmdTool2 -AdpAllInfo -a0 | Select-String -pattern "(Virtual Drives)|(Physical Devices)|(Degraded)|(Offline.*: \d)|(Critical)|(Failed.*: \d)|(Errors.*: \d)"

foreach ($line in $Result) {

if ( $line -Match "(Virtual Drives)|(Physical Devices)") {

    $SumResult+="$line"
}
else {
    
    $mark="[OK]"
    if  ( $line -NotMatch "0" ) {
        $ERROR_FOUND=$true 
        $mark="[ERROR]"
    } 

    $SumResult+=$mark+$line
}
} # <<Adapter Error Counters

$Head=@(""
"================"
" Summary states "
"================")
$SumResult+=$Head

## Summary info ##

$Result = & $CmdTool2 -ShowSummary -a0 #| Select-String -pattern "^\w{1}"

foreach ($line in $Result) {

if ( $line -NotMatch ":" -and $line -NotMatch "^\s*$" ) {
    $SumResult+=""
    $SumResult+="$line>"
}
elseif ( $line -Match "(Connector)|(Vendor)|(Virtual drive)|(Capacity)|(Size)" ) {
    
    $SumResult+=$line
}

elseif ( $line -Match "(Status)|(State)" ) {
    
    $mark="[OK]"
    if  ( $line -NotMatch "(Optimal)|(Healthy)|(OK)|(Online)|(Active)" ) {
        $ERROR_FOUND=$true 
        $mark="[ERROR]"
    } 

    $SumResult+=$mark+$line
}

} # <<$Summary
    

$Head=@(""
"==========================="
" Detailed HDD errors check "
"===========================")
$SumResult+=$Head

## HDD Errors check ##

$Result = & $CmdTool2 -PDList -a0 | Select-String "(Slot)|(WWN)|(Error)|(Failure)|(Firmware state)|(alert)"

$HDDError=$false
$HDDInfo=@()

foreach ($line in $Result) {


if ( $line -Match "Slot") {
    
    If ( $HDDInfo.Count -ne 0 ) {
        if ( $HDDError) { # Prev HDD has errors
            
            $SumResult+="(-) This HDD has some [ERRORS] (!)"
            $SumResult+= $HDDInfo}
        else {
            $SumResult+="(+) This HDD is [OK]"
        }
        $SumResult+=""
    }
    
    $SumResult+=$line # Slot
    $HDDInfo=@()
    $HDDError=$false
    
}
elseif ( $line -Match "(Error)|(Failure)|(Firmware state)|(alert)" ) {
    
    $mark="[OK] "
    if  ( $line -NotMatch "(Online)|(No)|(0)" ) {
        $ERROR_FOUND=$true
        $HDDError=$true 
        $mark="[ERROR] "
    } 

    $HDDInfo+=$mark+$line
}

} # <<HDD Errors

# Last HDD info is out of the loop
if ( $HDDError) { # Prev HDD has errors
            
    $SumResult+="(-) This HDD has some [ERRORS] (!)"
    $SumResult+= $HDDInfo}
else {
    $SumResult+="(+) This HDD is [OK]"
}


### Email results ###

if ( $ERROR_FOUND ) {

    $SumResult+=""
    $msg = "(!) FOR MORE INFO USE [$CmdTool2 -CfgDsply -a0] on $HOSTNAME (!)"
    $SumResult+=$msg

    $EmailBody = $SumResult | out-string # | ConvertTo-Html

    $MessageParams = @{
        'To' = @($MAIL, $HL_MAIL)
        'Subject' = "RAID Report : [ERRORS] detected on $HOSTNAME ["+(Get-Date).ToString('dd-MM-yyyy HH:mm')+"]" 
        'Body' = $EmailBody
    }
}
else {
    $MessageParams = @{
        'To' = $HL_MAIL
        'Subject' = "RAID Report : [OK] on $HOSTNAME ["+(Get-Date).ToString('dd-MM-yyyy HH:mm')+"]" 
        'Body' = "RAID Report : Everything is OK"
    }
}

Try {
    Send-MailMessage @MailServerParams @MessageParams -ErrorAction Stop; #-BodyAsHtml
    #Invoke-RestMethod https://hc-ping.com/***
} 
Catch { 
    Write-Host $sendErr
    Write-Host "Email sending ERROR"
}    