﻿function Format-ScriptReplaceHereStrings {
    <#
    .SYNOPSIS
    Replace here strings with variable created equivalents.
    .DESCRIPTION
    Replace here strings with variable created equivalents.
    .PARAMETER Code
    Multiple lines of code to analyze
    .EXAMPLE
       PS > $testfile = 'C:\temp\test.ps1'
       PS > $test = Get-Content $testfile -raw
       PS > $test | Format-ScriptReplaceHereStrings | clip
       
       Description
       -----------
       Takes C:\temp\test.ps1 as input, formats as the function defines and places the result in the clipboard 
       to be pasted elsewhere for review.

    .NOTES
       Author: Zachary Loeber
       Site: http://www.the-little-things.net/
       Requires: Powershell 3.0

       Version History
       1.0.0 - Initial release
    #>
    [CmdletBinding()]
    param(
        [parameter(Position=0, ValueFromPipeline=$true, HelpMessage='Lines of code to process.')]
        [string[]]$Code
    )
    begin {
        $Codeblock = @()
        $ParseError = $null
        $Tokens = $null
        $FunctionName = $MyInvocation.MyCommand.Name
        Write-Verbose "$($FunctionName): Begin."
        function EscapeChars ([string]$line) {
            $line -replace '`r','``r' -replace '`n','``n'
        }
    }
    process {
        $Codeblock += $Code
    }
    end {
        $ScriptText = $Codeblock | Out-String

        Write-Verbose "$($FunctionName): Attempting to parse AST."
        $AST = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$Tokens, [ref]$ParseError) 
 
        if($ParseError) { 
            $ParseError | Write-Error
            throw "$($FunctionName): Will not work properly with errors in the script, please modify based on the above errors and retry."
        }
        
        $TokenKinds = @($Tokens | Where {$_.Kind -like $Kind})

        for($t = $Tokens.Count - 2; $t -ge 2; $t--) {
            $token = $tokens[$t]
            if ($token.Kind -like "HereString*") {
                switch ($token.Kind) {
                    'HereStringExpandable' {
                        $NewStringOp = '"'
                        $CloseStringOp = '`r`n"'
                    }
                    default {
                        $NewStringOp = "'"
                        $CloseStringOp = "' + " + '"`r`n"'
                    }
                }
                $HereStringVar = $tokens[$t - 2].Text
                $HereStringAssignment = $tokens[$t - 1].Text
                $RemoveStart = $tokens[$t - 2].Extent.StartOffset
                $RemoveEnd = $Token.Extent.EndOffset - $RemoveStart
                $HereStringText = @($Token.Value -split "`r`n")
                $CodeReplacement = $HereStringVar + ' ' + $HereStringAssignment + ' ' + $NewStringOp + (EscapeChars $HereStringText[0]) + $CloseStringOp + "`r`n"
                for($t2 = 1; $t2 -le $HereStringText.Count; $t2++) {
                    $CodeReplacement += $HereStringVar + ' += ' + $NewStringOp + (EscapeChars $HereStringText[$t2]) + $CloseStringOp + "`r`n"
                }
                $ScriptText = $ScriptText.Remove($RemoveStart,$RemoveEnd).Insert($RemoveStart,$CodeReplacement)
            }
        }

        $ScriptText
        Write-Verbose "$($FunctionName): End."
    }
}