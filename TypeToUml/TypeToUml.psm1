
function _newRecordLabel {
    param(
        [Parameter(Mandatory)]
        [type]
        $Type
    )

    if ($Type.IsInterface) {
        return "&lt;&lt;Interface&gt;&gt;<br />$($Type.FullName)"
    }

    if ($Type.IsAbstract) {
        return "<i>$($Type.FullName)</i>"
    }

    return $type.FullName

}

function _getDeclaredMembers {
    param(
        [Parameter(Mandatory)]
        [type]
        $Type
    )

    $props = $type.GetMembers(
        [System.Reflection.BindingFlags]::Public -bor
        [System.Reflection.BindingFlags]::Instance -bor
        [System.Reflection.BindingFlags]::Static -bor
        [System.Reflection.BindingFlags]::DeclaredOnly
    ) | Where-Object { $_.IsSpecialName -ne $true }

$props
}

function _getMethodSignature {
    param(
        [Parameter(Mandatory)]
        [System.Reflection.MethodInfo]
        $MethodInfo
    )

    $methodParamString = ($MethodInfo.GetParameters() |
            Foreach-Object {
                "{0} {1}" -f $_.ParameterType, $_.Name
            }) -join ","

    "{0} ({1}) : {2}" -f $MethodInfo.Name, $methodParamString, $MethodInfo.ReturnType

}

function _getPropertySignature {
    param(
        [Parameter(Mandatory)]
        [System.Reflection.PropertyInfo]
        $MethodInfo
    )

    "{0}: {1}" -f $MethodInfo.Name, $MethodInfo.PropertyType
}

function _convertTypeToNode {
    param(
        [Parameter(Mandatory)]
        [Type]
        $Type
    )
    $members = _getDeclaredMembers $type
    $methodSignatures = $members |
        Where-Object MemberType -eq Method |
        Foreach-Object { _getMethodSignature $_ }

    $propertySignatures = $members |
        Where-Object MemberType -eq Property |
        Foreach-Object { _getPropertySignature $_ }

    Record $Type.FullName -Label (_newRecordLabel $Type) {
        row (($propertySignatures -join '<br ALIGN="LEFT"/>') + '<br ALIGN="LEFT"/>')
        row (($methodSignatures -join '<br ALIGN="LEFT"/>') + '<br ALIGN="LEFT"/>')
    }
}

function _getBaseType {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Type]
        $Type
    )

    if ($null -ne $Type.BaseType) {
        Write-Verbose "Got base type $($type.BaseType.FullName)"
        $baseType = $Type.BaseType
        _getBaseType -Type $baseType
        return $baseType
    }
}

function _addTypeToHT {
    param(
        [type]$Type,
        [switch]$IncludeInterfaces
    )

    if (-not $script:TypeHashtable[$Type.FullName]) {
        Write-Verbose "[_addTypeToHt] $($script:TypeHashtable)"
        $script:TypeHashtable[$Type.FullName] = $Type
    }

    if ($IncludeInterfaces) {
        $Type.ImplementedInterfaces | Foreach-Object {
            if (-not $script:TypeHashtable[$_.FullName]) {
                $script:TypeHashtable[$_.FullName] = $_
            }
        }
    }
}

<#
.SYNOPSIS
Generates a UML diagram from a .NET type

.DESCRIPTION
Takes one or several .NET types and generates a UML diagram.

.PARAMETER Type
The type to generate a UML diagram for.

.PARAMETER IncludeBaseTypes
Recursively include base types to the input type(s)

.PARAMETER IncludeInterfaces
Includes interfaces implemented by types.

.PARAMETER Raw
Generate raw graphviz output

.EXAMPLE
PS> [Type]"System.Diagnostics.Process" | New-TypeUMLDiagram -IncludeBaseTypes

Generate a UML diagram for the type System.Diagnostics.Process and include base types.

.NOTES
General notes
#>

function Show-TypeUmlDiagram {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Type[]]
        $Type,

        [Parameter()]
        [switch]
        $IncludeBaseTypes,

        [Parameter()]
        [switch]
        $IncludeInterfaces,

        [Parameter()]
        [switch]
        $Raw
    )

    begin {
        $script:TypeHashtable = @{ }
        $addTypeSplat = @{}
        if ($IncludeInterfaces) {
            $addTypeSplat['IncludeInterfaces'] = $true
        }
    }

    process {
        foreach ($t in $Type) {
            _addTypeToHT -Type $t @addTypeSplat
            if ($IncludeBaseTypes) {
                $t | _getBaseType | ForEach-Object {
                    _addTypeToHT -Type $_ @addTypeSplat
                }
        }
    }
}

end {
    $graph = graph g @{rankdir = 'BT' } {
        foreach ($t in $script:TypeHashtable.GetEnumerator()) {
            _convertTypeToNode $t.Value
            try {
                if ($null -ne $script:TypeHashtable[$t.Value.BaseType.FullName]) {
                    edge -From $t.Value.Fullname -To $t.Value.BaseType.FullName
                }
                if ($IncludeInterfaces) {
                    foreach ($i in $t.Value.ImplementedInterfaces) {
                        edge -From $t.Value.FullName -To $i.FullName
                    }
                }
            } catch {

            }

        }
    }
    Write-Verbose "$($script:TypeHashtable | Out-String)"
    if ($Raw) {
        $graph
    } else {
        $graph | Export-PSGraph -ShowGraph
}
}
}