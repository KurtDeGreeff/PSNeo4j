﻿function Remove-Neo4jRelationship {
    <#
    .SYNOPSIS
       Remove Neo4j relationships

    .DESCRIPTION
       Remove Neo4j relationships

       'Left' implies the node a relationship starts from, and 'Right' implies the node a relationship points to

       You can use either LeftLabel/LeftHash, or LeftQuery to determine the nodes on the left, ditto for nodes on the right
       You can't mix and match label/hash and query node selection between the left and right (yet)

    .EXAMPLE
        Remove-Neo4jRelationship -LeftQuery "MATCH (left:Server) WHERE left.ComputerName =~ 'dc.*'" `
                                 -Type 'DependsOn' `
                                 -Properties @{
                                     ServiceHost = $True
                                     LoadBalanced = $True
                                 }
        # Remove relationships...
          # that start on a node labeled 'Server' where the 'ComputerName' starts with dc
          # that are of the type 'DependsOn'
          # That have specific relationship property values

    . PARAMETER LeftLabel
        Determines label of node(s) the relationships start from

        Use in conjunction with LeftHash, if needed

        Warning: susceptible to query injection

    . PARAMETER LeftHash
        Filter nodes the relationship starts from to only nodes containing these keys and values

        Warning: susceptible to query injection (keys only. values are parameterized)

    . PARAMETER RightLabel
        Determines label of node(s) the relationships point to

        Use in conjunction with RightHash, if needed

        Warning: susceptible to query injection

    . PARAMETER RightHash
        Filter nodes the relationship points to to only nodes containing these keys and values

        Warning: susceptible to query injection (keys only. values are parameterized)

    . PARAMETER LeftQuery
        Query to determine which node(s) the relationships start from

        IMPORTANT: This must assign the 'left' variable to the resulting nodes, for example:
                   "MATCH (left:Service)"

    . PARAMETER RightQuery
        Query to determine which node(s) the relationships point to

        IMPORTANT: This must assign the 'right' variable to the resulting nodes, for example:
                   "MATCH (right:Service)"

    . PARAMETER Type
        The relationship type (similar to a label) for the relationship we remove

        Warning: susceptible to query injection

    . PARAMETER Properties
        Filter relationships to delete to relationships with these properties

        Warning: susceptible to query injection (keys only. values are parameterized)

    .PARAMETER As
        Parse the Neo4j response as...
            Parsed:  We attempt to parse the output into friendlier PowerShell objects
                     Please open an issue if you see unexpected output with this
            Raw:     We don't touch the response                           ($Response)
            Results: We expand the 'results' property on the response      ($Response.results)
            Row:     We expand the 'row' property on the responses results ($Response.results.data.row)

        We default to the value specified by Set-PSNeo4jConfiguration (Initially, 'Parsed')

        See ConvertFrom-Neo4jResponse for implementation details

    .PARAMETER MetaProperties
        Merge zero or any combination of these corresponding meta properties in the results: 'id', 'type', 'deleted'

        We default to the value specified by Set-PSNeo4jConfiguration (Initially, 'type')

    .PARAMETER MergePrefix
        If any MetaProperties are specified, we add this prefix to avoid clobbering existing neo4j properties

        We default to the value specified by Set-PSNeo4jConfiguration (Initially, 'Neo4j')

    .PARAMETER BaseUri
        BaseUri to build REST endpoint Uris from

        We default to the value specified by Set-PSNeo4jConfiguration (Initially, 'http://127.0.0.1:7474')

    .PARAMETER Credential
        PSCredential to use for auth

        We default to the value specified by Set-PSNeo4jConfiguration (Initially, not specified)

    .FUNCTIONALITY
        Neo4j
    #>
    [cmdletbinding(DefaultParameterSetName = 'LabelHash')]
    param(
        [parameter( ParameterSetName = 'LabelHash')]
        $LeftLabel,
        [parameter( ParameterSetName = 'LabelHash')]
        $LeftHash,
        [parameter( ParameterSetName = 'LabelHash')]
        $RightLabel,
        [parameter( ParameterSetName = 'LabelHash')]
        $RightHash,

        [parameter( ParameterSetName = 'Query' )]
        $LeftQuery,
        [parameter( ParameterSetName = 'Query' )]
        $RightQuery,

        $Type,
        [hashtable]$Properties,

        [validateset('Raw', 'Results', 'Row', 'Parsed')]
        [string]$As = $PSNeo4jConfig.As,
        [validateset('id', 'type', 'deleted')]
        [string]$MetaProperties = $PSNeo4jConfig.MetaProperties,
        [string]$MergePrefix = $PSNeo4jConfig.MergePrefix,

        [string]$BaseUri = $PSNeo4jConfig.BaseUri,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential =  $PSNeo4jConfig.Credential  
    )
    $SQLParams = @{}
    $LeftVar = $null
    $RightVar = $null
    if($PSCmdlet.ParameterSetName -eq 'LabelHash') {
        $LeftQuery = $null
        if($LeftLabel) {
            $LeftPropString = $null
            if($LeftHash.keys.count -gt 0) {
                $Props = foreach($Property in $LeftHash.keys) {
                    "$Property`: `$left$Property"
                    $SQLParams.Add("left$Property", $LeftHash[$Property])
                }
                $LeftPropString = $Props -join ', '
                $LeftPropString = "{$LeftPropString}"
            }
            $LeftQuery = "MATCH (left:$LeftLabel $LeftPropString)"
        }

        $RightQuery = $null
        if($RightLabel) {
            $RightPropString = $null
            if($RightHash.keys.count -gt 0 -and $RightLabel) {
                $Props = foreach($Property in $RightHash.keys) {
                    "$Property`: `$right$Property"
                    $SQLParams.Add("right$Property", $RightHash[$Property])
                }
                $RightPropString = $Props -join ', '
                $RightPropString = "{$RightPropString}"
            }
            $RightQuery = "MATCH (right:$RightLabel $RightPropString)"
        }
    }

    $InvokeParams = @{}
    $PropString = $null
    if($Properties) {
        $Props = foreach($Property in $Properties.keys) {
            "$Property`: `$relationship$Property"
            $SQLParams.Add("relationship$Property", $Properties[$Property])
        }
        $PropString = $Props -join ', '
        $PropString = "{$PropString}"
    }
    
    if($SQLParams.Keys.count -gt 0) {
        $InvokeParams.add('Parameters', $SQLParams)
    }

    if($LeftQuery) {$LeftVar = 'left'}
    if($RightQuery) {$RightVar = 'right'}
    $Query = @"
$LeftQuery
$RightQuery
MATCH ($LeftVar)-[relationship:$Type $PropString]->($RightVar)
DELETE relationship
"@
    $Params = . Get-ParameterValues -Properties MetaProperties, MergePrefix, Credential, BaseUri, As
    Write-Verbose "$($Params | Format-List | Out-String)"
    Invoke-Neo4jQuery @Params @InvokeParams -Query $Query
}