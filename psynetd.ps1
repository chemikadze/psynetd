$debug = $false
$logConnections = $false

function main_freebsd() {
  param(
    [Parameter(Mandatory=$False, HelpMessage="Turn on debugging.")]
    [switch]$d,
    [Parameter(Mandatory=$False, HelpMessage="Turn on logging of successful connections.")]
    [switch]$l,
    [Parameter(Mandatory=$False, HelpMessage="Turn on TCP Wrapping for external services.")]
    [switch]$w,
    [Parameter(Mandatory=$False, HelpMessage="Turn on TCP Wrapping for internal services which are built in to inetd.")]
    [switch]$W,
    [Parameter(Mandatory=$False, HelpMessage="The default maximum number of simultaneous invocations of each service.")]
    [int]$c=0,
    [Parameter(Mandatory=$False, HelpMessage="The default maximum number of times a service can be invoked from a single IP address in one minute.")]
    [int]$C=0,
    [Parameter(Mandatory=$False, HelpMessage="Specify one specific IP address to bind to.")]
    [string]$a="0.0.0.0",
    [Parameter(Mandatory=$False, HelpMessage="Specify an alternate file in which to store the process ID.")]
    [string]$p=$null,
    [Parameter(Mandatory=$False, HelpMessage="Specify the maximum number of times a service can be invoked in one minute.")]
    [int]$R=256,
    [Parameter(Mandatory=$False, HelpMessage="Specify the default maximum number of simultaneous invocations of each service from a single IP address.")]
    [int]$s=0,
    [Parameter(Mandatory=$False, Position=0)]
    [string]$config=findDefaultConfig()
  )

  $debugging = $d
  $logConnections = $l

  $services = parseConfig($config)

  foreach ($service in $services) {
    startService($service)
  }

  exit 0
}

function findDefaultConfig() {
  return "$(Split-Path $MyInvocation.MyCommand.Definition)\initd.conf"
}

function log_info($str) {
  Write-Host($str)
}

function log_debug($str) {
  if ($debugging) {
    Write-Host($str)
  }
}

function parseConfig($filename) {
  $delcarations = @()
  $lines = (Get-Content $filename)
  foreach ($line in $lines) {
    if ($line[0] == '#') {
      continue;
    }
    $tokens = $line.Split(" \t", [System.StringSplitOptions]::RemoveEmptyEntries)
    $declaration = New-Object ServiceDeclaration
    $delcaration.port = parsePort($tokens[0])
    $declaration.socketType = parseSocketType($tokens[1])
    $declaration.protocol = parseProtocolName($tokens[2])
    $declaration.wait = ($tokens[3] == "wait")  # TODO nowait/max-child/max-connections-per-ip-per-minute/max-child-per-ip
    $declaration.user = $tokens[4]  # TODO parse user[:group][/login-class]
    $declaration.executablePath = $tokens[5]
    $declaration.arguments = $tokens[6..-1]
    $declarations += $declaration
  }
  return $declarations
}

function parsePort($servname) {
  # TODO getservbyname
  return 42
}

function parseSocketType($socketType) {
  switch ($socketType) {
    "stream" { return [System.Net.Sockets]::SocketType.Stream }
    "dgram" { return [System.Net.Sockets]::SocketType.Dgram }
    "raw" { return [System.Net.Sockets]::SocketType.Raw }
    "rdm" {  return [System.Net.Sockets]::SocketType.Rdm }
    "seqpacket" { return [System.Net.Sockets]::SocketType.Seqpacket }
  }
}

function parseProtocolName($protocol) {
  switch -regex ($protocol) {
    "tcp(4|6|46)?" { return [System.Net.Sockets]::ProtocolType.Tcp }

    "udp(4|6|46)?" { return [System.Net.Sockets]::ProtocolType.Udp }

    "tcp(4|6|46)?/ttcp" { throw "tcp/ttcp is not currently supported" }
    "rpc/tcp" { throw "rpc is not currently supported" }
    "rpc/udp" { throw "rpc is not currently supported" }

    default { throw "unknown protocol $protocol" }
  }
}

Add-Type -Language CSharp @"
public class ServiceDeclaration {
    public int port;
    public System.Net.Sockets.SocketType socketType;
    public string protocol;
    public bool wait;
    public string user;
    public string executablePath;
    public string[] arguments;
}
"@;

function startService([ServiceDeclaration]$service) {
  log_info "Starting service ${service.executablePath}..."
}

function startServer($hostname, $port) {
  $address = $null
  try {
    $address = [System.Net.Dns]::GetHostEntry($hostname).AddressList[0]
  } catch {
    $address = [System.Net.IPAddress]::Parse($hostname)
  }
  if ($address -eq $null) {
    log_info "Wrong address specified, exiting"
    return 1
  }
  try {
    $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList @($address, $port)
    $listener.Start()
  } catch {
    log_info "Listener threw exception, exiting"
    return 1
  }

  log_info "$(Get-Date -format u) Starting main server loop on port $port..."
  while ($true) {
    $client = $listener.AcceptTcpClient()
    if ($logConnections) {
      log_debug "$(Get-Date -format u) Handling new incoming request from ${client.RemoteEndPoint.Address}:${client.RemoteEndPoint.Port}..."
    }
    $stream = $client.GetStream()

    $reqStream = New-Object System.IO.MemoryStream
    $reqBuffer = New-Object Byte[] 1024
    do
    {
      $bytesRead = $stream.Read($reqBuffer, 0, $reqBuffer.Length)
      $reqStream.Write($reqBuffer, 0, $bytesRead)
    } while ($bytesRead > 0)
    $reqData = $reqStream.ToArray()

    # SEND DATA BACK AND FORTH

    $response = "ololo"
    $repBuffer = [System.Text.Encoding]::ASCII.GetBytes($response)
    $stream.Write($repBuffer, 0, $repBuffer.Length)

    $client.Close()
  }
}