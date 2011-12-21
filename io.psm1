function Set-WorkingDirectory {
  <#
  .Synopsis
   Allows to execute given scriptblock in different directory.
  .Description
   Allows to execute given scriptblock in different directory. It wraps
   cmdlets that work with location. It changes the location to $Directory nad
   after the $code is executed, it changes the directory to original one.
  .Example
   Set-location c:\temp
   Set-WorkingDirectory -dir c:\ -code { gci }
   write-host Current directory: get-location

   It performs gci in directory c:\
  #>
	param(
		[Parameter(Mandatory=$true,Position=0)]
		[string]
		$directory,
		[Parameter(Mandatory=$true,Position=1)]
		[scriptblock]
		$code
	)
	Write-Verbose "`nChanging directory to $directory"
	Push-Location
	Set-Location $directory
	try {
		. $code
	}
	finally {
		Pop-Location
		Write-Verbose "Changed directory back to $((get-location).path)"
	}
}