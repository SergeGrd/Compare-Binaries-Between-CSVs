<# Script name: Compare-Bin-From-CSV.ps1
 last edit by: sergeg 2020-12-10
::
Copyright ^(C^) Microsoft. All rights reserved.
THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE 
USE OR OTHER DEALINGS IN THE SOFTWARE.
::
Purpose: Powershell Script to Compare CSV containing binaries 
Help:  get-help .\Compare-Bin-From-CSV.ps1 -detailed
#> 

<#
.SYNOPSIS
The script compares the binaries exported to CSV by SDP Reports

.DESCRIPTION
The script compares the binaries exported to CSV by SDP Reports
Usage:
 .\Compare-Bin-From-CSV.ps1 [Left|Right|OutputPath]

If you get an error that running scripts is disabled, run 
	Set-ExecutionPolicy Bypass -force -Scope Process
and verify with 'Get-ExecutionPolicy -List' that no ExecutionPolicy with higher precedence is blocking execution of this script.

The output will be such as this
Module                  Company      Description            ServerA   ServerB    Match
<Path>\ContosoDrv.sys   Contoso      Driver from Contoso    (1.3)     (1.5)      different
<Path>\ContosoDrv2.sys  Contoso      Driver from Contoso    (2.6)     (2.6)      identical
<Path>\FabrikamDrv.sys  Fabrikam     Driver from Fabrikam   (0.7)     Not found  different

When displayed in a gridview it is easy to filter on the 'different' keyword to have all the differences displayed

.PARAMETER Left
 Manfdatory : This switch gives the path to the first CSV file
 
.PARAMETER Right
 Manfdatory : This switch gives the path to the second CSV file

.PARAMETER OutputPath
 This switch gives the folder where to store the BinCompare.csv file.
 If not set, the file will be generated in the current folder

.EXAMPLE
 .\Compare-Bin-From-CSV.ps1 -Left .\Server-A-binaries.csv -Right .\Server-B-binaries.csv
 Create a table containing the binaries in each csv file and add a column telling if they're different or identical
 It will create a .\BinCompare.csv file in the current folder
  
.EXAMPLE
 .\Compare-Bin-From-CSV.ps1 -Left .\Server-A-binaries.csv -Right .\Server-B-binaries.csv -OutputPath c:\temp
 Create a table containing the binaries in each csv file and add a column telling if they're different or identical
 It will save the result in the c:\temp\BinCompare.csv file 

#>

param(
    [Parameter(Mandatory=$true)][string]$Left,
    [Parameter(Mandatory=$true)][string]$Right,
    [string]$OutputPath
)

# ==================================================================================================================== #
<#
    The CSV files generated by our reports contain a header that make them un importable using import-csv

    Something like:
        sep= -a-separator-
        CHECKSYM,(-a-version-)
        Created:,"-a-Date-,a-time-"
        Computer:,-a-computer-name-
        [-a-title-]

    We suppose the separator will always be a coma. If it changes, we'll get the data from the file

    Part 1:
        The first part consists in removing this header
        It's impossible to remove data from a file
        So we create new one without the header

    Part 2:
        We import the two files using Import-CSV and we name them by Left & Right
        We create a list of the usefull data in each of them : Essentially Binary path, company name, description, version

    Part 3:
        We create a new table that will contain the binaries collected in the two list (Left & Right)
        First the ones in common
        Then the ones that are present in only one of the files
    
    We finally export the last table as a CSV for further usage and display it as a gridview
    In a Gridview, it is easy to filter on keywords such as 'different'

#>
# ========================================================================================= Check arguments ========== #

if (!(Test-Path -Path $Left)){
    write-host "path "$Left" not found"
    break
}
if (!(Test-Path -Path $Right )){
    write-host "path "$Right" not found"
    break
}

# ==================================================== Generate the CSV files in a way they can be imported ========== #

# -------------- Left File -------------- #

# ----- Generate the Left File Name
$CNLine = (Get-Content -Path $Left -First 10 | Select-String -Pattern 'Computer')[0]
$LeftComputerName = ([string]$CNLine).split(",")[1]
$DirectoryName = (Get-ItemProperty -Path $Left).DirectoryName
$FileName = (Get-ItemProperty -Path $Left).Name
$LeftFileName = $DirectoryName+"\Left_"+$LeftComputerName+"_"+$FileName
if (Test-Path -Path $LeftFileName){
    Remove-Item -Path $LeftFileName -Force
}

# ----- Generate the importable Left File
$FileContent = Get-Content -Path $Left  
for ($l = 0 ; $l -lt $FileContent.Count ; $l++){
    if ($FileContent[$l][0] -eq ","){
        $FileContent[$l] | Out-File -FilePath $LeftFileName -Append
    }
}

# -------------- Right File -------------- #

# ----- Generate the Right File Name
$CNLine = (Get-Content -Path $Right -First 10 | Select-String -Pattern 'Computer')[0]
$RightComputerName = ([string]$CNLine).split(",")[1]
$DirectoryName = (Get-ItemProperty -Path $Right).DirectoryName
$FileName = (Get-ItemProperty -Path $Right).Name
$RightFileName = $DirectoryName+"\Right_"+$RightComputerName+"_"+$FileName
if (Test-Path -Path $RightFileName){
    Remove-Item -Path $RightFileName -Force
}

