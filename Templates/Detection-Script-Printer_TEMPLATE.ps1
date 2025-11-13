# Detection-Script-Printer_TEMPLATE.ps1

# Try modern method
if(get-command -name Get-Printer -erroraction silentlyContinue){

    $Result = get-printer | where name -eq $PrinterName

} else {

    # Try old school method
    $Result = Get-CIMInstance -classname Win32_Printer -Filter "name=$printername" -erroraction silentlyContinue


}


