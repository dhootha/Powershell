<#
    .SYNOPSIS
        Creates an HTML report of a Big-IP LTM virtual servers, pools, and pool members.
       
       	Zachary Loeber
    	
    	THIS CODE IS MADE AVAILABLE AS IS, WITHOUT WARRANTY OF ANY KIND. THE ENTIRE 
    	RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.
    	
    	Version 1.0.1, 01/21/2014
    	
    .DESCRIPTION
    	
        Creates an HTML report of a Big-IP LTM virtual servers, pools, and pool members.

        The following information is shown:
    	
        * Virtual Server Summary
            - Virtual server name
            - Address
            - Port
            - Pool
            - Enable state
            - Availability
        * Virtual Server Details
            - Virtual server name
            - Persistence profile
            - iRules
        * Pools
            - Pool name
            - Active members
            - Enable state
            - Availability
            - Load balance method
        * Pool Members
            - Pool name
            - Address
            - Port
            - Total connections
            - Current connections
            - Bytes in
            - Enable state
            - Availability
    	
    	IMPORTANT NOTE: iControl snappin is (obviously) required: 
                        https://devcentral.f5.com/d/microsoft-powershell-with-icontrol
	
	.PARAMETER ReportFormat
        One of three report formats to use; HTML, Excel, and Custom. The first two are precanned 
        options, the last requires custom code further on in the script.
    
        HTML - This is the default option. Saves the report locally.
        Excel - This can be used to spit out all the report elements to excel, each section in its 
                own workbook.
        Custom - You will need to supply your own mix of parameters later in the code to use this.
	
	.PARAMETER PromptForInput
    	By default global variables are used (which can be found shortly after the parameters section).
        If PromptForInput is used then the device, username, and password to use will be prompted for at the console.
    
	.EXAMPLE
        Generate the HTML report using the predefined global variables.
        .\Get-LTMReport.ps1
	
    .EXAMPLE
        Generate the Excel report, prompt for connection information.
        .\Get-LTMReport.ps1 -PromptForInput -ReportFormat 'Excel'
        
    .EXAMPLE
        Generate the HTML report, prompt for connection information.
        .\Get-LTMReport.ps1 -PromptForInput

    .NOTES
        Author: Zachary Loeber
        
        Version Info:
        1.0.1 - 01/21/2014
              - Swapped out Format-HTMLTable for Format-HTMLTable
        1.0.0 - 01/02/2014
              - Initial release
            
    .LINK 
        http://www.the-little-things.net 
#>
[CmdletBinding()] 
param ( 
    [Parameter()]
    [ValidateSet('HTML','Excel','Custom')]
    [String]
    $ReportFormat='HTML',
    
    [Parameter()]
    [switch]
    $PromptForInput
)

#region Custom Static Variables
# Set these to suit your environment.
$BIGIP_RECURSE = $true # Recursively list subfolders in partitions
$BIGIP_DEVICE = '10.1.1.1'
$BIGIP_USER = 'SomeUser'
$BIGIP_PASS = 'SomePassword'
$BIGIP_CREDs = new-object pscredential $BIGIP_USER,(ConvertTo-SecureString $BIGIP_PASS -AsPlainText -Force)
$Verbosity = ($PSBoundParameters['Verbose'] -eq $true)

if ($PromptForInput)
{
    $BIGIP_DEVICE = Read-Host "Please enter your Big-IP LTM Device IP or hostname:"
    $BIGIP_USER = Read-Host "Please enter your Big-IP LTM username:"
    $BIGIP_PASS = Read-Host -AsSecureString "Please enter your Big-IP LTM password:"
    $BIGIP_CREDs = new-object pscredential $BIGIP_USER,($BIGIP_PASS)
    
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes',''
    $no = New-Object System.Management.Automation.Host.ChoiceDescription '&No',''
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($no,$yes)
    $result = $Host.UI.PromptForChoice('Verbose?','Do you want verbose output?',$choices,0)
    $Verbosity = ($result -ne $true)
}
#endregion Custom Static Variables

#region Global Options and Variables
# Change this to allow for more or less result properties to span horizontally
#  anything equal to or above this threshold will get displayed vertically instead.
#  (NOTE: This only applies to sections set to be dynamic in html reports)
$HorizontalThreshold = 10

$currdir = ''
if ($MyInvocation.MyCommand.Path) {
    $currdir = Split-Path $MyInvocation.MyCommand.Path
} else {
    $currdir = $pwd -replace '^\S+::',''
}
#endregion Global Options and Variables

#region System Report Section Processing Definitions
$BigIPLTMReportPreProcessing =
@'
    Get-BIGIPLTMReportInformation @VerboseDebug `
                               -ReportContainer $ReportContainer `
                               -SortedRpts $SortedReports
'@

$PoolElements_Postprocessing =
@'
    [scriptblock]$scriptblock = {[string]$args[0] -ne [string]$args[1]}
    $temp = Format-HTMLTable $Table                          -Column 'Enabled' -ColumnValue 'ENABLED' -Attr 'class' -AttrValue 'healthy'
    $temp = Format-HTMLTable $temp -Scriptblock $scriptblock -Column 'Enabled' -ColumnValue 'ENABLED' -Attr 'class' -AttrValue 'warn'
    $temp = Format-HTMLTable $temp                           -Column 'Availability' -ColumnValue 'GREEN' -Attr 'class' -AttrValue 'healthy'
    $temp = Format-HTMLTable $temp                           -Column 'Availability' -ColumnValue 'RED' -Attr 'class' -AttrValue 'alert'
            Format-HTMLTable $temp                           -Column 'Availability' -ColumnValue 'BLUE' -Attr 'class' -AttrValue 'warn'
'@
#endregion Report Section Processing Definitions

#region Report Structure Definitions
$BigIPLTMReport = @{
    'Configuration' = @{
        'TOC'               = $true
        'PreProcessing'     = $BigIPLTMReportPreProcessing
        'SkipSectionBreaks' = $false
        'ReportTypes'       = @('FullDocumentation','ExcelExport')
        'Assets'            = @()
        'PostProcessingEnabled' = $true
    }
    'Sections' = @{
        'Break_VirtualServerInformation' = @{
            'Enabled' = $true
            'ShowSectionEvenWithNoData' = $true
            'Order' = 0
            'AllData' = @{}
            'Title' = 'Virtual Server Information'
            'Type' = 'SectionBreak'
            'ReportTypes' = @{
                'ExcelExport' = $false
                'FullDocumentation' = @{
                    'ContainerType' = 'full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' = $true
                }
            }
        }
        'VirtualServerSummary' = @{
            'Enabled' = $true
            'ShowSectionEvenWithNoData' = $true
            'Order' = 1
            'AllData' = @{}
            'Title' = 'Virtual Server Summary'
            'Type' = 'Section'
            'Comment' = $false
            'ReportTypes' = @{
                'ExcelExport' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Name';e={$_.virtualserver}},
                        @{n='Address';e={$_.address}},
                        @{n='Port';e={$_.port}},
                        @{n='Pool';e={$_.pool}},
                        @{n='Enabled';e={$_.enabled}},
                        @{n='Availability';e={$_.availability}},
                        @{n='Persistence Profile';e={[string]$_.persistenceprofile -replace ' ', "`n`r"}},
                        @{n='Fallback Persistence Profile';e={$_.ExchangeServerCount}},
                        @{n='Rules';e={[string]$_.rules -replace ' ', "`n`r"}}
                }
                'FullDocumentation' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Name';e={'<a href="#{0}">{0}</a>' -f $_.virtualserver}},
                        @{n='Address';e={$_.address}},
                        @{n='Port';e={$_.port}},
                        @{n='Pool';e={'<a href="#{0}">{0}</a>' -f $_.pool}},
                        @{n='Enabled';e={$_.enabled}},
                        @{n='Availability';e={$_.availability}}
                }
            }
            'PostProcessing' = $PoolElements_Postprocessing
        }
        'VirtualServerDetails' = @{
            'Enabled' = $true
            'ShowSectionEvenWithNoData' = $true
            'Order' = 2
            'AllData' = @{}
            'Title' = 'Virtual Server Details'
            'Type' = 'Section'
            'Comment' = $false
            'ReportTypes' = @{
                'ExcelExport' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Name';e={$_.virtualserver}},
                        @{n='Address';e={$_.address}},
                        @{n='Port';e={$_.port}},
                        @{n='Pool';e={$_.pool}},
                        @{n='Enabled';e={$_.enabled}},
                        @{n='Availability';e={$_.availability}},
                        @{n='Persistence Profile';e={[string]$_.persistenceprofile -replace ' ', "`n`r"}},
                        @{n='Rules';e={[string]$_.rules -replace ' ', "`n`r"}}
                }
                'FullDocumentation' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Name';e={'<a id="{0}">{0}</a>' -f $_.virtualserver}},
                        @{n='Persistence Profile';e={[string]$_.persistenceprofile -replace ' ', "<br />`n`r"}},
                        @{n='Rules';e={[string]$_.rules -replace ' ', "<br />`n`r"}}
                }
            }
        }
        'Break_PoolInformation' = @{
            'Enabled' = $true
            'ShowSectionEvenWithNoData' = $true
            'Order' = 10
            'AllData' = @{}
            'Title' = 'Pool Information'
            'Type' = 'SectionBreak'
            'ReportTypes' = @{
                'ExcelExport' = $false
                'FullDocumentation' = @{
                    'ContainerType' = 'full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' = $true
                }
            }
        }
        'Pools' = @{
            'Enabled' = $true
            'ShowSectionEvenWithNoData' = $true
            'Order' = 11
            'AllData' = @{}
            'Title' = 'Pools'
            'Type' = 'Section'
            'Comment' = $false
            'ReportTypes' = @{
                'ExcelExport' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Pool';e={$_.pool}},
                        @{n='Active Members';e={$_.activepoolmembers}},
                        @{n='Enabled';e={$_.enabled}},
                        @{n='Availability';e={$_.availability}},
                        @{n='Load Balance Method';e={$_.lbmethod}}
                }
                'FullDocumentation' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Pool';e={'<a id="{0}">{0}</a>' -f $_.pool}},
                        @{n='Active Members';e={'<a href="#members_{0}">{1}</a>' -f $_.pool,$_.activepoolmembers}},
                        @{n='Enabled';e={$_.enabled}},
                        @{n='Availability';e={$_.availability}},
                        @{n='Load Balance Method';e={$_.lbmethod}}
                }
            }
            'PostProcessing' = $PoolElements_Postprocessing
        }
        'PoolMembers' = @{
            'Enabled' = $true
            'ShowSectionEvenWithNoData' = $true
            'Order' = 12
            'AllData' = @{}
            'Title' = 'Pool Members'
            'Type' = 'Section'
            'Comment' = $false
            'ReportTypes' = @{
                'ExcelExport' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Pool';e={$_.pool}},
                        @{n='Address';e={$_.address}},
                        @{n='Port';e={$_.port}},
                        @{n='Total Connections';e={$_.totalconnections}},
                        @{n='Current Connections';e={$_.currentconnections}},
                        @{n='Bytes In';e={$_.bytes_in}},
                        @{n='Enabled';e={$_.enabled}},
                        @{n='Availability';e={$_.availability}}
                }
                'FullDocumentation' = @{
                    'ContainerType' = 'Full'
                    'SectionOverride' = $false
                    'TableType' = 'Horizontal'
                    'Properties' =
                        @{n='Pool';e={'<a id="members_{0}">{0}</a>' -f $_.pool}},
                        @{n='Address';e={$_.address}},
                        @{n='Port';e={$_.port}},
                        @{n='Total Connections';e={$_.totalconnections}},
                        @{n='Current Connections';e={$_.currentconnections}},
                        @{n='Bytes In';e={$_.bytes_in}},
                        @{n='Enabled';e={$_.enabled}},
                        @{n='Availability';e={$_.availability}}
                }
            }
            'PostProcessing' = $PoolElements_Postprocessing
        }
    }
} 
#endregion System Report Structure

