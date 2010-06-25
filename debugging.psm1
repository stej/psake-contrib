function Show-TasksDependencies
{
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[string]
		$psakefile,
		[Parameter(Position=1, Mandatory=$false)]
    	[string[]]$taskList = @()
	)
	if (!(Get-Module powerboots)) {
		Write-Error "Module powerboots is not found. You have to import it first"
		return
	}
	Add-Type -path  "$PSScriptRoot\lib\NodeXl\Microsoft.GLEE.dll"
	Add-Type -path  "$PSScriptRoot\lib\NodeXl\Microsoft.NodeXL.Algorithms.dll"
	Add-Type -path  "$PSScriptRoot\lib\NodeXl\Microsoft.NodeXL.Control.Wpf.dll"
	Add-Type -path  "$PSScriptRoot\lib\NodeXl\Microsoft.NodeXL.Core.dll"
	Add-Type -path  "$PSScriptRoot\lib\NodeXl\Microsoft.NodeXL.Layouts.dll"
	Add-Type -path  "$PSScriptRoot\lib\NodeXl\Microsoft.NodeXL.Util.dll"
	Add-Type -path  "$PSScriptRoot\lib\NodeXl\Microsoft.NodeXL.Visualization.Wpf.dll"
	
	$c = New-Object Microsoft.NodeXL.Visualization.Wpf.NodeXlControl
	$c.Layout = New-Object Microsoft.NodeXL.Layouts.SugiyamaLayout
	#$c.Layout = New-Object Microsoft.NodeXL.Layouts.HarelKorenFastMultiscaleLayout
	$c.BackColor = [System.Windows.Media.Color]::FromRgb(0xff, 0xff, 0xff)
	
	function New-Vertex {
		param($vertices, $name)
		$v = $vertices.Add()
		$v.SetValue([Microsoft.NodeXL.Core.ReservedMetadataKeys]::PerVertexLabel, $name)
		$v.SetValue([Microsoft.NodeXL.Core.ReservedMetadataKeys]::PerVertexShape, [Microsoft.NodeXL.Visualization.Wpf.VertexShape]::label)
		$v.SetValue([Microsoft.NodeXL.Core.ReservedMetadataKeys]::PerColor, [System.Drawing.Color]::Black)
		$v.SetValue([Microsoft.NodeXL.Core.ReservedMetadataKeys]::PerVertexLabelFillColor, [System.Drawing.Color]::White)
		$v
	}
	
	
	function New-Edge {
		param($edges, $vert1, $vert2)
		$e = $edges.Add($vert1, $vert2, $true)
		$e.SetValue([Microsoft.NodeXL.Core.ReservedMetadataKeys]::PerColor, [System.Drawing.Color]::Blue)
		$e.SetValue([Microsoft.NodeXL.Core.ReservedMetadataKeys]::PerEdgeWidth, [single]3)
		$e
	}
	
	function Get-TaskGraph {
		$m = Import-Module "$PsscriptRoot\..\psake\psake.psm1" -pass
		& $m { 
			$script:dependencies = New-Object Collections.ArrayList
			
			${function:Write-TaskTimeSummary} = {}
			$function:ExecuteTask = {
				param($taskName) 
				$taskKey = $taskName.ToLower()
				$task = $script:context.Peek().tasks.$taskKey
				foreach($childTask in $task.DependsOn)
				{
					[void]$dependencies.Add((New-Object PSObject -Property @{Parent=$taskName; DependsOn=$childTask }))
					ExecuteTask $childTask
				}
			}
		}
		Invoke-Psake $psakefile -task $taskList > $null
		$dependencies = @(& $m { $script:dependencies })
		Remove-Module psake
		$dependencies
	}
	$dependencies = @(Get-TaskGraph)
	@($dependencies | Select-Object -ExpandProperty Parent) + @($dependencies | Select-Object -ExpandProperty DependsOn) |
		Select-Object -unique |
		% -begin { $vertices=@{}}`
		  -process { 
		  	Write-Debug "Adding vertex for $_"
			$vertices[$_] = New-Vertex $c.Graph.Vertices $_
		}
	
	$dependencies | % {
		Write-Debug "Adding edge for $_"
		New-Edge $c.Graph.Edges $vertices[$_.Parent] $vertices[$_.DependsOn] > $null
	}
	
	Boots {	
		$c
	} -width 400 -heigh 400 -On_Loaded { $c.DrawGraphAsync($true) }
}