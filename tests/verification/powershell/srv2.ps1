$l = [System.Net.HttpListener]::new()
$l.Prefixes.Add('http://localhost:8766/')
$l.Start()
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
    $task = $l.GetContextAsync()
    while (-not $task.AsyncWaitHandle.WaitOne(500)) { if ((Get-Date) -gt $deadline) { break } }
    if (-not $task.IsCompleted) { break }
    $ctx = $task.Result
    $path = $ctx.Request.Url.AbsolutePath
    $body = ''
    if ($ctx.Request.HasEntityBody) { $body = (New-Object IO.StreamReader($ctx.Request.InputStream)).ReadToEnd() }
    switch ($path) {
        '/json'    { $ctx.Response.ContentType = 'application/json'; $out = '{"name":"demo","items":[1,2,3],"when":"2026-11-21T10:30:00Z"}' }
        '/missing' { $ctx.Response.StatusCode = 404; $out = 'not here' }
        '/echo'    { $ctx.Response.ContentType = 'application/json'; $out = '{"method":"' + $ctx.Request.HttpMethod + '","auth":"' + $ctx.Request.Headers['X-Token'] + '","body":' + $(if ($body) { $body } else { 'null' }) + '}' }
        '/file'    { $ctx.Response.ContentType = 'text/plain'; $out = "line1`nline2`n" }
        '/stop'    { $out = 'bye'; $deadline = Get-Date }
        default    { $out = 'hello' }
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($out)
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}
$l.Stop()
