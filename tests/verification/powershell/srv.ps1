$l = [System.Net.HttpListener]::new()
$l.Prefixes.Add('http://localhost:8765/')
$l.Start()
for ($i = 0; $i -lt 6; $i++) {
    $ctx = $l.GetContext()
    $bytes = [Text.Encoding]::UTF8.GetBytes('hello from local server')
    $ctx.Response.ContentType = 'text/plain'
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}
$l.Stop()
