<#
.SYNOPSIS
Return Exchange 2013 component states, their most recent requester, and other relevant information.
.DESCRIPTION
Return Exchange 2013 component states, their most recent requester, and other relevant information.
.PARAMETER NonActiveOnly
Only return results for components not in an active state.
.PARAMETER ServerFilter
Limit results to specific servers.

.EXAMPLE
PS > Get-Exchange2013ComponentStateHistory | ft -AutoSize

Description
-----------
Show all component states for all servers along with their most recent requester.

.EXAMPLE
PS > Get-Exchange2013ComponentStateHistory | Where {($_.Requesters).Count -gt 1 } | ft -AutoSize

Description
-----------
List all components with more than 1 historical requester

.NOTES
Author: Zachary Loeber
Requires: Powershell 3.0, Exchange 2013
Version History
1.0.0 - 12/07/2014
- Initial release

The component state cliff notes:
    Component State Requesters
    * HealthAPI - Reserved by managed availability (probably shouldn't ever use this if setting component states)
    * Maintenance
    * Sidelined
    * Functional
    * Deployment

    Multiple requesters can set a component state. 
    Note: When there are multiple requesters 'Inactive' is prioritized over 'Active'

    Global Components
    * ServerwideOffline - Overrules the states of all other components except for Monitoring and RecoveryActionsEnabled

    Managed Availability Components (I think)
    * Monitoring
    * RecoveryActionsEnabled

    Transport Components (Only components which can be in 'draining' state)
    * FrontendTransport
    * HubTransport

    All other components
    * AutoDiscoverProxy
    * ActiveSyncProxy
    * EcpProxy
    * EwsProxy
    * ImapProxy
    * OabProxy
    * OwaProxy
    * PopProxy
    * PushNotificationsProxy
    * RpsProxy
    * RwsProxy
    * RpcProxy
    * UMCallRouter
    * XropProxy
    * HttpProxyAvailabilityGroup
    * ForwardSyncDaemon
    * ProvisioningRps
    * MapiProxy
    * EdgeTransport
    * HighAvailability
    * SharedCache

.LINK
https://github.com/zloeber/Powershell
.LINK
http://www.the-little-things.net
#>

[CmdLetBinding()]
param(
    [Parameter(Position=0, HelpMessage='Only return results for components not in an active state.')]
    [switch]$NonActiveOnly,
    [Parameter(Position=1, HelpMessage='Limit results to specific servers.')]
    [string]$ServerFilter = '*'
)

begin {
    try {
        $ExchangeServers = Get-ExchangeServer $ServerFilter | Where {$_.AdminDisplayVersion -like 'Version 15.*'}
    }
    catch {
        Write-Warning "Get-Exchange2013ComponentStateHistory: Unable to enumerate Exchange 2013 servers!"
        break
    }
}
process {
    Foreach ($Server in $ExchangeServers) {
        Write-Verbose "Get-Exchange2013ComponentStateHistory: Processing Server - $($Server.Name)"
        try {
            $ComponentStates = Get-ServerComponentState $Server.Name
            if ($NonActiveOnly) {
                $ComponentStates = $ComponentStates | Where {$_.State -ne 'Active'}
                Write-Verbose "Get-Exchange2013ComponentStateHistory: Non-active components - $($ComponentStates.Count)"
            }
            Foreach ($ComponentState in $ComponentStates) {
                Write-Verbose "Get-Exchange2013ComponentStateHistory: Processing Component $($ComponentState.Component)"
                $StateHistory = @()
                # Found in AD
                $StateHistory += $ComponentState.RemoteStates | Select Component,State,Requester,Timestamp,@{n='Source';e={'AD'}}
                # Found in registry
                $StateHistory += $ComponentState.LocalStates | Select Component,State,Requester,Timestamp,@{n='Source';e={'Registry'}}
                $RecentState = $StateHistory | Sort-Object -Property Timestamp -Descending | Select -First 1
                $Requesters = ($StateHistory | select Requester -Unique).Requester
                New-Object psobject -Property @{
                    'Server' = $Server.Name
                    'Component' = $ComponentState.Component
                    'State' = $ComponentState.State
                    'LastChanged' = $RecentState.Timestamp
                    'LastRequester' = $RecentState.Requester
                    'LastSource' = $RecentState.Source
                    'Requesters' = $Requesters
                }
            }
        }
        catch {
            Write-Warning "Get-Exchange2013ComponentStateHistory: Unable to get component state for $($Server.Name)!"
        }
    }
}
end {}