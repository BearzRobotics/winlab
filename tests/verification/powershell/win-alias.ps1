foreach ($n in 'ls','cat','cp','mv','rm','mkdir','ps','kill','sleep','sort','curl','wget','man','clear') {
    $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1
    '{0,-6} {1}' -f $n, $(if ($c) { "$($c.CommandType)" + $(if ($c.CommandType -eq 'Alias') { " -> $($c.Definition)" } elseif ($c.CommandType -eq 'Application') { " $($c.Source)" } else { '' }) } else { 'not found' })
}
'PROFILE=' + $PROFILE