#region HTML Template Variables
# This is the meat and potatoes of how the reports are spit out. Currently it is
# broken down by html component -> rendering style.
$HTMLRendering = @{
    # Markers: 
    #   <0> - Asset Name
    'Header' = @{
        'DynamicGrid' = @'
<!DOCTYPE html>
<!-- HTML5 Mobile Boilerplate -->
<!--[if IEMobile 7]><html class="no-js iem7"><![endif]-->
<!--[if (gt IEMobile 7)|!(IEMobile)]><!--><html class="no-js" lang="en"><!--<![endif]-->

<!-- HTML5 Boilerplate -->
<!--[if lt IE 7]><html class="no-js lt-ie9 lt-ie8 lt-ie7" lang="en"> <![endif]-->
<!--[if (IE 7)&!(IEMobile)]><html class="no-js lt-ie9 lt-ie8" lang="en"><![endif]-->
<!--[if (IE 8)&!(IEMobile)]><html class="no-js lt-ie9" lang="en"><![endif]-->
<!--[if gt IE 8]><!--> <html class="no-js" lang="en"><!--<![endif]-->

<head>

    <meta charset="utf-8">
    <!-- Always force latest IE rendering engine (even in intranet) & Chrome Frame -->
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
    <title><0></title>
    <meta http-equiv="cleartype" content="on">
    <link rel="shortcut icon" href="/favicon.ico">

    <!-- Responsive and mobile friendly stuff -->
    <meta name="HandheldFriendly" content="True">
    <meta name="MobileOptimized" content="320">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!-- Stylesheets 
    <link rel="stylesheet" href="css/html5reset.css" media="all">
    <link rel="stylesheet" href="css/responsivegridsystem.css" media="all">
    <link rel="stylesheet" href="css/col.css" media="all">
    <link rel="stylesheet" href="css/2cols.css" media="all">
    <link rel="stylesheet" href="css/3cols.css" media="all">
    -->
    <!--<link rel="stylesheet" href="AllStyles.css" media="all">-->
        <!-- Responsive Stylesheets 
    <link rel="stylesheet" media="only screen and (max-width: 1024px) and (min-width: 769px)" href="/css/1024.css">
    <link rel="stylesheet" media="only screen and (max-width: 768px) and (min-width: 481px)" href="/css/768.css">
    <link rel="stylesheet" media="only screen and (max-width: 480px)" href="/css/480.css">
    -->
    <!-- All JavaScript at the bottom, except for Modernizr which enables HTML5 elements and feature detects -->
    <!-- <script src="js/modernizr-2.5.3-min.js"></script> -->

    <style type="text/css">
    <!--
        /* html5reset.css - 01/11/2011 */
        html, body, div, span, object, iframe,
        h1, h2, h3, h4, h5, h6, p, blockquote, pre,
        abbr, address, cite, code,
        del, dfn, em, img, ins, kbd, q, samp,
        small, strong, sub, sup, var,
        b, i,
        dl, dt, dd, ol, ul, li,
        fieldset, form, label, legend,
        table, caption, tbody, tfoot, thead, tr, th, td,
        article, aside, canvas, details, figcaption, figure, 
        footer, header, hgroup, menu, nav, section, summary,
        time, mark, audio, video {
            margin: 0;
            padding: 0;
            border: 0;
            outline: 0;
            font-size: 100%;
            vertical-align: baseline;
            background: transparent;
        }
        body {
            line-height: 1;
        }
        article,aside,details,figcaption,figure,
        footer,header,hgroup,menu,nav,section { 
            display: block;
        }
        nav ul {
            list-style: none;
        }
        blockquote, q {
            quotes: none;
        }
        blockquote:before, blockquote:after,
        q:before, q:after {
            content: '';
            content: none;
        }
        a {
            margin: 0;
            padding: 0;
            font-size: 100%;
            vertical-align: baseline;
            background: transparent;
        }
        /* change colours to suit your needs */
        ins {
            background-color: #ff9;
            color: #000;
            text-decoration: none;
        }
        /* change colours to suit your needs */
        mark {
            background-color: #ff9;
            color: #000; 
            font-style: italic;
            font-weight: bold;
        }
        del {
            text-decoration:  line-through;
        }
        abbr[title], dfn[title] {
            border-bottom: 1px dotted;
            cursor: help;
        }
        table {
            border-collapse: collapse;
            border-spacing: 0;
        }
        /* change border colour to suit your needs */
        hr {
            display: block;
            height: 1px;
            border: 0;   
            border-top: 1px solid #cccccc;
            margin: 1em 0;
            padding: 0;
        }
        input, select {
            vertical-align: middle;
        }
        /* RESPONSIVE GRID SYSTEM =============================================================================  */
        /* BASIC PAGE SETUP ============================================================================= */
        body { 
        margin : 0 auto;
        padding : 0;
        font : 100%/1.4 'lucida sans unicode', 'lucida grande', 'Trebuchet MS', verdana, arial, helvetica, helve, sans-serif;     
        color : #000; 
        text-align: center;
        background: #fff url(/images/bodyback.png) left top;
        }
        button, 
        input, 
        select, 
        textarea { 
        font-family : MuseoSlab100, lucida sans unicode, 'lucida grande', 'Trebuchet MS', verdana, arial, helvetica, helve, sans-serif; 
        color : #333; }
        /*  HEADINGS  ============================================================================= */
        h1, h2, h3, h4, h5, h6 {
        font-family:  MuseoSlab300, 'lucida sans unicode', 'lucida grande', 'Trebuchet MS', verdana, arial, helvetica, helve, sans-serif;
        font-weight : normal;
        margin-top: 0px;
        letter-spacing: -1px;
        }
        h1 { 
        font-family:  LeagueGothicRegular, 'lucida sans unicode', 'lucida grande', 'Trebuchet MS', verdana, arial, helvetica, helve, sans-serif;
        color: #000;
        margin-bottom : 0.0em;
        font-size : 4em; /* 40 / 16 */
        line-height : 1.0;
        }
        h2 { 
        color: #222;
        margin-bottom : .5em;
        margin-top : .5em;
        font-size : 2.75em; /* 40 / 16 */
        line-height : 1.2;
        }
        h3 { 
        color: #333;
        margin-bottom : 0.3em;
        letter-spacing: -1px;
        font-size : 1.75em; /* 28 / 16 */
        line-height : 1.3; }
        h4 { 
        color: #444;
        margin-bottom : 0.5em;
        font-size : 1.5em; /* 24 / 16  */
        line-height : 1.25; }
            footer h4 { 
                color: #ccc;
            }
        h5 { 
        color: #555;
        margin-bottom : 1.25em;
        font-size : 1em; /* 20 / 16 */ }
        h6 { 
        color: #666;
        font-size : 1em; /* 16 / 16  */ }
        /*  TYPOGRAPHY  ============================================================================= */
        p, ol, ul, dl, address { 
        margin-bottom : 1.5em; 
        font-size : 1em; /* 16 / 16 = 1 */ }
        p {
        hyphens : auto;  }
        p.introtext {
        font-family:  MuseoSlab100, 'lucida sans unicode', 'lucida grande', 'Trebuchet MS', verdana, arial, helvetica, helve, sans-serif;
        font-size : 2.5em; /* 40 / 16 */
        color: #333;
        line-height: 1.4em;
        letter-spacing: -1px;
        margin-bottom: 0.5em;
        }
        p.handwritten {
        font-family:  HandSean, 'lucida sans unicode', 'lucida grande', 'Trebuchet MS', verdana, arial, helvetica, helve, sans-serif; 
        font-size: 1.375em; /* 24 / 16 */
        line-height: 1.8em;
        margin-bottom: 0.3em;
        color: #666;
        }
        p.center {
        text-align: center;
        }
        .and {
        font-family: GoudyBookletter1911Regular, Georgia, Times New Roman, sans-serif;
        font-size: 1.5em; /* 24 / 16 */
        }
        .heart {
        font-family: Pictos;
        font-size: 1.5em; /* 24 / 16 */
        }
        ul, 
        ol { 
        margin : 0 0 1.5em 0; 
        padding : 0 0 0 24px; }
        li ul, 
        li ol { 
        margin : 0;
        font-size : 1em; /* 16 / 16 = 1 */ }
        dl, 
        dd { 
        margin-bottom : 1.5em; }
        dt { 
        font-weight : normal; }
        b, strong { 
        font-weight : bold; }
        hr { 
        display : block; 
        margin : 1em 0; 
        padding : 0;
        height : 1px; 
        border : 0; 
        border-top : 1px solid #ccc;
        }
        small { 
        font-size : 1em; /* 16 / 16 = 1 */ }
        sub, sup { 
        font-size : 75%; 
        line-height : 0; 
        position : relative; 
        vertical-align : baseline; }
        sup { 
        top : -.5em; }
        sub { 
        bottom : -.25em; }
        .subtext {
            color: #666;
            }
        /* LINKS =============================================================================  */
        a { 
        color : #cc1122;
        -webkit-transition: all 0.3s ease;
        -moz-transition: all 0.3s ease;
        -o-transition: all 0.3s ease;
        transition: all 0.3s ease;
        text-decoration: none;
        }
        a:visited { 
        color : #ee3344; }
        a:focus { 
        outline : thin dotted; 
        color : rgb(0,0,0); }
        a:hover, 
        a:active { 
        outline : 0;
        color : #dd2233;
        }
        footer a { 
        color : #ffffff;
        -webkit-transition: all 0.3s ease;
        -moz-transition: all 0.3s ease;
        -o-transition: all 0.3s ease;
        transition: all 0.3s ease;
        }
        footer a:visited { 
        color : #fff; }
        footer a:focus { 
        outline : thin dotted; 
        color : rgb(0,0,0); }
        footer a:hover, 
        footer a:active { 
        outline : 0;
        color : #fff;
        }
        /* IMAGES ============================================================================= */
        img {
        border : 0;
        max-width: 100%;}
        img.floatleft { float: left; margin: 0 10px 0 0; }
        img.floatright { float: right; margin: 0 0 0 10px; }
        /* TABLES ============================================================================= */
        table { 
        border-collapse : collapse;
        border-spacing : 0;
        margin-bottom : 0em; 
        width : 100%; }
        th, td, caption { 
        padding : .25em 10px .25em 5px; }
        tfoot { 
        font-style : italic; }
        caption { 
        background-color : transparent; }
        /*  MAIN LAYOUT    ============================================================================= */
        #skiptomain { display: none; }
        #wrapper {
            width: 100%;
            position: relative;
            text-align: left;
        }
            #headcontainer {
                width: 100%;
            }
                header {
                    clear: both;
                    width: 100%; /* 1000px / 1250px */
                    font-size: 0.6125em; /* 13 / 16 */
                    max-width: 92.3em; /* 1200px / 13 */
                    margin: 0 auto;
                    padding: 5px 0px 0px 0px;
                    position: relative;
                    color: #000;
                    text-align: center ;
                }
            #maincontentcontainer {
                width: 100%;
            }
                .standardcontainer {
                }
                .darkcontainer {
                    background: rgba(102, 102, 102, 0.05);
                }
                .lightcontainer {
                    background: rgba(255, 255, 255, 0.25);
                }
                    #maincontent{
                        clear: both;
                        width: 80%; /* 1000px / 1250px */
                        font-size: 0.8125em; /* 13 / 16 */
                        max-width: 92.3em; /* 1200px / 13 */
                        margin: 0 auto;
                        padding: 1em 0px;
                        color: #333;
                        line-height: 1.5em;
                        position: relative;
                    }
                    .maincontent{
                        clear: both;
                        width: 80%; /* 1000px / 1250px */
                        font-size: 0.8125em; /* 13 / 16 */
                        max-width: 92.3em; /* 1200px / 13 */
                        margin: 0 auto;
                        padding: 1em 0px;
                        color: #333;
                        line-height: 1.5em;
                        position: relative;
                    }
            #footercontainer {
                width: 100%;    
                border-top: 1px solid #000;
                background: #222 url(/images/footerback.png) left top;
            }
                footer {
                    clear: both;
                    width: 80%; /* 1000px / 1250px */
                    font-size: 0.8125em; /* 13 / 16 */
                    max-width: 92.3em; /* 1200px / 13 */
                    margin: 0 auto;
                    padding: 20px 0px 10px 0px;
                    color: #999;
                }
                footer strong {
                    font-size: 1.077em; /* 14 / 13 */
                    color: #aaa;
                }
                footer a:link, footer a:visited { color: #999; text-decoration: underline; }
                footer a:hover { color: #fff; text-decoration: underline; }
                ul.pagefooterlist, ul.pagefooterlistimages {
                    display: block;
                    float: left;
                    margin: 0px;
                    padding: 0px;
                    list-style: none;
                }
                ul.pagefooterlist li, ul.pagefooterlistimages li {
                    clear: left;
                    margin: 0px;
                    padding: 0px 0px 3px 0px;
                    display: block;
                    line-height: 1.5em;
                    font-weight: normal;
                    background: none;
                }
                ul.pagefooterlistimages li {
                    height: 34px;
                }
                ul.pagefooterlistimages li img {
                    padding: 5px 5px 5px 0px;
                    vertical-align: middle;
                    opacity: 0.75;
                    -ms-filter: "progid:DXImageTransform.Microsoft.Alpha(Opacity=75)";
                    filter: alpha( opacity  = 75);
                    -webkit-transition: all 0.3s ease;
                    -moz-transition: all 0.3s ease;
                    -o-transition: all 0.3s ease;
                    transition: all 0.3s ease;
                }
                ul.pagefooterlistimages li a
                {
                    text-decoration: none;
                }
                ul.pagefooterlistimages li a:hover img {
                    opacity: 1.0;
                    -ms-filter: "progid:DXImageTransform.Microsoft.Alpha(Opacity=100)";
                    filter: alpha( opacity  = 100);
                }
                    #smallprint {
                        margin-top: 20px;
                        line-height: 1.4em;
                        text-align: center;
                        color: #999;
                        font-size: 0.923em; /* 12 / 13 */
                    }
                    #smallprint p{
                        vertical-align: middle;
                    }
                    #smallprint .twitter-follow-button{
                        margin-left: 1em;
                        vertical-align: middle;
                    }
                    #smallprint img {
                        margin: 0px 10px 15px 0px;
                        vertical-align: middle;
                        opacity: 0.5;
                        -ms-filter: "progid:DXImageTransform.Microsoft.Alpha(Opacity=50)";
                        filter: alpha( opacity  = 50);
                        -webkit-transition: all 0.3s ease;
                        -moz-transition: all 0.3s ease;
                        -o-transition: all 0.3s ease;
                        transition: all 0.3s ease;
                    }
                    #smallprint a:hover img {
                        opacity: 1.0;
                        -ms-filter: "progid:DXImageTransform.Microsoft.Alpha(Opacity=100)";
                        filter: alpha( opacity  = 100);
                    }
                    #smallprint a:link, #smallprint a:visited { color: #999; text-decoration: none; }
                    #smallprint a:hover { color: #999; text-decoration: underline; }
        /*  SECTIONS  ============================================================================= */
        .section {
            clear: both;
            padding: 0px;
            margin: 0px;
        }
        /*  CODE  ============================================================================= */
        pre.code {
            padding: 0;
            margin: 0;
            font-family: monospace;
            white-space: pre-wrap;
            font-size: 1.1em;
        }
        strong.code {
            font-weight: normal;
            font-family: monospace;
            font-size: 1.2em;
        }
        /*  EXAMPLE  ============================================================================= */
        #example .col {
            background: #ccc;
            background: rgba(204, 204, 204, 0.85);
        }
        /*  NOTES  ============================================================================= */
        .note {
            position:relative;
            padding:1em 1.5em;
            margin: 0 0 1em 0;
            background: #fff;
            background: rgba(255, 255, 255, 0.5);
            overflow:hidden;
        }
        .note:before {
            content:"";
            position:absolute;
            top:0;
            right:0;
            border-width:0 16px 16px 0;
            border-style:solid;
            border-color:transparent transparent #cccccc #cccccc;
            background:#cccccc;
            -webkit-box-shadow:0 1px 1px rgba(0,0,0,0.3), -1px 1px 1px rgba(0,0,0,0.2);
            -moz-box-shadow:0 1px 1px rgba(0,0,0,0.3), -1px 1px 1px rgba(0,0,0,0.2);
            box-shadow:0 1px 1px rgba(0,0,0,0.3), -1px 1px 1px rgba(0,0,0,0.2);
            display:block; width:0; /* Firefox 3.0 damage limitation */
        }
        .note.rounded {
            -webkit-border-radius:5px 0 5px 5px;
            -moz-border-radius:5px 0 5px 5px;
            border-radius:5px 0 5px 5px;
        }
        .note.rounded:before {
            border-width:8px;
            border-color:#ff #ff transparent transparent;
            background: url(/images/bodyback.png);
            -webkit-border-bottom-left-radius:5px;
            -moz-border-radius:0 0 0 5px;
            border-radius:0 0 0 5px;
        }
        /*  SCREENS  ============================================================================= */
        .siteimage {
            max-width: 90%;
            padding: 5%;
            margin: 0 0 1em 0;
            background: transparent url(/images/stripe-bg.png);
            -webkit-transition: background 0.3s ease;
            -moz-transition: background 0.3s ease;
            -o-transition: background 0.3s ease;
            transition: background 0.3s ease;
        }
        .siteimage:hover {
            background: #bbb url(/images/stripe-bg.png);
            position: relative;
            top: -2px;
            
        }
        /*  COLUMNS  ============================================================================= */
        .twocolumns{
            -moz-column-count: 2;
            -moz-column-gap: 2em;
            -webkit-column-count: 2;
            -webkit-column-gap: 2em;
            column-count: 2;
            column-gap: 2em;
          }
        /*  GLOBAL OBJECTS ============================================================================= */
        .breaker { clear: both; }
        .group:before,
        .group:after {
            content:"";
            display:table;
        }
        .group:after {
            clear:both;
        }
        .group {
            zoom:1; /* For IE 6/7 (trigger hasLayout) */
        }
        .floatleft {
            float: left;
        }
        .floatright {
            float: right;
        }
        /* VENDOR-SPECIFIC ============================================================================= */
        html { 
        -webkit-overflow-scrolling : touch; 
        -webkit-tap-highlight-color : rgb(52,158,219); 
        -webkit-text-size-adjust : 100%; 
        -ms-text-size-adjust : 100%; }
        .clearfix { 
        zoom : 1; }
        ::-webkit-selection { 
        background : rgb(23,119,175); 
        color : rgb(250,250,250); 
        text-shadow : none; }
        ::-moz-selection { 
        background : rgb(23,119,175); 
        color : rgb(250,250,250); 
        text-shadow : none; }
        ::selection { 
        background : rgb(23,119,175); 
        color : rgb(250,250,250); 
        text-shadow : none; }
        button, 
        input[type="button"], 
        input[type="reset"], 
        input[type="submit"] { 
        -webkit-appearance : button; }
        ::-webkit-input-placeholder {
        font-size : .875em; 
        line-height : 1.4; }
        input:-moz-placeholder { 
        font-size : .875em; 
        line-height : 1.4; }
        .ie7 img,
        .iem7 img { 
        -ms-interpolation-mode : bicubic; }
        input[type="checkbox"], 
        input[type="radio"] { 
        box-sizing : border-box; }
        input[type="search"] { 
        -webkit-box-sizing : content-box;
        -moz-box-sizing : content-box; }
        button::-moz-focus-inner, 
        input::-moz-focus-inner { 
        padding : 0;
        border : 0; }
        p {
        /* http://www.w3.org/TR/css3-text/#hyphenation */
        -webkit-hyphens : auto;
        -webkit-hyphenate-character : "\2010";
        -webkit-hyphenate-limit-after : 1;
        -webkit-hyphenate-limit-before : 3;
        -moz-hyphens : auto; }
        /*  SECTIONS  ============================================================================= */
        .section {
            clear: both;
            padding: 0px;
            margin: 0px;
        }
        /*  GROUPING  ============================================================================= */
        .group:before,
        .group:after {
            content:"";
            display:table;
        }
        .group:after {
            clear:both;
        }
        .group {
            zoom:1; /* For IE 6/7 (trigger hasLayout) */
        }
        /*  GRID COLUMN SETUP   ==================================================================== */
        .col {
            display: block;
            float:left;
            margin: 1% 0 1% 1.6%;
        }
        .col:first-child { margin-left: 0; } /* all browsers except IE6 and lower */
        /*  REMOVE MARGINS AS ALL GO FULL WIDTH AT 480 PIXELS */
        @media only screen and (max-width: 480px) {
            .col { 
                margin: 1% 0 1% 0%;
            }
        }
        /*  GRID OF TWO   ============================================================================= */
        .span_2_of_2 {
            width: 100%;
        }
        .span_1_of_2 {
            width: 49.2%;
        }
        /*  GO FULL WIDTH AT LESS THAN 480 PIXELS */
        @media only screen and (max-width: 480px) {
            .span_2_of_2 {
                width: 100%; 
            }
            .span_1_of_2 {
                width: 100%; 
            }
        }
        /*  GRID OF THREE   ============================================================================= */
        .span_3_of_3 {
            width: 100%; 
        }
        .span_2_of_3 {
            width: 66.1%; 
        }
        .span_1_of_3 {
            width: 32.2%; 
        }
        /*  GO FULL WIDTH AT LESS THAN 480 PIXELS */
        @media only screen and (max-width: 480px) {
            .span_3_of_3 {
                width: 100%; 
            }
            .span_2_of_3 {
                width: 100%; 
            }
            .span_1_of_3 {
                width: 100%;
            }
        }
        /*  GRID OF FOUR   ============================================================================= */
        .span_4_of_4 {
            width: 100%; 
        }
        .span_3_of_4 {
            width: 74.6%; 
        }
        .span_2_of_4 {
            width: 49.2%; 
        }
        .span_1_of_4 {
            width: 23.8%; 
        }
        /*  GO FULL WIDTH AT LESS THAN 480 PIXELS */
        @media only screen and (max-width: 480px) {
            .span_4_of_4 {
                width: 100%; 
            }
            .span_3_of_4 {
                width: 100%; 
            }
            .span_2_of_4 {
                width: 100%; 
            }
            .span_1_of_4 {
                width: 100%; 
            }
        }
        
        body {
            font-family: Verdana, Geneva, Arial, Helvetica, sans-serif;
        }
        
        table{
            border-collapse: collapse;
            border: none;
            font: 10pt Verdana, Geneva, Arial, Helvetica, sans-serif;
            color: black;
            margin-bottom: 0px;
        }
        table td{
            font-size: 10px;
            padding-left: 0px;
            padding-right: 20px;
            text-align: left;
        }
        table td:last-child{
            padding-right: 5px;
        }
        table th {
            font-size: 12px;
            font-weight: bold;
            padding-left: 0px;
            padding-right: 20px;
            text-align: left;
            border-bottom: 1px  grey solid;
        }
        h2{ 
            clear: both;
            font-size: 200%; 
            margin-left: 20px;
            font-weight: bold;
        }
        h3{
            clear: both;
            font-size: 115%;
            margin-left: 20px;
            margin-top: 30px;
        }
        p{ 
            margin-left: 20px; font-size: 12px;
        }
        table.list{
            float: left;
        }
        table.list td:nth-child(1){
            font-weight: bold;
            border-right: 1px grey solid;
            text-align: right;
        }
        table.list td:nth-child(2){
            padding-left: 7px;
        }
        table tr:nth-child(even) td:nth-child(even){ background: #CCCCCC; }
        table tr:nth-child(odd) td:nth-child(odd){ background: #F2F2F2; }
        table tr:nth-child(even) td:nth-child(odd){ background: #DDDDDD; }
        table tr:nth-child(odd) td:nth-child(even){ background: #E5E5E5; }
        
        /*  Error and warning highlighting - Row*/
        table tr.warn:nth-child(even) td:nth-child(even){ background: #FFFF88; }
        table tr.warn:nth-child(odd) td:nth-child(odd){ background: #FFFFBB; }
        table tr.warn:nth-child(even) td:nth-child(odd){ background: #FFFFAA; }
        table tr.warn:nth-child(odd) td:nth-child(even){ background: #FFFF99; }
        
        table tr.alert:nth-child(even) td:nth-child(even){ background: #FF8888; }
        table tr.alert:nth-child(odd) td:nth-child(odd){ background: #FFBBBB; }
        table tr.alert:nth-child(even) td:nth-child(odd){ background: #FFAAAA; }
        table tr.alert:nth-child(odd) td:nth-child(even){ background: #FF9999; }
        
        table tr.healthy:nth-child(even) td:nth-child(even){ background: #88FF88; }
        table tr.healthy:nth-child(odd) td:nth-child(odd){ background: #BBFFBB; }
        table tr.healthy:nth-child(even) td:nth-child(odd){ background: #AAFFAA; }
        table tr.healthy:nth-child(odd) td:nth-child(even){ background: #99FF99; }
        
        /*  Error and warning highlighting - Cell*/
        table tr:nth-child(even) td.warn:nth-child(even){ background: #FFFF88; }
        table tr:nth-child(odd) td.warn:nth-child(odd){ background: #FFFFBB; }
        table tr:nth-child(even) td.warn:nth-child(odd){ background: #FFFFAA; }
        table tr:nth-child(odd) td.warn:nth-child(even){ background: #FFFF99; }
        
        table tr:nth-child(even) td.alert:nth-child(even){ background: #FF8888; }
        table tr:nth-child(odd) td.alert:nth-child(odd){ background: #FFBBBB; }
        table tr:nth-child(even) td.alert:nth-child(odd){ background: #FFAAAA; }
        table tr:nth-child(odd) td.alert:nth-child(even){ background: #FF9999; }
        
        table tr:nth-child(even) td.healthy:nth-child(even){ background: #88FF88; }
        table tr:nth-child(odd) td.healthy:nth-child(odd){ background: #BBFFBB; }
        table tr:nth-child(even) td.healthy:nth-child(odd){ background: #AAFFAA; }
        table tr:nth-child(odd) td.healthy:nth-child(even){ background: #99FF99; }
        
        /* security highlighting */
        table tr.security:nth-child(even) td:nth-child(even){ 
            border-color: #FF1111; 
            border: 1px #FF1111 solid;
        }
        table tr.security:nth-child(odd) td:nth-child(odd){ 
            border-color: #FF1111; 
            border: 1px #FF1111 solid;
        }
        table tr.security:nth-child(even) td:nth-child(odd){
            border-color: #FF1111; 
            border: 1px #FF1111 solid;
        }
        table tr.security:nth-child(odd) td:nth-child(even){
            border-color: #FF1111; 
            border: 1px #FF1111 solid;
        }
        table th.title{ 
            text-align: center;
            background: #848482;
            border-bottom: 1px  black solid;
            font-weight: bold;
            color: white;
        }
        table th.sectioncomment{ 
            text-align: left;
            background: #848482;
            font-style : italic;
            color: white;
            font-weight: normal;
            
            padding: 0px;
        }
        table th.sectioncolumngrouping{ 
            text-align: center;
            background: #AAAAAA;
            color: black;
            font-weight: bold;
            border:1px solid white;
        }
        table th.sectionbreak{ 
            text-align: center;
            background: #848482;
            border: 2px black solid;
            font-weight: bold;
            color: white;
            font-size: 130%;
        }
        table th.reporttitle{ 
            text-align: center;
            background: #848482;
            border: 2px black solid;
            font-weight: bold;
            color: white;
            font-size: 150%;
        }
        table tr.divide{
            border-bottom: 1px  grey solid;
        }
    -->
    </style></head>

<body>
<div id="wrapper">
'@
        'EmailFriendly' = @'
<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01 Frameset//EN' 'http://www.w3.org/TR/html4/frameset.dtd'>
<html><head><title><0></title>
<style type='text/css'>
<!--
body {
    font-family: Verdana, Geneva, Arial, Helvetica, sans-serif;
}
table{
   border-collapse: collapse;
   border: none;
   font: 10pt Verdana, Geneva, Arial, Helvetica, sans-serif;
   color: black;
   margin-bottom: 10px;
   margin-left: 20px;
}
table td{
   font-size: 12px;
   padding-left: 0px;
   padding-right: 20px;
   text-align: left;
   border:1px solid black;
}
table th {
   font-size: 12px;
   font-weight: bold;
   padding-left: 0px;
   padding-right: 20px;
   text-align: left;
}

h1{ clear: both;
    font-size: 150%; 
    text-align: center;
  }
h2{ clear: both; font-size: 130%; }

h3{
   clear: both;
   font-size: 115%;
   margin-left: 20px;
   margin-top: 30px;
}

p{ margin-left: 20px; font-size: 12px; }

table.list{ float: left; }
   table.list td:nth-child(1){
   font-weight: bold;
   border: 1px grey solid;
   text-align: right;
}

table th.title{ 
    text-align: center;
    background: #848482;
    border: 2px  grey solid;
    font-weight: bold;
    color: white;
}
table tr.divide{
    border-bottom: 5px  grey solid;
}
.odd { background-color:#ffffff; }
.even { background-color:#dddddd; }
.warn { background-color:yellow; }
.alert { background-color:red; }
-->
</style>
</head>
<body>
'@
    }
    'Footer' = @{
        'DynamicGrid' = @'
</div>
</body>
</html>        
'@
        'EmailFriendly' = @'
</div>
</body>
</html>       
'@
    }

    # Markers: 
    #   <0> - Server Name
    'ServerBegin' = @{
        'DynamicGrid' = @'
    
    <hr noshade size="3" width='100%'>
    <div id="headcontainer">
        <table>        
            <tr>
                <th class="reporttitle"><0></th>
            </tr>
        </table>
    </div>
    <div id="maincontentcontainer">
        <div id="maincontent">
            <div class="section group">
                <hr noshade size="3" width='100%'>
            </div>
            <div>

       
'@
        'EmailFriendly' = @'
    <div id='report'>
    <hr noshade size=3 width='100%'>
    <h1><0></h1>

    <div id="maincontentcontainer">
    <div id="maincontent">
      <div class="section group">
        <hr noshade="noshade" size="3" width="100%" style=
        "display:block;height:1px;border:0;border-top:1px solid #ccc;margin:1em 0;padding:0;" />
      </div>
      <div>

'@    
    }
    'ServerEnd' = @{
        'DynamicGrid' = @'

            </div>
        </div>
    </div>
</div>

'@
        'EmailFriendly' = @'

            </div>
        </div>
    </div>
</div>

'@
    }
    
    # Markers: 
    #   <0> - columns to span title
    #   <1> - Table header title
    'TableTitle' = @{
        'DynamicGrid' = @'
        
            <tr>
                <th class="title" colspan=<0>><1></th>
            </tr>
'@
        'EmailFriendly' = @'
            
            <tr>
              <th class="title" colspan="<0>"><1></th>
            </tr>
              
'@
    }
    
    'TableComment' = @{
        'DynamicGrid' = @'
        
            <tr>
                <th class="sectioncomment" colspan=<0>><1></th>
            </tr>
'@
        'EmailFriendly' = @'
            
            <tr>
              <th class="sectioncomment" colspan="<0>"><1></th>
            </tr>
              
'@
    }    

    'SectionContainers' = @{
        'DynamicGrid'  = @{
            'Half' = @{
                'Head' = @'
        
        <div class="col span_2_of_4">
'@
                'Tail' = @'
        </div>
'@
            }
            'Full' = @{
                'Head' = @'
        
        <div class="col span_4_of_4">
'@
                'Tail' = @'
        </div>
'@
            }
            'Third' = @{
                'Head' = @'
        
        <div class="col span_1_of_3">
'@
                'Tail' = @'
        </div>
'@
            }
            'TwoThirds' = @{
                'Head' = @'
        
        <div class="col span_2_of_3">
'@
                'Tail' = @'
                
        </div>
'@
            }
            'Fourth'        = @{
                'Head' = @'
        
        <div class="col span_1_of_4">
'@
                'Tail' = @'
                
        </div>
'@
            }
            'ThreeFourths'  = @{
                'Head' = @'
               
        <div class="col span_3_of_4">
'@
                'Tail'          = @'
        
        </div>
'@
            }
        }
        'EmailFriendly'  = @{
            'Half' = @{
                'Head' = @'
        
        <div class="col span_2_of_4">
        <table><tr WIDTH="50%">
'@
                'Tail' = @'
        </tr></table>       
        </div>
'@
            }
            'Full' = @{
                'Head' = @'
        
        <div class="col span_4_of_4">
'@
                'Tail' = @'
                
        </div>
'@
            }
            'Third' = @{
                'Head' = @'
        
        <div class="col span_1_of_3">
'@
                'Tail' = @'
                
        </div>
'@
            }
            'TwoThirds' = @{
                'Head' = @'
        
        <div class="col span_2_of_3">
'@
                'Tail' = @'
                
        </div>
'@
            }
            'Fourth'        = @{
                'Head' = @'
        
        <div class="col span_1_of_4">
'@
                'Tail' = @'
                
        </div>
'@
            }
            'ThreeFourths'  = @{
                'Head' = @'
               
        <div class="col span_3_of_4">
'@
                'Tail'          = @'
        
        </div>
'@
            }
        }
    }
    
    'SectionContainerGroup' = @{
        'DynamicGrid' = @{ 
            'Head' = @'
        
        <div class="section group">
'@
            'Tail' = @'
        </div>
'@
        }
        'EmailFriendly' = @{
            'Head' = @'
    
        <div class="section group">
'@
            'Tail' = @'
        </div>
'@
        }
    }
    
    'CustomSections' = @{
        # Markers: 
        #   <0> - Header
        'SectionBreak' = @'
    
    <div class="section group">        
        <div class="col span_4_of_4"><table>        
            <tr>
                <th class="sectionbreak"><0></th>
            </tr>
        </table>
        </div>
    </div>
'@
    }
}
#endregion HTML Template Variables
#endregion Globals

#region Functions - Serial or Utility
Function ConvertTo-PropertyValue 
{
    <#
    .SYNOPSIS
    Convert an object with various properties into an array of property, value pairs 
    
    .DESCRIPTION
    Convert an object with various properties into an array of property, value pairs

    If you output reports or other formats where a table with one long row is poorly formatted, this is a quick way to create a table of property value pairs.

    There are other ways you could do this.  For example, I could list all noteproperties from Get-Member results and return them.
    This function will keep properties in the same order they are provided, which can often be helpful for readability of results.

    .PARAMETER inputObject
    A single object to convert to an array of property value pairs.

    .PARAMETER leftheader
    Header for the left column.  Default:  Property

    .PARAMETER rightHeader
    Header for the right column.  Default:  Value

    .PARAMETER memberType
    Return only object members of this membertype.  Default:  Property, NoteProperty, ScriptProperty

    .EXAMPLE
    get-process powershell_ise | convertto-propertyvalue

    I want details on the powershell_ise process.
        With this command, if I output this to a table, a csv, etc. I will get a nice vertical listing of properties and their values
        Without this command, I get a long row with the same info

    .EXAMPLE
    #This example requires and demonstrates using the New-HTMLHead, New-HTMLTable, Add-HTMLTableColor, ConvertTo-PropertyValue and Close-HTML functions.
    
    #get processes to work with
        $processes = Get-Process
    
    #Build HTML header
        $HTML = New-HTMLHead -title "Process details"

    #Add CPU time section with top 10 PrivateMemorySize processes.  This example does not highlight any particular cells
        $HTML += "<h3>Process Private Memory Size</h3>"
        $HTML += New-HTMLTable -inputObject $($processes | sort PrivateMemorySize -Descending | select name, PrivateMemorySize -first 10)

    #Add Handles section with top 10 Handle usage.
    $handleHTML = New-HTMLTable -inputObject $($processes | sort handles -descending | select Name, Handles -first 10)

        #Add highlighted colors for Handle count
            
            #build hash table with parameters for Add-HTMLTableColor.  Argument and AttrValue will be modified each time we run this.
            $params = @{
                Column = "Handles" #I'm looking for cells in the Handles column
                ScriptBlock = {[double]$args[0] -gt [double]$args[1]} #I want to highlight if the cell (args 0) is greater than the argument parameter (arg 1)
                Attr = "Style" #This is the default, don't need to actually specify it here
            }

            #Add yellow, orange and red shading
            $handleHTML = Add-HTMLTableColor -HTML $handleHTML -Argument 1500 -attrValue "background-color:#FFFF99;" @params
            $handleHTML = Add-HTMLTableColor -HTML $handleHTML -Argument 2000 -attrValue "background-color:#FFCC66;" @params
            $handleHTML = Add-HTMLTableColor -HTML $handleHTML -Argument 3000 -attrValue "background-color:#FFCC99;" @params
      
        #Add title and table
        $HTML += "<h3>Process Handles</h3>"
        $HTML += $handleHTML

    #Add process list containing first 10 processes listed by get-process.  This example does not highlight any particular cells
        $HTML += New-HTMLTable -inputObject $($processes | select name -first 10 ) -listTableHead "Random Process Names"

    #Add property value table showing details for PowerShell ISE
        $HTML += "<h3>PowerShell Process Details PropertyValue table</h3>"
        $processDetails = Get-process powershell_ise | select name, id, cpu, handles, workingset, PrivateMemorySize, Path -first 1
        $HTML += New-HTMLTable -inputObject $(ConvertTo-PropertyValue -inputObject $processDetails)

    #Add same PowerShell ISE details but not in property value form.  Close the HTML
        $HTML += "<h3>PowerShell Process Details object</h3>"
        $HTML += New-HTMLTable -inputObject $processDetails | Close-HTML

    #write the HTML to a file and open it up for viewing
        set-content C:\test.htm $HTML
        & 'C:\Program Files\Internet Explorer\iexplore.exe' C:\test.htm

    .FUNCTIONALITY
    General Command
    #> 
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [PSObject]$InputObject,
        
        [validateset("AliasProperty", "CodeProperty", "Property", "NoteProperty", "ScriptProperty",
            "Properties", "PropertySet", "Method", "CodeMethod", "ScriptMethod", "Methods",
            "ParameterizedProperty", "MemberSet", "Event", "Dynamic", "All")]
        [string[]]$memberType = @( "NoteProperty", "Property", "ScriptProperty" ),
            
        [string]$leftHeader = "Property",
            
        [string]$rightHeader = "Value"
    )

    begin{
        #init array to dump all objects into
        $allObjects = @()

    }
    process{
        #if we're taking from pipeline and get more than one object, this will build up an array
        $allObjects += $inputObject
    }

    end{
        #use only the first object provided
        $allObjects = $allObjects[0]

        #Get properties.  Filter by memberType.
        $properties = $allObjects.psobject.properties | ?{$memberType -contains $_.memberType} | select -ExpandProperty Name

        #loop through properties and display property value pairs
        foreach($property in $properties){

            #Create object with property and value
            $temp = "" | select $leftHeader, $rightHeader
            $temp.$leftHeader = $property.replace('"',"")
            $temp.$rightHeader = try { $allObjects | select -ExpandProperty $temp.$leftHeader -erroraction SilentlyContinue } catch { $null }
            $temp
        }
    }
}

Function ConvertTo-HashArray
{
    <#
    .SYNOPSIS
    Convert an array of objects to a hash table based on a single property of the array. 
    
    .DESCRIPTION
    Convert an array of objects to a hash table based on a single property of the array.
    
    .PARAMETER InputObject
    An array of objects to convert to a hash table array.

    .PARAMETER PivotProperty
    The property to use as the key value in the resulting hash.
    
    .PARAMETER LookupValue
    Property in the psobject to be the value that the hash key points to in the returned result. If not specified, all properties in the psobject are used.

    .EXAMPLE
    $DellServerHealth = @(Get-DellServerhealth @_dellhardwaresplat)
    $DellServerHealth = ConvertTo-HashArray $DellServerHealth 'PSComputerName'

    Description
    -----------
    Calls a function which returns a psobject then converts that result to a hash array based on the PSComputerName
    
    .NOTES
    Author: Zachary Loeber
    
    Version Info:
    1.1 - 11/17/2013
        - Added LookupValue Parameter to allow for creation of one to one hashs
        - Added more error validation
        - Dolled up the paramerters
        
    .LINK 
    http://www.the-little-things.net 
    #> 
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   HelpMessage='A single or array of PSObjects',
                   Position=0)]
        [AllowEmptyCollection()]
        [PSObject[]]
        $InputObject,
        
        [Parameter(Mandatory=$true,
                   HelpMessage='Property in the psobject to be the future key in a returned hash.',
                   Position=1)]
        [string]$PivotProperty,
        
        [Parameter(HelpMessage='Property in the psobject to be the value that the hash key points to. If not specified, all properties in the psobject are used.',
                   Position=2)]
        [string]$LookupValue = ''
    )

    BEGIN
    {
        #init array to dump all objects into
        $allObjects = @()
        $Results = @{}
    }
    PROCESS
    {
        #if we're taking from pipeline and get more than one object, this will build up an array
        $allObjects += $inputObject
    }

    END
    {
        ForEach ($object in $allObjects)
        {
            if ($object -ne $null)
            {
                try
                {
                    if ($object.PSObject.Properties.Match($PivotProperty).Count) 
                    {
                        if ($LookupValue -eq '')
                        {
                            $Results[$object.$PivotProperty] = $object
                        }
                        else
                        {
                            if ($object.PSObject.Properties.Match($LookupValue).Count)
                            {
                                $Results[$object.$PivotProperty] = $object.$LookupValue
                            }
                            else
                            {
                                Write-Warning -Message ('ConvertTo-HashArray: LookupValue Not Found - {0}' -f $_.Exception.Message)
                            }
                        }
                    }
                    else
                    {
                        Write-Warning -Message ('ConvertTo-HashArray: LookupValue Not Found - {0}' -f $_.Exception.Message)
                    }
                }
                catch
                {
                    Write-Warning -Message ('ConvertTo-HashArray: Something weird happened! - {0}' -f $_.Exception.Message)
                }
            }
        }
        $Results
    }
}

Function ConvertTo-PSObject
{
    <# 
     Take an array of like psobject and convert it to a singular psobject based on two shared
     properties across all psobjects in the array.
     Example Input object: 
    $obj = @()
    $a = @{ 
        'PropName' = 'Property 1'
        'Val1' = 'Value 1'
        }
    $b = @{ 
        'PropName' = 'Property 2'
        'Val1' = 'Value 2'
        }
    $obj += new-object psobject -property $a
    $obj += new-object psobject -property $b

    $c = $obj | ConvertTo-PSObject -propname 'PropName' -valname 'Val1'
    $c.'Property 1'
    Value 1
    #>
    [cmdletbinding()]
    PARAM(
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        [PSObject[]]$InputObject,
        [string]$propname,
        [string]$valname
    )

    BEGIN
    {
        #init array to dump all objects into
        $allObjects = @()
    }
    PROCESS
    {
        #if we're taking from pipeline and get more than one object, this will build up an array
        $allObjects += $inputObject
    }
    END
    {
        $returnobject = New-Object psobject
        foreach ($obj in $allObjects)
        {
            if ($obj.$propname -ne $null)
            {
                $returnobject | Add-Member -MemberType NoteProperty -Name $obj.$propname -Value $obj.$valname
            }
        }
        $returnobject
    }
}

Function ConvertTo-MultiArray 
{
 <#
 .Notes
 NAME: ConvertTo-MultiArray
 AUTHOR: Tome Tanasovski
 Website: http://powertoe.wordpress.com
 Twitter: http://twitter.com/toenuff
 Version: 1.0
 CREATED: 11/5/2010
 LASTEDIT:
 11/5/2010 1.0
 Initial Release
 11/5/2010 1.1
 Removed array parameter and passes a reference to the multi-dimensional array as output to the cmdlet
 11/5/2010 1.2
 Modified all rows to ensure they are entered as string values including $null values as a blank ("") string.

 .Synopsis
 Converts a collection of PowerShell objects into a multi-dimensional array

 .Description
 Converts a collection of PowerShell objects into a multi-dimensional array.  The first row of the array contains the property names.  Each additional row contains the values for each object.

 This cmdlet was created to act as an intermediary to importing PowerShell objects into a range of cells in Exchange.  By using a multi-dimensional array you can greatly speed up the process of adding data to Excel through the Excel COM objects.

 .Parameter InputObject
 Specifies the objects to export into the multi dimensional array.  Enter a variable that contains the objects or type a command or expression that gets the objects. You can also pipe objects to ConvertTo-MultiArray.

 .Inputs
 System.Management.Automation.PSObject
        You can pipe any .NET Framework object to ConvertTo-MultiArray

 .Outputs
 [ref]
        The cmdlet will return a reference to the multi-dimensional array.  To access the array itself you will need to use the Value property of the reference

 .Example
 $arrayref = get-process |Convertto-MultiArray

 .Example
 $dir = Get-ChildItem c:\
 $arrayref = Convertto-MultiArray -InputObject $dir

 .Example
 $range.value2 = (ConvertTo-MultiArray (get-process)).value

 .LINK

http://powertoe.wordpress.com

#>
    param(
        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$true)]
        [PSObject[]]$InputObject
    )
    BEGIN {
        $objects = @()
        [ref]$array = [ref]$null
    }
    Process {
        $objects += $InputObject
    }
    END {
        $properties = $objects[0].psobject.properties |%{$_.name}
        $array.Value = New-Object 'object[,]' ($objects.Count+1),$properties.count
        # i = row and j = column
        $j = 0
        $properties |%{
            $array.Value[0,$j] = $_.tostring()
            $j++
        }
        $i = 1
        $objects |% {
            $item = $_
            $j = 0
            $properties | % {
                if ($item.($_) -eq $null) {
                    $array.value[$i,$j] = ""
                }
                else {
                    $array.value[$i,$j] = $item.($_).tostring()
                }
                $j++
            }
            $i++
        }
        $array
    }
}

Function Format-HTMLTable 
{
    <# 
    .SYNOPSIS 
        Format-HTMLTable - Selectively color elements of of an html table based on column value or even/odd rows.
     
    .DESCRIPTION 
        Create an html table and colorize individual cells or rows of an array of objects 
        based on row header and value. Optionally, you can also modify an existing html 
        document or change only the styles of even or odd rows.
     
    .PARAMETER InputObject 
        An array of objects (ie. (Get-process | select Name,Company) 
     
    .PARAMETER  Column 
        The column you want to modify. (Note: If the parameter ColorizeMethod is not set to ByValue the 
        Column parameter is ignored)

    .PARAMETER ScriptBlock
        Used to perform custom cell evaluations such as -gt -lt or anything else you need to check for in a
        table cell element. The scriptblock must return either $true or $false and is, by default, just
        a basic -eq comparisson. You must use the variables as they are used in the following example.
        (Note: If the parameter ColorizeMethod is not set to ByValue the ScriptBlock parameter is ignored)

        [scriptblock]$scriptblock = {[int]$args[0] -gt [int]$args[1]}

        $args[0] will be the cell value in the table
        $args[1] will be the value to compare it to

        Strong typesetting is encouraged for accuracy.

    .PARAMETER  ColumnValue 
        The column value you will modify if ScriptBlock returns a true result. (Note: If the parameter 
        ColorizeMethod is not set to ByValue the ColumnValue parameter is ignored).
     
    .PARAMETER  Attr 
        The attribute to change should ColumnValue be found in the Column specified. 
        - A good example is using "style" 

    .PARAMETER  AttrValue 
        The attribute value to set when the ColumnValue is found in the Column specified 
        - A good example is using "background: red;" 
    
    .PARAMETER DontUseLinq
        Use inline C# Linq calls for html table manipulation by default. This is extremely fast but requires .NET 3.5 or above.
        Use this switch to force using non-Linq method (xml) first.
        
    .PARAMETER Fragment
        Return only the HTML table instead of a full document.
    
    .EXAMPLE 
        This will highlight the process name of Dropbox with a red background. 

        $TableStyle = @'
        <title>Process Report</title> 
            <style>             
            BODY{font-family: Arial; font-size: 8pt;} 
            H1{font-size: 16px;} 
            H2{font-size: 14px;} 
            H3{font-size: 12px;} 
            TABLE{border: 1px solid black; border-collapse: collapse; font-size: 8pt;} 
            TH{border: 1px solid black; background: #dddddd; padding: 5px; color: #000000;} 
            TD{border: 1px solid black; padding: 5px;} 
            </style>
        '@

        $tabletocolorize = Get-Process | Select Name,CPU,Handles | ConvertTo-Html -Head $TableStyle
        $colorizedtable = Format-HTMLTable $tabletocolorize -Column "Name" -ColumnValue "Dropbox" -Attr "style" -AttrValue "background: red;" -HTMLHead $TableStyle
        $colorizedtable = Format-HTMLTable $colorizedtable -Attr "style" -AttrValue "background: grey;" -ColorizeMethod 'ByOddRows' -WholeRow:$true
        $colorizedtable = Format-HTMLTable $colorizedtable -Attr "style" -AttrValue "background: yellow;" -ColorizeMethod 'ByEvenRows' -WholeRow:$true
        $colorizedtable | Out-File "$pwd/testreport.html" 
        ii "$pwd/testreport.html"

    .EXAMPLE 
        Using the same $TableStyle variable above this will create a table of top 5 processes by memory usage,
        color the background of a whole row yellow for any process using over 150Mb and red if over 400Mb.

        $tabletocolorize = $(get-process | select -Property ProcessName,Company,@{Name="Memory";Expression={[math]::truncate($_.WS/ 1Mb)}} | Sort-Object Memory -Descending | Select -First 5 ) 

        [scriptblock]$scriptblock = {[int]$args[0] -gt [int]$args[1]}
        $testreport = Format-HTMLTable $tabletocolorize -Column "Memory" -ColumnValue 150 -Attr "style" -AttrValue "background:yellow;" -ScriptBlock $ScriptBlock -HTMLHead $TableStyle -WholeRow $true
        $testreport = Format-HTMLTable $testreport -Column "Memory" -ColumnValue 400 -Attr "style" -AttrValue "background:red;" -ScriptBlock $ScriptBlock -WholeRow $true
        $testreport | Out-File "$pwd/testreport.html" 
        ii "$pwd/testreport.html"

    .NOTES 
        If you are going to convert something to html with convertto-html in powershell v2 there is 
        a bug where the header will show up as an asterick if you only are converting one object property. 

        This script is a modification of something I found by some rockstar named Jaykul at this site
        http://stackoverflow.com/questions/4559233/technique-for-selectively-formatting-data-in-a-powershell-pipeline-and-output-as

        .Net 3.5 or above is a requirement for using the Linq libraries.

    Version Info:
    1.2 - 01/12/2014
        - Changed bool parameters to switch
        - Added DontUseLinq parameter
        - Changed function name to be less goofy sounding
        - Updated the add-type custom namespace from Huddled to CustomLinq
        - Added help messages to fuction parameters.
        - Added xml method for function to use if the linq assemblies couldn't be loaded (slower but still works)
    1.1 - 11/13/2013
        - Removed the explicit definition of Csharp3 in the add-type definition to allow windows 2012 compatibility.
        - Fixed up parameters to remove assumed values
        - Added try/catch around add-type to detect and prevent errors when processing on systems which do not support
          the linq assemblies.
    .LINK 
        http://www.the-little-things.net 
    #> 
    [CmdletBinding( DefaultParameterSetName = "StringSet")] 
    param ( 
        [Parameter( Position=0,
                    Mandatory=$true, 
                    ValueFromPipeline=$true, 
                    ParameterSetName="ObjectSet",
                    HelpMessage="Array of psobjects to convert to an html table and modify.")]
        [Object[]]
        $InputObject,
        
        [Parameter( Position=0, 
                    Mandatory=$true, 
                    ValueFromPipeline=$true, 
                    ParameterSetName="StringSet",
                    HelpMessage="HTML table to modify.")] 
        [string]
        $InputString='',
        
        [Parameter( HelpMessage="Column name to compare values against when updating the table by value.")]
        [string]
        $Column="Name",
        
        [Parameter( HelpMessage="Value to compare when updating the table by value.")]
        $ColumnValue=0,
        
        [Parameter( HelpMessage="Custom script block for table conditions to search for when updating the table by value.")]
        [scriptblock]
        $ScriptBlock = {[string]$args[0] -eq [string]$args[1]}, 
        
        [Parameter( Mandatory=$true,
                    HelpMessage="Attribute to append to table element.")] 
        [string]
        $Attr,
        
        [Parameter( Mandatory=$true,
                    HelpMessage="Value to assign to attribute.")] 
        [string]
        $AttrValue,
        
        [Parameter( HelpMessage="By default the td element (individual table cell) is modified. This switch causes the attributes for the entire row (tr) to update instead.")] 
        [switch]
        $WholeRow,
        
        [Parameter( HelpMessage="If an array of object is converted to html prior to modification this is the head data which will get prepended to it.")]
        [string]
        $HTMLHead='<title>HTML Table</title>',
        
        [Parameter( HelpMessage="Method for table modification. ByValue uses column name lookups. ByEvenRows/ByOddRows are exactly as they sound.")]
        [ValidateSet('ByValue','ByEvenRows','ByOddRows')]
        [string]
        $ColorizeMethod='ByValue',
        
        [Parameter( HelpMessage="Use inline C# Linq calls for html table manipulation by default. Extremely fast but requires .NET 3.5 or above to work. Use this switch to force using non-Linq method (xml) first.")] 
        [switch]
        $DontUseLinq,
        
        [Parameter( HelpMessage="Return only the html table element.")] 
        [switch]
        $Fragment
        )
    
    BEGIN 
    {
        $LinqAssemblyLoaded = $false
        if (-not $DontUseLinq)
        {
            # A little note on Add-Type, this adds in the assemblies for linq with some custom code. The first time this 
            # is run in your powershell session it is compiled and loaded into your session. If you run it again in the same
            # session and the code was not changed at all, powershell skips the command (otherwise recompiling code each time
            # the function is called in a session would be pretty ineffective so this is by design). If you make any changes
            # to the code, even changing one space or tab, it is detected as new code and will try to reload the same namespace
            # which is not allowed and will cause an error. So if you are debugging this or changing it up, either change the
            # namespace as well or exit and restart your powershell session.
            #
            # And some notes on the actual code. It is my first jump into linq (or C# for that matter) so if it looks not so 
            # elegant or there is a better way to do this I'm all ears. I define four methods which names are self-explanitory:
            # - GetElementByIndex
            # - GetElementByValue
            # - GetOddElements
            # - GetEvenElements
            $LinqCode = @"
            public static System.Collections.Generic.IEnumerable<System.Xml.Linq.XElement> GetElementByIndex(System.Xml.Linq.XContainer doc, System.Xml.Linq.XName element, int index)
            {
                return doc.Descendants(element)
                        .Where  (e => e.NodesBeforeSelf().Count() == index)
                        .Select (e => e);
            }
            public static System.Collections.Generic.IEnumerable<System.Xml.Linq.XElement> GetElementByValue(System.Xml.Linq.XContainer doc, System.Xml.Linq.XName element, string value)
            {
                return  doc.Descendants(element) 
                        .Where  (e => e.Value == value)
                        .Select (e => e);
            }
            public static System.Collections.Generic.IEnumerable<System.Xml.Linq.XElement> GetOddElements(System.Xml.Linq.XContainer doc, System.Xml.Linq.XName element)
            {
                return doc.Descendants(element)
                        .Where  ((e,i) => i % 2 != 0)
                        .Select (e => e);
            }
            public static System.Collections.Generic.IEnumerable<System.Xml.Linq.XElement> GetEvenElements(System.Xml.Linq.XContainer doc, System.Xml.Linq.XName element)
            {
                return doc.Descendants(element)
                        .Where  ((e,i) => i % 2 == 0)
                        .Select (e => e);
            }
"@
            try
            {
                Add-Type -ErrorAction SilentlyContinue `
                -ReferencedAssemblies System.Xml, System.Xml.Linq `
                -UsingNamespace System.Linq `
                -Name XUtilities `
                -Namespace CustomLinq `
                -MemberDefinition $LinqCode
                
                $LinqAssemblyLoaded = $true
            }
            catch
            {
                $LinqAssemblyLoaded = $false
            }
        }
        $tablepattern = [regex]'(?s)(<table.*?>.*?</table>)'
        $headerpattern = [regex]'(?s)(^.*?)(?=<table)'
        $footerpattern = [regex]'(?s)(?<=</table>)(.*?$)'
        $header = ''
        $footer = ''
    }
    PROCESS 
    { }
    END 
    { 
        if ($psCmdlet.ParameterSetName -eq 'ObjectSet')
        {
            # If we sent an array of objects convert it to html first
            $InputString = ($InputObject | ConvertTo-Html -Head $HTMLHead)
        }

        # Convert our data to x(ht)ml 
        if ($LinqAssemblyLoaded)
        {
            $xml = [System.Xml.Linq.XDocument]::Parse("$InputString")
        }
        else
        {
            # old school xml is kinda dumb so we strip out only the table to work with then 
            # add the header and footer back on later.
            $firsttable = [Regex]::Match([string]$InputString, $tablepattern).Value
            $header = [Regex]::Match([string]$InputString, $headerpattern).Value
            $footer = [Regex]::Match([string]$InputString, $footerpattern).Value
            [xml]$xml = [string]$firsttable
        }
        switch ($ColorizeMethod) {
            "ByEvenRows" {
                if ($LinqAssemblyLoaded)
                {
                    $evenrows = [CustomLinq.XUtilities]::GetEvenElements($xml, "{http://www.w3.org/1999/xhtml}tr")    
                    foreach ($row in $evenrows)
                    {
                        $row.SetAttributeValue($Attr, $AttrValue)
                    }
                }
                else
                {
                    $rows = $xml.GetElementsByTagName('tr')
                    for($i=0;$i -lt $rows.count; $i++)
                    {
                        if (($i % 2) -eq 0 ) {
                           $newattrib=$xml.CreateAttribute($Attr)
                           $newattrib.Value=$AttrValue
                           [void]$rows.Item($i).Attributes.Append($newattrib)
                        }
                    }
                }
            }
            "ByOddRows" {
                if ($LinqAssemblyLoaded)
                {
                    $oddrows = [CustomLinq.XUtilities]::GetOddElements($xml, "{http://www.w3.org/1999/xhtml}tr")    
                    foreach ($row in $oddrows)
                    {
                        $row.SetAttributeValue($Attr, $AttrValue)
                    }
                }
                else
                {
                    $rows = $xml.GetElementsByTagName('tr')
                    for($i=0;$i -lt $rows.count; $i++)
                    {
                        if (($i % 2) -ne 0 ) {
                           $newattrib=$xml.CreateAttribute($Attr)
                           $newattrib.Value=$AttrValue
                           [void]$rows.Item($i).Attributes.Append($newattrib)
                        }
                    }
                }
            }
            "ByValue" {
                if ($LinqAssemblyLoaded)
                {
                    # Find the index of the column you want to format 
                    $ColumnLoc = [CustomLinq.XUtilities]::GetElementByValue($xml, "{http://www.w3.org/1999/xhtml}th",$Column) 
                    $ColumnIndex = $ColumnLoc | Foreach-Object{($_.NodesBeforeSelf() | Measure-Object).Count} 
            
                    # Process each xml element based on the index for the column we are highlighting 
                    switch([CustomLinq.XUtilities]::GetElementByIndex($xml, "{http://www.w3.org/1999/xhtml}td", $ColumnIndex)) 
                    { 
                        {$(Invoke-Command $ScriptBlock -ArgumentList @($_.Value, $ColumnValue))} {
                            if ($WholeRow)
                            {
                                $_.Parent.SetAttributeValue($Attr, $AttrValue)
                            }
                            else
                            {
                                $_.SetAttributeValue($Attr, $AttrValue)
                            }
                        }
                    }
                }
                else
                {
                    $colvalindex = 0
                    $headerindex = 0
                    $xml.GetElementsByTagName('th') | Foreach {
                        if ($_.'#text' -eq $Column) 
                        {
                            $colvalindex=$headerindex
                        }
                        $headerindex++
                    }
                    $rows = $xml.GetElementsByTagName('tr')
                    $cols = $xml.GetElementsByTagName('td')
                    $colvalindexstep = ($cols.count /($rows.count - 1))
                    for($i=0;$i -lt $rows.count; $i++)
                    {
                        $index = ($i * $colvalindexstep) + $colvalindex
                        $colval = $cols.Item($index).'#text'
                        if ($(Invoke-Command $ScriptBlock -ArgumentList @($colval, $ColumnValue))) {
                            $newattrib=$xml.CreateAttribute($Attr)
                            $newattrib.Value=$AttrValue
                            if ($WholeRow)
                            {
                                [void]$rows.Item($i).Attributes.Append($newattrib)
                            }
                            else
                            {
                                [void]$cols.Item($index).Attributes.Append($newattrib)
                            }
                        }
                    }
                }
            }
        }
        if ($LinqAssemblyLoaded)
        {
            if ($Fragment)
            {
                [string]$htmlresult = $xml.Document.ToString()
                if ([string]$htmlresult -match $tablepattern)
                {
                    [string]$matches[0]
                }
            }
            else
            {
                [string]$xml.Document.ToString()
            }
        }
        else
        {
            if ($Fragment)
            {
                [string]($xml.OuterXml | Out-String)
            }
            else
            {
                [string]$htmlresult = $header + ($xml.OuterXml | Out-String) + $footer
                return $htmlresult
            }
        }
    }
}

Function Add-Zip
{
    param([string]$zipfilename)

    if(-not (test-path($zipfilename)))
    {
        set-content $zipfilename ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18))
        (dir $zipfilename).IsReadOnly = $false  
    }

    $shellApplication = new-object -com shell.application
    $zipPackage = $shellApplication.NameSpace($zipfilename)

    foreach($file in $input) 
    { 
            $zipPackage.CopyHere($file.FullName)
            Start-sleep -milliseconds 500
    }
}

Function New-ZipFile
{
    #.Synopsis
    #  Expand a zip file, ensuring it's contents go to a single folder ...
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        $ZipFilePath,

        [Parameter(Position=1, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias("PSPath","Item")]
        [string[]]
        $InputObject = $Pwd,

        [switch]
        $Append,

        # The compression level (defaults to Optimal):
        #   Optimal - The compression operation should be optimally compressed, even if the operation takes a longer time to complete.
        #   Fastest - The compression operation should complete as quickly as possible, even if the resulting file is not optimally compressed.
        #   NoCompression - No compression should be performed on the file.
        [System.IO.Compression.CompressionLevel]$Compression = "Optimal"
    )
    BEGIN
    {
        # Make sure the folder already exists
        [string]$File = Split-Path $ZipFilePath -Leaf
        [string]$Folder = $(if($Folder = Split-Path $ZipFilePath) { Resolve-Path $Folder } else { $Pwd })
        $ZipFilePath = Join-Path $Folder $File
        # If they don't want to append, make sure the zip file doesn't already exist.
        if(!$Append) 
        {
            if(Test-Path $ZipFilePath) 
            { 
                Remove-Item $ZipFilePath 
            }
        }
        $Archive = [System.IO.Compression.ZipFile]::Open( $ZipFilePath, "Update" )
    }
    PROCESS
    {
        foreach($path in $InputObject) 
        {
            foreach($item in Resolve-Path $path) 
            {
                # Push-Location so we can use Resolve-Path -Relative 
                Push-Location (Split-Path $item)
                # This will get the file, or all the files in the folder (recursively)
                foreach($file in Get-ChildItem $item -Recurse -File -Force | % FullName) 
                {
                    # Calculate the relative file path
                    $relative = (Resolve-Path $file -Relative).TrimStart(".\")
                    # Add the file to the zip
                    $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $file, $relative, $Compression)
                }
                Pop-Location
            }
        }
    }
    END
    {
        $Archive.Dispose()
        Get-Item $ZipFilePath
    }
}
#endregion Functions - Serial or Utility

#region Big-IP Functions
Function Get-BigIPLTMReportInformation
{
    [CmdletBinding()]
    param
    (
        [Parameter( HelpMessage="The custom report hash variable structure you plan to report upon")]
        $ReportContainer,
        [Parameter( HelpMessage="A sorted hash of enabled report elements.")]
        $SortedRpts
    )
    BEGIN
    {
        function Do-BigIPInitialize()
        {
          if ( (Get-PSSnapin | Where-Object { $_.Name -eq "iControlSnapIn"}) -eq $null )
          {
            Add-PSSnapIn iControlSnapIn
          }
          $success = Initialize-F5.iControl -HostName $BIGIP_DEVICE -Credentials $BIGIP_CREDs
          
          if ( $BIGIP_RECURSE )
          {
            $oldstate = (Get-F5.iControl).SystemSession.get_recursive_query_state();
            (Get-F5.iControl).SystemSession.set_recursive_query_state("STATE_ENABLED");
          }
          return $success;
        }
        
        function Convert-To64Bit()
        {
          param($high, $low);  
            
          $low = [Convert]::ToString($low,2).PadLeft(32,'0')  
          if($low.length -eq "64")  
          {  
            $low = $low.substring(32,32)  
          }  
             
          return [Convert]::ToUint64([Convert]::ToString($high,2).PadLeft(32,'0')+$low,2);  
        }

        function Extract-Statistic()
        {
          param($StatisticA, $type);
          $value = -1;
          
          foreach($Statistic in $StatisticA)
          { 
            if ( $Statistic.type -eq $type )
            {
              $value = Convert-To64Bit $Statistic.value.high $Statistic.value.low;
              break;
            }
          }
          return $value;
        }
        
        $verbose_timer = $verbose_starttime = Get-Date
        $VirtualServers = @()
        $PoolList = @()
        $PoolMemberList = @()
    }
    PROCESS
    {}
    END
    {
        if ( Do-BigIPInitialize )
        {
#            #region Devices
#            $Failover = (Get-F5.iControl).SystemFailover
#            $DeviceRedundant = $false
#            if ($Failover.is_redundant())
#            {
#                $DeviceRedundant = $true
#                $FailoverMode = $Failover.get_failover_mode() -replace 'FAILOVER_MODE_', ''
#                $FailoverState = $Failover.get_failover_state() -replace 'FAILOVER_STATE', ''
#            }
#            #endregion Devices
            
            #region Virtual Servers
            $vs_list = (Get-F5.iControl).LocalLBVirtualServer.get_list()
            foreach ($vs in $vs_list)
            {
                $vsstatus = (Get-F5.iControl).LocalLBVirtualServer.get_object_status($vs)
                $vs_dest  = ((Get-F5.iControl).LocalLBVirtualServer.get_destination($vs))[0]
                $partition,$vsname = $vs -split "\/(?=[^\/]+?$)"
                $VSProps = @{
                    'virtualserver' = $vsname
                    'partition' = $partition
                    'pool' = ((-join (Get-F5.iControl).LocalLBVirtualServer.get_default_pool_name($vs)) -split "\/(?=[^\/]+?$)")[1]
                    'address' = $vs_dest.address
                    'port' = $vs_dest.port
                    'rules' = @(((Get-F5.iControl).LocalLBVirtualServer.get_rule($vs)).rule_name | %{ ($_ -split "\/(?=[^\/]+?$)")[1]})
                    'protocol' = (-join ((Get-F5.iControl).LocalLBVirtualServer.get_protocol($vs)) -split "\/(?=[^\/]+?$)")[1] -replace 'PROTOCOL_',''
                    'persistenceprofile' = (-join ((Get-F5.iControl).LocalLBVirtualServer.get_persistence_profile($vs)).profile_name -split "\/(?=[^\/]+?$)")[1]
                    'availability' = $vsstatus.availability_status -replace 'AVAILABILITY_STATUS_',''
                    'enabled' = $vsstatus.enabled_status -replace 'ENABLED_STATUS_',''
                    'description' = $vsstatus.status_description            
                }
                $VirtualServers += New-Object psobject -Property $VSProps
            }
            Write-Verbose -Message ('Get-BigIPLTMReportInformation {0}: Virtual Servers Info - {1}' -f $BIGIP_DEVICE,$((New-TimeSpan $verbose_timer ($verbose_timer = get-date)).totalseconds))
            #endregion Virtual Servers

            #region Pools
            $pool_list = (Get-F5.iControl).LocalLBPool.get_list()
            foreach ($pool in $pool_list)
            {
                $poolstatus = (Get-F5.iControl).LocalLBPool.get_object_status($pool)
                $poolactivemembercount = ((Get-F5.iControl).LocalLBPool.get_active_member_count($pool))[0]
                $partition,$poolname = $pool -split "\/(?=[^\/]+?$)"
                
                # Get our pool information
                $PoolListProps = @{
                    'pool' = $poolname
                    'partition' = $partition
                    'activepoolmembers' = $poolactivemembercount
                    'lbmethod' = ((-join (Get-F5.iControl).LocalLBPool.get_lb_method($pool)) -replace 'LB_METHOD_','')
                    'availability' = $poolstatus.availability_status -replace 'AVAILABILITY_STATUS_',''
                    'enabled' = $poolstatus.enabled_status -replace 'ENABLED_STATUS_',''
                    'description' = $poolstatus.status_description
                }
                $PoolList += New-Object psobject -Property $PoolListProps
                
                # Now get the member information
                $poolmembers = (Get-F5.iControl).LocalLBPoolMember.get_object_status((,$pool))
                Foreach ($poolmember in $poolmembers[0])
                {
                    $member = $poolmember.member
                    $poolmemberstatus = $poolmember.object_status
                    $MemberDefAofA = New-Object -TypeName "iControl.CommonIPPortDefinition[][]" 1,1
                    $MemberDefAofA[0][0] = $member;
                    $poolmemberstats = ((Get-F5.iControl).LocalLBPoolMember.get_statistics((,$pool), $MemberDefAofA)).statistics

                   # $poolmemberstats = ((Get-F5.iControl).LocalLBNodeAddress.get_statistics($member.address)).statistics
                    $PoolMemberProps = @{
                        'pool' = $poolname
                        'address' = $member.address
                        'port' = $member.port
                        'availability' = $poolmemberstatus.availability_status -replace 'AVAILABILITY_STATUS_',''
                        'enabled' = $poolmemberstatus.enabled_status -replace 'ENABLED_STATUS_',''                        
                        'description' = $poolmemberstatus.status_description
                        'totalconnections' = Extract-Statistic $poolmemberstats[0].statistics "STATISTIC_SERVER_SIDE_TOTAL_CONNECTIONS"
                        'currentconnections' = Extract-Statistic $poolmemberstats[0].statistics "STATISTIC_SERVER_SIDE_CURRENT_CONNECTIONS"
                        'bytes_in' = Extract-Statistic $poolmemberstats[0].statistics 'STATISTIC_SERVER_SIDE_BYTES_IN'
                    }
                    $PoolMemberList += New-Object psobject -Property $PoolMemberProps
                }
            }
            Write-Verbose -Message ('Get-BigIPLTMReportInformation {0}: Pool Info - {1}' -f $BIGIP_DEVICE,$((New-TimeSpan $verbose_timer ($verbose_timer = get-date)).totalseconds))
            #endregion Pools
            
#            #region Persistence Profiles
#            $perfprofs = (Get-F5.iControl).LocalLBProfilePersistence.get_list()
#            Foreach ($perfprop in $perfprops)
#            {
#                $mode = (Get-F5.iControl).LocalLBProfilePersistence.get_persistence_mode($perfprop).value -replace 'PERSISTENCE_MODE_',''
#                $cookiemethod = (Get-F5.iControl).LocalLBProfilePersistence.get_cookie_persistence_method($perfprop).value -replace 'COOKIE_PERSISTENCE_METHOD_',''
#            }
#            Write-Verbose -Message ('Get-BigIPLTMReportInformation {0}: Persistence Profile Info - {1}' -f $BIGIP_DEVICE,$((New-TimeSpan $verbose_timer ($verbose_timer = get-date)).totalseconds))
#            #endregion Persistence Profiles
        
            #region Populate Data
            Write-Verbose -Message ('Get-BigIPLTMReportInformation {0}: Section Data - {1}' -f $BIGIP_DEVICE,$((New-TimeSpan $verbose_timer ($verbose_timer = get-date)).totalseconds))
            $SortedRpts | %{ 
                switch ($_.Section) {
                    'VirtualServerSummary' {
                        $ReportContainer['Sections'][$_]['AllData'][$BIGIP_DEVICE] = 
                            @($VirtualServers | Sort-Object -Property virtualserver)
                    }
                    'VirtualServerDetails' {
                        $ReportContainer['Sections'][$_]['AllData'][$BIGIP_DEVICE] = 
                            @($VirtualServers | Sort-Object -Property virtualserver)
                    }
                    'Pools' {
                        $ReportContainer['Sections'][$_]['AllData'][$BIGIP_DEVICE] = 
                            @($PoolList | Sort-Object -Property pool)
                    }
                    'PoolMembers' {
                        $ReportContainer['Sections'][$_]['AllData'][$BIGIP_DEVICE] = 
                            @($PoolMemberList | Sort-Object -Property pool)
                    }
                }
            }
            #endregion Populate Data

            # We need to return something to base the rest of the report around, may as well return the device we connected to
            Return $BIGIP_DEVICE
            Write-Verbose -Message ('Get-BigIPLTMReportInformation {0}: Finished - {1}' -f $BIGIP_DEVICE,$((New-TimeSpan $verbose_timer ($verbose_timer = get-date)).totalseconds))
        }
    }
}
#endregion Big-IP Functions

#region Functions - Asset Report Project
Function Create-ReportSection
{
    #** This function is specific to this script and does all kinds of bad practice
    #   stuff. Use this function neither to learn from or judge me please. **
    #
    #   That being said, this function pretty much does all the report output
    #   options and layout magic. It depends upon the report layout hash and
    #   $HTMLRendering global variable hash.
    #
    #   This function generally shouldn't need to get changed in any way to customize your
    #   reports.
    #
    # .EXAMPLE
    #    Create-ReportSection -Rpt $ReportSection -Asset $Asset 
    #                         -Section 'Summary' -TableTitle 'System Summary'
    
    [CmdletBinding()]
    param(
        [parameter()]
        $Rpt,
        
        [parameter()]
        [string]$Asset,

        [parameter()]
        [string]$Section,
        
        [parameter()]
        [string]$TableTitle        
    )
    BEGIN
    {
        Add-Type -AssemblyName System.Web
    }
    PROCESS
    {}
    END
    {
        # Get our section type
        $RptSection = $Rpt['Sections'][$Section]
        $SectionType = $RptSection['Type']
        
        switch ($SectionType)
        {
            'Section'     # default to a data section
            {
                Write-Verbose -Message ('Create-ReportSection: {0}: {1}' -f $Asset,$Section)
                $ReportElementSource = @($RptSection['AllData'][$Asset])
                if ((($ReportElementSource.Count -gt 0) -and 
                     ($ReportElementSource[0] -ne $null)) -or 
                     ($RptSection['ShowSectionEvenWithNoData']))
                {
                    $SourceProperties = $RptSection['ReportTypes'][$ReportType]['Properties']
                    
                    #region report section type and layout
                    $TableType = $RptSection['ReportTypes'][$ReportType]['TableType']
                    $ContainerType = $RptSection['ReportTypes'][$ReportType]['ContainerType']

                    switch ($TableType)
                    {
                        'Horizontal' 
                        {
                            $PropertyCount = $SourceProperties.Count
                            $Vertical = $false
                        }
                        'Vertical' {
                            $PropertyCount = 2
                            $Vertical = $true
                        }
                        default {
                            if ((($SourceProperties.Count) -ge $HorizontalThreshold))
                            {
                                $PropertyCount = 2
                                $Vertical = $true
                            }
                            else
                            {
                                $PropertyCount = $SourceProperties.Count
                                $Vertical = $false
                            }
                        }
                    }
                    #endregion report section type and layout
                    
                    $Table = ''
                    If ($PropertyCount -ne 0)
                    {
                        # Create our future HTML table header
                        $SectionLink = '<a href="{0}"></a>' -f $Section
                        $TableHeader = $HTMLRendering['TableTitle'][$HTMLMode] -replace '<0>',$PropertyCount
                        $TableHeader = $SectionLink + ($TableHeader -replace '<1>',$TableTitle)

                        if ($RptSection.ContainsKey('Comment'))
                        {
                            if ($RptSection['Comment'] -ne $false)
                            {
                                $TableComment = $HTMLRendering['TableComment'][$HTMLMode] -replace '<0>',$PropertyCount
                                $TableComment = $TableComment -replace '<1>',$RptSection['Comment']
                                $TableHeader = $TableHeader + $TableComment
                            }
                        }
                        
                        $AllTableElements = @()
                        Foreach ($TableElement in $ReportElementSource)
                        {
                            $AllTableElements += $TableElement | Select $SourceProperties
                        }

                        # If we are creating a vertical table it takes a bit of transformational work
                        if ($Vertical)
                        {
                            $Count = 0
                            foreach ($Element in $AllTableElements)
                            {
                                $Count++
                                $SingleElement = [string]($Element | ConvertTo-PropertyValue | ConvertTo-Html)
                                if ($Rpt['Configuration']['PostProcessingEnabled'])
                                {
                                    # Add class elements for even/odd rows
                                    $SingleElement = Format-HTMLTable $SingleElement -ColorizeMethod 'ByEvenRows' -Attr 'class' -AttrValue 'even' -WholeRow
                                    $SingleElement = Format-HTMLTable $SingleElement -ColorizeMethod 'ByOddRows' -Attr 'class' -AttrValue 'odd' -WholeRow
                                    if ($RptSection.ContainsKey('PostProcessing') -and 
                                       ($RptSection['PostProcessing'].Value -ne $false))
                                    {
                                        $Rpt['Configuration']['PostProcessingEnabled'].Value
                                        $Table = $(Invoke-Command ([scriptblock]::Create($RptSection['PostProcessing'])))
                                    }
                                }
                                $SingleElement = [Regex]::Match($SingleElement, "(?s)(?<=</tr>)(.+)(?=</table>)").Value
                                $Table += $SingleElement 
                                if ($Count -ne $AllTableElements.Count)
                                {
                                    $Table += '<tr class="divide"><td></td><td></td></tr>'
                                }
                            }
                            $Table = '<table class="list">' + $TableHeader + $Table + '</table>'
                            $Table = [System.Web.HttpUtility]::HtmlDecode($Table)
                        }
                        # Otherwise it is a horizontal table
                        else
                        {
                            [string]$Table = $AllTableElements | ConvertTo-Html
                            if ($Rpt['Configuration']['PostProcessingEnabled'])
                            {
                                # Add class elements for even/odd rows
                                $Table = Format-HTMLTable $Table -ColorizeMethod 'ByEvenRows' -Attr 'class' -AttrValue 'even' -WholeRow
                                $Table = Format-HTMLTable $Table -ColorizeMethod 'ByOddRows' -Attr 'class' -AttrValue 'odd' -WholeRow
                                if ($RptSection.ContainsKey('PostProcessing'))
                                
                                {
                                    if ($RptSection.ContainsKey('PostProcessing'))
                                    {
                                        if ($RptSection['PostProcessing'] -ne $false)
                                        {
                                            $Table = $(Invoke-Command ([scriptblock]::Create($RptSection['PostProcessing'])))
                                        }
                                    }
                                }
                            }
                            # This will gank out everything after the first colgroup so we can replace it with our own spanned header
                            $Table = [Regex]::Match($Table, "(?s)(?<=</colgroup>)(.+)(?=</table>)").Value
                            $Table = '<table>' + $TableHeader + $Table + '</table>'
                            $Table = [System.Web.HttpUtility]::HtmlDecode(($Table))
                        }
                    }
                    
                    $Output = $HTMLRendering['SectionContainers'][$HTMLMode][$ContainerType]['Head'] + 
                              $Table + $HTMLRendering['SectionContainers'][$HTMLMode][$ContainerType]['Tail']
                    $Output
                }
            }
            'SectionBreak'
            {
                if ($Rpt['Configuration']['SkipSectionBreaks'] -eq $false)
                {
                    $Output = $HTMLRendering['CustomSections'][$SectionType] -replace '<0>',$TableTitle
                    $Output
                }
            }
        }
    }
}

Function New-ReportDelivery
{
    [CmdletBinding()]
    param
    (
        [Parameter( HelpMessage="Report body, typically in HTML format", ValueFromPipeline=$true )]
        [string[]]
        $Report,
        
        [Parameter( ParameterSetName="EmailReport", HelpMessage="Send email of resulting report?")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]                    
        [switch]
        $SendMail,
        
        [Parameter( ParameterSetName="EmailReport", HelpMessage="Email server to relay report through")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [string]
        $EmailRelay = ".",
        
        [Parameter( ParameterSetName="EmailReport", HelpMessage="Email sender")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [string]
        $EmailSender='systemreport@localhost',
        
        [Parameter( ParameterSetName="EmailReport", Mandatory=$true, HelpMessage="Email recipient")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [string]
        $EmailRecipient,
        
        [Parameter( ParameterSetName="EmailReport", HelpMessage="Email subject")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [string]
        $EmailSubject='System Report',
        
        [Parameter( ParameterSetName="EmailReport", HelpMessage="Email report(s) as attachement")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [Parameter( ParameterSetName = "EmailReportAsAttachment")]
        [switch]
        $EmailAsAttachment,
        
        [Parameter( ParameterSetName="EmailReport", HelpMessage="Force email to be sent anonymously?")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [switch]
        $ForceAnonymous,

        [Parameter( ParameterSetName="SaveReport", HelpMessage="Save the report?")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [switch]
        $SaveReport,
        
        [Parameter( ParameterSetName="SaveReport", HelpMessage="Zip the report(s).")]
        [Parameter( ParameterSetName = "EmailAndSaveReport")]
        [Parameter( ParameterSetName = "EmailReportAsAttachment")]
        [switch]
        $ZipReport
    )
    BEGIN
    {
        $Reports = @()      # Save a list of report paths in case we will be emailing as attachments
        if ($SaveReport)
        {
            $ReportFormat = 'HTML'
        }
        if ($SaveAsPDF)
        {
            $PdfGenerator = "$((Get-Location).Path)\NReco.PdfGenerator.dll"
            if (Test-Path $PdfGenerator)
            {
                $ReportFormat = 'PDF'
                $PdfGenerator = "$((Get-Location).Path)\NReco.PdfGenerator.dll"
                $Assembly = [Reflection.Assembly]::LoadFrom($PdfGenerator) #| Out-Null
                $PdfCreator = New-Object NReco.PdfGenerator.HtmlToPdfConverter
            }
        }
    }
    PROCESS
    {
        switch ($ReportFormat) {
            'PDF' {
                $ReportOutput = $PdfCreator.GeneratePdf([string]$Report)
                $ReportName = $ReportName -replace '.html','.pdf'
                Add-Content -Value $ReportOutput `
                            -Encoding byte `
                            -Path ($ReportName)
            }
            'HTML' {
                $Report | Out-File $ReportName
            }
        }
        $Reports += $ReportName
    }
    END
    {
        if ($Sendmail)
        {
            $SendMailSplat = @{
                'From' = $EmailSender
                'To' = $EmailRecipient
                'Subject' = $EmailSubject
                'Priority' = 'Normal'
                'smtpServer' = $EmailRelay
                'BodyAsHTML' = $true
            }
            if ($ForceAnonymous)
            {
                $Pass = ConvertTo-SecureString –String 'anonymous' –AsPlainText -Force
                $Creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "NT AUTHORITY\ANONYMOUS LOGON", $pass
                $SendMailSplat.Credential = $creds

            }
            if ($EmailAsAttachment)
            {
                if ($ZipReport)
                {
                    $ZipName = $ReportName -replace '.html','.zip'
                    $Reports | New-ZipFile -ZipFilePath $ZipName -Append
                }
                else
                {
                    $SendMailSplat.Attachments = $Reports
                }
            }
            else
            {
                $SendMailSplat.Body = $Report
            }
            send-mailmessage @SendMailSplat
        }
    }
}

Function New-ReportOutput
{
    [CmdletBinding()]
    param
    (
        [Parameter( HelpMessage="Report body, typically in HTML format",
                    ValueFromPipeline=$true,
                    Mandatory=$true )]
        [string]
        $Report,
        
        [Parameter( HelpMessage="Save the report as a PDF. If the PDF library is not available the default format, HTML, will be used instead.")]
        [switch]
        $SaveAsPDF,
        
        [Parameter( HelpMessage="Postpend timestamp to file name.")]
        [switch]
        $Postpendtimestamp,
        
        [Parameter( HelpMessage="Prepend timestamp to file name.")]
        [switch]
        $Prependtimestamp,
        
        [Parameter( HelpMessage="If output already exists do not overwrite.")]
        [switch]
        $NoOverwrite,
        
        [Parameter( HelpMessage="If saving the report, what do you want to call it?")]
        [string]
        $ReportName="Report.html",
        
        [Parameter( HelpMessage="Where are you saving the report (defaults to local temp directory)?")]
        [string]
        $ReportPath=$env:Temp
    )
    BEGIN
    {
        $timestamp = Get-Date -Format ddmmyyyy-HHMMss
        if ($Prependtimestamp)
        {
            $ReportName="$timestamp_$($ReportName.Split('.')[0]).$($ReportName.Split('.')[1])"
        }
        if ($Postpendtimestamp)
        {
            $ReportName="$($ReportName.Split('.')[0])_$timestamp.$($ReportName.Split('.')[1])"
        }
        $ReportFormat = 'HTML'
        if ($SaveAsPDF)
        {
            $PdfGenerator = "$((Get-Location).Path)\NReco.PdfGenerator.dll"
            if (Test-Path $PdfGenerator)
            {
                try {
                    $ReportFormat = 'PDF'
                    $PdfGenerator = "$((Get-Location).Path)\NReco.PdfGenerator.dll"
                    $Assembly = [Reflection.Assembly]::LoadFrom($PdfGenerator) #| Out-Null
                    $PdfCreator = New-Object NReco.PdfGenerator.HtmlToPdfConverter
                }
                catch {
                    $ReportFormat = 'HTML'
                }
            }
        }
    }
    PROCESS
    {}
    END
    {
        switch ($ReportFormat) {
            'PDF' {
                $ReportOutput = $PdfCreator.GeneratePdf([string]$Report)
                if ($ReportName -notmatch "\.pdf$") 
                {
                    if ($ReportName -match "\.html{0,1}$") 
                    {
                        $ReportName = [System.Text.RegularExpressions.Regex]::Replace($ReportName,"\.html{0,1}$", '.pdf');
                    }
                    else
                    {
                        $ReportName = "$($ReportName).pdf"
                    }
                }
                if ((Test-Path "$ReportPath\$ReportName") -and $NoOverwrite)
                {
                    $retval = $false
                }
                else
                {
                    Add-Content -Value $ReportOutput `
                                -Encoding byte `
                                -Path ("$ReportPath\$ReportName")
                    $retval = "$ReportPath\$ReportName"
                }
            }
            'HTML' {
                if ($ReportName -notmatch "\.html{0,1}$")
                {
                    if ($ReportName -match "\.pdf$") 
                    {
                        $ReportName = [System.Text.RegularExpressions.Regex]::Replace($ReportName,"\.pdf$", '.html');
                    }
                    else
                    {
                        $ReportName = "$($ReportName).html"
                    }
                }
                if ((Test-Path "$ReportPath\$ReportName") -and $NoOverwrite)
                {
                    $retval = $false
                }
                else
                {
                    $Report | Out-File "$ReportPath\$ReportName"
                    $retval = "$ReportPath\$ReportName"
                }
            }
        }
        return $retval
    }
}

Function New-SelfContainedAssetReport
{
    <#
    .SYNOPSIS
        Generates a new asset report from gathered data.
    .DESCRIPTION
        Generates a new asset report from gathered data. The information 
        gathering routine generates the output root elements.
    .PARAMETER ReportContainer
        The custom report hash vaiable structure you plan to report upon.
    .PARAMETER DontGatherData
        If your report container already has all the data from a prior run and
        you are just creating a different kind of report with the same data, enable this switch
    .PARAMETER ReportType
        The report type.
    .PARAMETER HTMLMode
        The HTML rendering type (DynamicGrid or EmailFriendly).
    .PARAMETER ExportToExcel
        Export an excel document.
    .PARAMETER EmailRelay
        Email server to relay report through.
    .PARAMETER EmailSender
        Email sender.
    .PARAMETER EmailRecipient
        Email recipient.
    .PARAMETER EmailSubject
        Email subject.
    .PARAMETER SendMail
        Send email of resulting report?
    .PARAMETER ForceAnonymous
        Force email to be sent anonymously?
    .PARAMETER SaveReport
        Save the report?
    .PARAMETER SaveAsPDF
        Save the report as a PDF. If the PDF library is not available the default format, HTML, will be used instead.
    .PARAMETER OutputMethod
        If saving the report, will it be one big report or individual reports?
    .PARAMETER ReportName
        If saving the report, what do you want to call it? This is only used if one big report is being generated.
    .PARAMETER ReportNamePrefix
        Prepend an optional prefix to the report name?
    .PARAMETER ReportLocation
        If saving multiple reports, where will they be saved?
    .EXAMPLE
        New-SelfContainedAssetReport -ReportContainer $ADForestReport -ExportToExcel `
            -SaveReport `
            -OutputMethod 'IndividualReport' `
            -HTMLMode 'DynamicGrid'

        Description:
        ------------------
        Create a forest active directory report.
    .NOTES
        Version    : 1.0.0 10/15/2013
                     - First release

        Author     : Zachary Loeber

        Disclaimer : This script is provided AS IS without warranty of any kind. I 
                     disclaim all implied warranties including, without limitation,
                     any implied warranties of merchantability or of fitness for a 
                     particular purpose. The entire risk arising out of the use or
                     performance of the sample scripts and documentation remains
                     with you. In no event shall I be liable for any damages 
                     whatsoever (including, without limitation, damages for loss of 
                     business profits, business interruption, loss of business 
                     information, or other pecuniary loss) arising out of the use of or 
                     inability to use the script or documentation. 

        Copyright  : I believe in sharing knowledge, so this script and its use is 
                     subject to : http://creativecommons.org/licenses/by-sa/3.0/
    .LINK
        http://www.the-little-things.net/
    .LINK
        http://nl.linkedin.com/in/zloeber

    #>

    #region Parameters
    [CmdletBinding()]
    PARAM
    (
        [Parameter(Mandatory=$true,
                   HelpMessage='The custom report hash variable structure you plan to report upon')]
        $ReportContainer,
        
        [Parameter(HelpMessage='Do not gather data, this assumes $Reportcontainer has been pre-populated.')]
        [switch]
        $DontGatherData,
        
        [Parameter( HelpMessage='The report type')]
        [string]
        $ReportType = '',
        
        [Parameter( HelpMessage='The HTML rendering type (DynamicGrid or EmailFriendly)')]
        [ValidateSet('DynamicGrid','EmailFriendly')]
        [string]
        $HTMLMode = 'DynamicGrid',
        
        [Parameter( HelpMessage='Export an excel document as part of the output')]
        [switch]
        $ExportToExcel,
        
        [Parameter( HelpMessage='Skip html/pdf generation, only produce an excel report (if switch is enabled)')]
        [switch]
        $NoReport,
        
        [Parameter( HelpMessage='Email server to relay report through')]
        [string]
        $EmailRelay = '.',
        
        [Parameter( HelpMessage='Email sender')]
        [string]
        $EmailSender='systemreport@localhost',
     
        [Parameter( HelpMessage='Email recipient')]
        [string]
        $EmailRecipient='default@yourdomain.com',
        
        [Parameter( HelpMessage='Email subject')]
        [string]
        $EmailSubject='System Report',
        
        [Parameter( HelpMessage='Send email of resulting report?')]
        [switch]
        $SendMail,
        
        [Parameter( HelpMessage="Force email to be sent anonymously?")]
        [switch]
        $ForceAnonymous,

        [Parameter( HelpMessage='Save the report?')]
        [switch]
        $SaveReport,
        
        [Parameter( HelpMessage='Save the report as a PDF. If the PDF library is not available the default format, HTML, will be used instead.')]
        [switch]
        $SaveAsPDF,

        [Parameter( HelpMessage='Zip up the report(s)?')]
        [switch]
        $ZipReport,
       
        [Parameter( HelpMessage='How to process report output?')]
        [ValidateSet('OneBigReport','IndividualReport','NoReport')]
        [string]
        $OutputMethod='OneBigReport',
        
        [Parameter( HelpMessage='If saving the report, what do you want to call it?')]
        [string]
        $ReportName='Report.html',
        
        [Parameter( HelpMessage='Prepend an optional prefix to the report name?')]
        [string]
        $ReportNamePrefix='',
        
        [Parameter( HelpMessage='If saving multiple reports, where will they be saved?')]
        [string]
        $ReportLocation='.'
    )
    #endregion Parameters
    BEGIN
    {
        # Use this to keep a splat of our CmdletBinding options
        $VerboseDebug=@{}
        If ($PSBoundParameters.ContainsKey('Verbose')) 
        {
            If ($PSBoundParameters.Verbose -eq $true)
            {
                $VerboseDebug.Verbose = $true
            } 
            else 
            {
                $VerboseDebug.Verbose = $false
            }
        }
        If ($PSBoundParameters.ContainsKey('Debug')) 
        {
            If ($PSBoundParameters.Debug -eq $true)
            {
                $VerboseDebug.Debug = $true 
            } 
            else 
            {
                $VerboseDebug.Debug = $false
            }
        }

        $ReportOutputSplat = @{
            'SaveAsPDF' = $SaveAsPDF
        }
        
        # Some basic initialization
        $AssetReports = ''
        $FinishedReportPaths = @()
        
        if (($ReportType -eq '') -or ($ReportContainer['Configuration']['ReportTypes'] -notcontains $ReportType))
        {
            $ReportType = $ReportContainer['Configuration']['ReportTypes'][0]
        }
        # There must be a more elegant way to do this hash sorting but this also allows
        # us to pull a list of only the sections which are defined and need to be generated.
        $SortedReports = @()
        Foreach ($Key in $ReportContainer['Sections'].Keys) 
        {
            if ($ReportContainer['Sections'][$Key]['ReportTypes'].ContainsKey($ReportType))
            {
                if ($ReportContainer['Sections'][$Key]['Enabled'] -and 
                    ($ReportContainer['Sections'][$Key]['ReportTypes'][$ReportType] -ne $false))
                {
                    $_SortedReportProp = @{
                                            'Section' = $Key
                                            'Order' = $ReportContainer['Sections'][$Key]['Order']
                                          }
                    $SortedReports += New-Object -Type PSObject -Property $_SortedReportProp
                }
            }
        }
        $SortedReports = $SortedReports | Sort-Object Order
    }
    PROCESS
    {}
    END 
    {
        # Information Gathering, Your custom script block must return the 
        #   array of strings (keys) which consist of the Root elements of your
        #   desired reports.
        Write-Verbose -Message ('New-SelfContainedAssetReport: Invoking information gathering script...')
        $AssetNames = 
            @(Invoke-Command ([scriptblock]::Create($ReportContainer['Configuration']['PreProcessing'])))

        # if we are to export all data to excel, then we do so per section
        #   then per Asset
        if ($ExportToExcel)
        {
            Write-Verbose -Message ('New-SelfContainedAssetReport: Exporting to excel...')
            # First make sure we have data to export, this shlould also weed out non-data sections meant for html
            #  (like section breaks and such)
            $ProcessExcelReport = $false
            foreach ($ReportSection in $SortedReports)
            {
                if ($ReportContainer['Sections'][$ReportSection.Section]['AllData'].Count -gt 0)
                {
                    $ProcessExcelReport = $true
                }
            }

            #region Excel
            if ($ProcessExcelReport)
            {
                # Create the excel workbook
                try
                {
                    $Excel = New-Object -ComObject Excel.Application -ErrorAction Stop
                    $ExcelExists = $True
                    $Excel.visible = $True
                    #Start-Sleep -s 1
                    $Workbook = $Excel.Workbooks.Add()
                    $Excel.DisplayAlerts = $false
                }
                catch
                {
                    Write-Warning ('Issues opening excel: {0}' -f $_.Exception.Message)
                    $ExcelExists = $False
                }
                if ($ExcelExists)
                {
                    # going through every section, but in reverse so it shows up in the correct
                    #  sheet in excel. 
                    $SortedExcelReports = $SortedReports | Sort-Object Order -Descending
                    Foreach ($ReportSection in $SortedExcelReports)
                    {
                        $SectionData = $ReportContainer['Sections'][$ReportSection.Section]['AllData']
                        $SectionProperties = $ReportContainer['Sections'][$ReportSection.Section]['ReportTypes'][$ReportType]['Properties']
                        
                        # Gather all the asset information in the section (remember that each asset may
                        #  be pointing to an array of psobjects)
                        $TransformedSectionData = @()                        
                        foreach ($asset in $SectionData.Keys)
                        {
                            # Get all of our calculated properties, then add in the asset name
                            $TempProperties = $SectionData[$asset] | Select $SectionProperties
                            $TransformedSectionData += ($TempProperties | Select @{n='AssetName';e={$asset}},*)
                        }
                        if (($TransformedSectionData.Count -gt 0) -and ($TransformedSectionData -ne $null))
                        {
                            $temparray1 = $TransformedSectionData | ConvertTo-MultiArray
                            if ($temparray1 -ne $null)
                            {    
                                $temparray = $temparray1.Value
                                $starta = [int][char]'a' - 1
                                
                                if ($temparray.GetLength(1) -gt 26) 
                                {
                                    $col = [char]([int][math]::Floor($temparray.GetLength(1)/26) + $starta) + [char](($temparray.GetLength(1)%26) + $Starta)
                                } 
                                else 
                                {
                                    $col = [char]($temparray.GetLength(1) + $starta)
                                }
                                
                                Start-Sleep -s 1
                                $xlCellValue = 1
                                $xlEqual = 3
                                $BadColor = 13551615    #Light Red
                                $BadText = -16383844    #Dark Red
                                $GoodColor = 13561798    #Light Green
                                $GoodText = -16752384    #Dark Green
                                $Worksheet = $Workbook.Sheets.Add()
                                $Worksheet.Name = $ReportSection.Section
                                $Range = $Worksheet.Range("a1","$col$($temparray.GetLength(0))")
                                $Range.Value2 = $temparray

                                #Format the end result (headers, autofit, et cetera)
                                [void]$Range.EntireColumn.AutoFit()
                                [void]$Range.FormatConditions.Add($xlCellValue,$xlEqual,'TRUE')
                                $Range.FormatConditions.Item(1).Interior.Color = $GoodColor
                                $Range.FormatConditions.Item(1).Font.Color = $GoodText
                                [void]$Range.FormatConditions.Add($xlCellValue,$xlEqual,'OK')
                                $Range.FormatConditions.Item(2).Interior.Color = $GoodColor
                                $Range.FormatConditions.Item(2).Font.Color = $GoodText
                                [void]$Range.FormatConditions.Add($xlCellValue,$xlEqual,'FALSE')
                                $Range.FormatConditions.Item(3).Interior.Color = $BadColor
                                $Range.FormatConditions.Item(3).Font.Color = $BadText
                                
                                # Header
                                $range = $Workbook.ActiveSheet.Range("a1","$($col)1")
                                $range.Interior.ColorIndex = 19
                                $range.Font.ColorIndex = 11
                                $range.Font.Bold = $True
                                $range.HorizontalAlignment = -4108
                            }
                        }
                    }
                    # Get rid of the blank default worksheets
                    $Workbook.Worksheets.Item("Sheet1").Delete()
                    $Workbook.Worksheets.Item("Sheet2").Delete()
                    $Workbook.Worksheets.Item("Sheet3").Delete()
                }
            }
            #endregion Excel
        }

        foreach ($Asset in $AssetNames)
        {
            # First check if there is any data to report upon for each asset
            $ContainsData = $false
            $SectionCount = 0
            Foreach ($ReportSection in $SortedReports)
            {
                if ($ReportContainer['Sections'][$ReportSection.Section]['AllData'].ContainsKey($Asset))
                {
                    $ContainsData = $true
                }
            }
            
            # If we have any data then we have a report to create
            if ($ContainsData)
            {
                $AssetReport = ''
                $AssetReport += $HTMLRendering['ServerBegin'][$HTMLMode] -replace '<0>',$Asset
                $UsedSections = 0
                $TotalSectionsPerRow = 0
                
                Foreach ($ReportSection in $SortedReports)
                {
                    if ($ReportContainer['Sections'][$ReportSection.Section]['ReportTypes'][$ReportType])
                    {
                        #region Section Calculation
                        # Use this code to track where we are at in section usage
                        #  and create new section groups as needed
                        
                        # Current section type
                        $CurrContainer = $ReportContainer['Sections'][$ReportSection.Section]['ReportTypes'][$ReportType]['ContainerType']
                        
                        # Grab first two digits found in the section container div
                        $SectionTracking = ([Regex]'\d{1}').Matches($HTMLRendering['SectionContainers'][$HTMLMode][$CurrContainer]['Head'])
                        if (($SectionTracking[1].Value -ne $TotalSectionsPerRow) -or `
                            ($SectionTracking[0].Value -eq $SectionTracking[1].Value) -or `
                            (($UsedSections + [int]$SectionTracking[0].Value) -gt $TotalSectionsPerRow) -and `
                            (!$ReportContainer['Sections'][$ReportSection.Section]['ReportTypes'][$ReportType]['SectionOverride']))
                        {
                            $NewGroup = $true
                        }
                        else
                        {
                            $NewGroup = $false
                            $UsedSections += [int]$SectionTracking[0].Value
                            #Write-Verbose -Message ('Report {0}: NOT a new group, Sections used {1}' -f $Asset,$UsedSections)
                        }
                        
                        if ($NewGroup)
                        {
                            if ($UsedSections -ne 0)
                            {
                                $AssetReport += $HTMLRendering['SectionContainerGroup'][$HTMLMode]['Tail']
                            }
                            $AssetReport += $HTMLRendering['SectionContainerGroup'][$HTMLMode]['Head']
                            $UsedSections = [int]$SectionTracking[0].Value
                            $TotalSectionsPerRow = [int]$SectionTracking[1].Value
                            #Write-Verbose -Message ('Report {0}: {1}/{2} Sections Used' -f $Asset,$UsedSections,$TotalSectionsPerRow)
                        }
                        #endregion Section Calculation
                        
                       # Write-Verbose -Message ('Report {0}: HTML Table creation - {1}' -f $Asset,$ReportSection.Section)
                        $AssetReport += Create-ReportSection  -Rpt $ReportContainer `
                                                              -Asset $Asset `
                                                              -Section $ReportSection.Section `
                                                              -TableTitle $ReportContainer['Sections'][$ReportSection.Section]['Title']
                    }
                }
                
                $AssetReport += $HTMLRendering['SectionContainerGroup'][$HTMLMode]['Tail']
                $AssetReport += $HTMLRendering['ServerEnd'][$HTMLMode]
                $AssetReports += $AssetReport
                
            }
            # If we are creating per-asset reports then create one now, otherwise keep going
            if (($OutputMethod -eq 'IndividualReport') -and ($AssetReports -ne ''))
            {
                $ReportOutputSplat.Report = ($HTMLRendering['Header'][$HTMLMode] -replace '<0>','$Asset') + 
                                            $AssetReports + 
                                            $HTMLRendering['Footer'][$HTMLMode]
                $ReportOutputSplat.ReportName = $ReportNamePrefix + $Asset + '.html'
                $ReportOutputSplat.ReportPath = $ReportLocation
        
                $FinishedReportPath = New-ReportOutput @ReportOutputSplat
                if ($FinishedReportPath -ne $false)
                {
                    $FinishedReportPaths += $FinishedReportPath
                }
                $AssetReports = ''
            }
        }
        
        # If one big report is getting sent/saved do so now
        if (($OutputMethod -eq 'OneBigReport') -and ($AssetReports -ne ''))
        {
            $FullReport = ($HTMLRendering['Header'][$HTMLMode] -replace '<0>',$Asset) + 
                           $AssetReports + 
                           $HTMLRendering['Footer'][$HTMLMode]
            $ReportOutputSplat.ReportName = $ReportName
            $ReportOutputSplat.ReportPath = $ReportLocation
            $ReportOutputSplat.Report = ($HTMLRendering['Header'][$HTMLMode] -replace '<0>','Multiple Systems') + 
                                                $AssetReports + 
                                                $HTMLRendering['Footer'][$HTMLMode]
            $FinishedReportPath = New-ReportOutput @ReportOutputSplat
            if ($FinishedReportPath -ne $false)
            {
                $FinishedReportPaths += $FinishedReportPath
            }
        }
        
        if ($ZipReport)
        {
            $ZipReportName = "$($ReportOutputSplat.ReportName).zip"
            $FinishedReportPaths | Add-Zip $ZipReportName
            $FinishedReportPaths | Remove-Item
            $FinishedReportPaths = @($ZipReportName)
        }
        if ($SendMail)
        {
            $ReportDeliverySplat = @{
                'EmailSender' = $EmailSender
                'EmailRecipient' = $EmailRecipient
                'EmailSubject' = $EmailSubject
                'EmailRelay' = $EmailRelay
                'SendMail' = $SendMail
                'ForceAnonymous' = $ForceAnonymous
            }
            
            if ($ZipReport -or ($FinishedReportPaths.Count -gt 1))
            {}
            New-ReportDelivery @ReportDeliverySplat
        }
    }
}
#endregion Functions - Asset Report Project

#region Main
$verbosesplat = @{}
if ($Verbosity)
{
    $verbosesplat.Verbose = $true
}
switch ($ReportFormat) {
	'HTML' {
        # Create a new big-ip ltm report and save it to html. For the best results
        # make certain that linq components are available (.net 3.5 sp2 or greater I believe).
        New-SelfContainedAssetReport `
                -ReportContainer $BigIPLTMReport `
                -SaveReport `
                -ReportNamePrefix 'bigip_' `
                -OutputMethod 'IndividualReport' `
                @verbosesplat
	}
	'Excel' {
        # Create a new big-ip ltm report and export all the results to excel
        # (obviously needs office 2007 or greater installed). The report does not
        # save by default.
        New-SelfContainedAssetReport `
                -ReportContainer $BigIPLTMReport `
                -ReportType 'ExcelExport' `
                -ExportToExcel `
                -NoReport `
                @verbosesplat
	}
    'Custom' {
        # Fill this out as you see fit
	}
}
#endregion Main