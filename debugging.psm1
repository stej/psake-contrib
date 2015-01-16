function Show-TasksDependencies
{
<#
.SYNOPSIS
Shows graphically tasks that gets called

.PARAMETER psakefile
File with psake build script

.PARAMETER taskList
Tasks that that should be visualized

.EXAMPLE
ipmo d:\psake-contrib\debugging.psm1; Show-TasksDependencies d:\UdpLogViewer\psake-build.ps1 -taskList Full

Shows what tasks are called when Full task is specified during Invoke-Psake buildfile Full

Assumes that psake module is on a default path "$PsscriptRoot\..\psake\psake.psm1"

.EXAMPLE
ipmo d:\psake-contrib\debugging.psm1; Show-TasksDependencies d:\UdpLogViewer\psake-build.ps1 -taskList Full -psakeModuleFile d:\psake\psake.psm1

Shows what tasks are called when Full task is specified during Invoke-Psake buildfile Full
#>
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[string]
		$psakefile,
		[Parameter(Position=1, Mandatory=$false)]
		[string[]]$taskList = @(),
		[Parameter(Position=2, Mandatory=$false)]
		[string]
		$psakeModuleFile="$PsscriptRoot\..\psake\psake.psm1"
	)
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
		$m = Import-Module $psakeModuleFile -pass
		& $m {
			$script:dependencies = New-Object Collections.ArrayList

			${function:Write-TaskTimeSummary} = {}
			${function:Invoke-Task} = {
				param($taskName)
				write-host Task $taskname
				$taskKey = $taskName.ToLower()
				$currentContext = $psake.context.Peek()
        $tasks = $currentContext.tasks
        $task = $tasks.$taskKey
				foreach($childTask in $task.DependsOn)
				{
					[void]$dependencies.Add((New-Object PSObject -Property @{Parent=$taskName; DependsOn=$childTask }))
					Invoke-Task $childTask
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

	$window = New-Object Windows.Window
  $window.Title = "Invoke-Psake build visualizer"
  $window.Content = $c
  $window.Width,$window.Height = 400,400
  $window.Left, $window.Top = 10,10
  $window.TopMost = $true
  $window.Add_Loaded({ $c.DrawGraphAsync($true) })
  $null = $window.ShowDialog()
}