function Get-Csprojs {
  <#
  .Synopsis
   Returns all Visual Studio C# projects (csproj files)
  #>
  param(
    [Parameter(Mandatory=$true)]
    [string]
    $baseDirectory
  )
  Get-ChildItem $baseDirectory *.csproj -recurse
}

function Get-CsprojDependencies {
  [CmdletBinding()]
  <#
  .Synopsis
   Returns list of C# projects and its dependencies.
  .Description
   Returns list of C# projects and its dependencies. The dependencies include also dependencies on binaries.
   If a solution contains project A and project B and both copy its output to directory \bin and
   project B depends on \bin\A.dll then there is dependency of B on A, that is not explicit.
   This function is able to find this dependencies and list them as well.
   The example is very simple but in real world, with very projects with more solutions, it is likely
   that there will be some projects that depend on each other through this dependencies.

   This function helps you determine correct order how the projects should be built.
  #>
  param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [System.IO.FileInfo]$Csprojs
  )
  begin {
    Write-Debug "Begin"
    $infos = @()
    $binReference = @{}
    $skipProjs = @{}
  }
  process {
    Write-Debug "Reading csproj $Csprojs.."
    $Csprojs | % {
      $content = [xml](gc $_.FullName)
      if (!($content.Project)) {
        Write-Warning "Project $($_.FullName) skipped. Does not contain root tag with name Project."
        return
      }

      Write-Debug "Reading $($_.FullName)"
      $ret = New-Object PSObject -prop @{FullName=$_.fullname; References=''; AssemblyName='' }

      $ns = @{'e'="http://schemas.microsoft.com/developer/msbuild/2003" }
      $ret.References = @(
        @(Select-Xml -Xml $content -XPath '//e:ProjectReference' -Namespace $ns) |
        select -ExpandProperty Node |
        select -ExpandProperty Include |
        % { Resolve-Path (Join-Path (Split-Path $ret.FullName -Parent) $_ ) })
      $ret.AssemblyName = Select-Xml -Xml $content -XPath '//e:AssemblyName' -Namespace $ns |
        select -ExpandProperty Node -First 1 |
        select -ExpandProperty '#text'

      # processing references to bin
      @(Select-Xml -Xml $content -XPath '//e:Reference' -Namespace $ns) |
        select -ExpandProperty Node |
        ? { $_.HintPath} |
        select -ExpandProperty HintPath |
        % {
          $assemblyName = [IO.Path]::GetFileNameWithoutExtension($_) # e.g. Gmc.System
          if (!$binReference.ContainsKey($assemblyName)) {
            $binReference[$assemblyName] = @()
          }
          $binReference[$assemblyName] += $ret
        }

      $infos += $ret

      Write-Debug "Count of referencies: $($ret.References.Count)"
    }
  }

  end {
    write-Debug "End"
    #resolve dependencies by assembly
    $binReference.Keys |
      % {
        $assemblyName = $_
        $assemblyCsproj = $infos | ? { $_.AssemblyName -eq $assemblyName }
        if (!$assemblyCsproj) {
          $assemblyName
        } else {
          $binReference[$assemblyName] | % { $_.References += $assemblyCsproj.FullName }
        }
      } |
      sort |
      % -Begin {  Write-Verbose "These assemblies are referenced but don't have related projects" } `
        -Process { Write-Verbose " $_" }
    $infos
  }
}

function Get-CsprojIncludedFiles {
  <#
  .Synopsis
   Returns lis of included files that are part of the solution.
  .Description
   Returns lis of included files that are part of the solution.
   Returned list contains full paths to the files.
  #>
  param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true,HelpMessage="Path to csproj file")]
    [IO.FileInfo[]]
    $Csproj
  )
  process {
    $nm = @{n='http://schemas.microsoft.com/developer/msbuild/2003' }
    $Csproj | % {
      [xml](gc $_.FullName) |
        Select-Xml -xpath '//n:ItemGroup/n:Compile' -Namespace $nm |
        Select-Object -exp Node |
        Select-Object -exp Include |
        % { Join-Path (Split-Path $Csproj) $_ }
    }
  }
}

function Get-CsprojInfo {
  <#
  .Synopsis
   Returns information about the C# project.
  .Description
   Returns information about the C# project that can be read from passes project file.
   The information contains:
    Path - full path to he project file
    Directory - directory where the project file is placed
    OutputType - type of project (Assembly, exe, ...)
    RootNamespace
    Assemblyname
    Framework
    Signed - true/false
    SignKey - key used for assembly signing
  #>
  param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true,HelpMessage="Path to csproj file")]
    [IO.FileInfo[]]
    $Csproj
  )
  process {
    $Csproj | % {
      $xml = [xml](gc $_.FullName)
      new-object PSObject -property @{
        Path          = $_.FullName
        Directory     = split-path $_.FullName
        OutputType    = $xml.Project.PropertyGroup[0].OutputType
        RootNamespace = $xml.Project.PropertyGroup[0].RootNamespace
        AssemblyName  = $xml.Project.PropertyGroup[0].AssemblyName
        Framework     = $xml.Project.PropertyGroup[0].TargetFrameworkVersion
        Signed        = $xml.Project.PropertyGroup[0].SignAssembly -eq 'true'
        SignKey       = $xml.Project.PropertyGroup[0].AssemblyOriginatorKeyFile
      }
    }
	}
}

function Get-CsprojsFromSln
{
  param(
    [Parameter(Mandatory=$true)]
    [string]
    $SlnPath,
    [Parameter(Mandatory=$false)]
    [switch]
    $FullPaths
  )
  # from text like Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Gtr.Remote.Api", "Remote.Api\Gtr.Remote.Api.csproj", "{3C1D5E4B-A1B8-4992-A2A5-33D25066F22C}"
  # parses Remote.Api\Gtr.Remote.Api.csproj
  $r = New-Object text.regularexpressions.regex '^Project\([^)]+\)\s*=\s*"[^"]+",\s*"(?<csprojPath>[^"]+)"', 'multiline'
  $content = (Get-Content $SlnPath) -join "`r`n"
  $r.Matches($content) |
    % { $_.Groups["csprojPath"].Value} |
    ? { $_.EndsWith(".csproj") } |
    % { if ($FullPaths) {
          join-path (split-path $SlnPath) $_
        } else {
          $_
        }
    }
}