# ----- Generate the importable Right File
$FileContent = Get-Content -Path $Right  
for ($l = 0 ; $l -lt $FileContent.Count ; $l++){
    if ($FileContent[$l][0] -eq ","){
        $FileContent[$l] | Out-File -FilePath $RightFileName -Append
    }
}

# ===================================================================================== Classes definitions ========== #

# -------------- Binaries properties -------------- #
class C_Binary{
    [string]$C_ModulePath
    [string]$C_FileVersion
    [string]$C_CompanyName
    [string]$C_FileDescription
    [bool]$C_Checked
    C_Binary([string]$ModulePath,[string]$FileVersion,[string]$CompanyName,[string]$FileDescription){
        $this.C_ModulePath = $ModulePath
        $this.C_FileVersion = $FileVersion
        $this.C_CompanyName = $CompanyName
        $this.C_FileDescription = $FileDescription
        $this.C_Checked = $false
    }
}

# -------------- Merged binaries -------------- #
class C_Binary_Compared{
    [string]$C_ModulePath
    [string]$C_CompanyName
    [string]$C_FileDescription
    [string]$C_LeftVersion
    [string]$C_RightVersion
    [string]$C_Match
    C_Binary_Compared([string]$ModulePath,[string]$CompanyName,[string]$FileDescription,[string]$LeftVersion,[string]$RightVersion,[string]$Match){
        $this.C_ModulePath = $ModulePath
        $this.C_CompanyName = $CompanyName
        $this.C_FileDescription = $FileDescription
        $this.C_LeftVersion = $LeftVersion
        $this.C_RightVersion = $RightVersion
        $this.C_Match = $Match
    }
}

# =============================================================================== Tables declaration & fill ========== #

$Left_List = @()
$Right_List = @()
$Compared_List = @()

# -------------- Build the two lists for comparison -------------- #

$CSV_Left = Import-Csv -Path $LeftFileName
$CSV_Right = Import-Csv -Path $RightFileName

$CSV_Left | ForEach-Object {
    $Left_List += [C_Binary]::new($_."Module Path", $_."File Version", $_."Company Name", $_."File Description")
}

$CSV_Right | ForEach-Object {
    $Right_List += [C_Binary]::new($_."Module Path", $_."File Version", $_."Company Name", $_."File Description")
}

# ============================================================================================== Comparison ========== #

# -------------- First run -------------- #

$Left_List | ForEach-Object {

    $MP = $_.C_ModulePath
    $CN = $_.C_CompanyName
    $FD = $_.C_FileDescription
    $LeftVer = $_.C_FileVersion
    $_.C_Checked = $true
    $Found = $false
  
    $Right_List | ForEach-Object {
    
        if ($_.C_ModulePath -eq $MP){
            $_.C_Checked = $true
            $Found = $true
            if ($_.C_FileVersion -eq $LeftVer){
                $Compared_List += [C_Binary_Compared]::new($MP,$CN,$FD,$LeftVer,$_.C_FileVersion, "identical")
            }
            else{
                $Compared_List += [C_Binary_Compared]::new($MP,$CN,$FD,$LeftVer,$_.C_FileVersion, "different")
            }
            
        }
    }
    if ($Found -eq $false){
        $Compared_List += [C_Binary_Compared]::new($MP,$CN,$FD,$LeftVer,"Not found", "different")
    }
}

# -------------- Add the binaries that are present in only one of the two lists -------------- #

$Left_List | Where-Object C_Checked -eq $false | ForEach-Object {
    $Compared_List += [C_Binary_Compared]::new($_.C_ModulePath,$_.C_CompanyName,$_.C_FileDescription,$_.C_FileVersion,"Not found","different")
}

$Right_List | Where-Object C_Checked -eq $false | ForEach-Object {
    $Compared_List += [C_Binary_Compared]::new($_.C_ModulePath,$_.C_CompanyName,$_.C_FileDescription,"Not found",$_.C_FileVersion,"different")
}

# ============================================================================= Save and display the result ========== #

if ($OutputPath){
    if (Test-Path -Path $OutputPath -PathType Container){
        $OutputPath = $OutputPath+"\BinCompare.csv"
    }
    else{
        write-host "$OutputPath does not exist. Use the current path of the script"
        $OutputPath = (Split-Path $MyInvocation.MyCommand.Path -Parent)+"\BinCompare.csv"
    }
}
else{
    $OutputPath = (Split-Path $MyInvocation.MyCommand.Path -Parent)+"\BinCompare.csv"
}

Write-Host "Output saved in $OutputPath"

$Compared_List | Select-Object @{E='C_ModulePath'; N='Module'},@{E='C_CompanyName';N='Company'}, @{E='C_FileDescription';N='Description'}, @{E='C_LeftVersion';N=$LeftComputerName}, @{E='C_RightVersion';N=$RightComputerName}, @{E='C_Match';N='Match'} | Export-Csv -Path $OutputPath
$Compared_List | Select-Object @{E='C_ModulePath'; N='Module'},@{E='C_CompanyName';N='Company'}, @{E='C_FileDescription';N='Description'}, @{E='C_LeftVersion';N=$LeftComputerName}, @{E='C_RightVersion';N=$RightComputerName}, @{E='C_Match';N='Match'} | Out-GridView -Title "Comparing $LeftComputerName $RightComputerName"