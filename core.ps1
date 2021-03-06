param(
    [Parameter(Mandatory = $false)]
    [Array]$Algorithm = $null,

    [Parameter(Mandatory = $false)]
    [Array]$PoolsName = $null,

    [Parameter(Mandatory = $false)]
    [array]$CoinsName= $null,

    [Parameter(Mandatory = $false)]
    [String]$Proxy = "", #i.e http://192.0.0.1:8080

    [Parameter(Mandatory = $false)]
    [String]$MiningMode = $null,


    [Parameter(Mandatory = $false)]
    [array]$Groupnames = @()


)

. .\Include.ps1


##Parameters for testing, must be commented on real use

#$MiningMode='Automatic'
#$MiningMode='Automatic24h'
#$MiningMode='Manual'

#$PoolsName=('zpool','mining_pool_hub')
#$PoolsName='whattomine_virtual'
#$PoolsName='yiimp'
#$PoolsName='nanopool'
#$PoolsName=('hash_refinery','zpool')
#$PoolsName='mining_pool_hub'
#$PoolsName='zpool'
#$PoolsName='hash_refinery'
#$PoolsName='ahashpool'
#$PoolsName='suprnova'

#$PoolsName="Nicehash"

#$Coinsname =('bitcore','Signatum','Zcash')
#$Coinsname ='bitcoingold'
#$Algorithm =('x11')





$env:CUDA_DEVICE_ORDER = 'PCI_BUS_ID' #This align cuda id with nvidia-smi order

Set-Location (Split-Path $script:MyInvocation.MyCommand.Path)

Get-ChildItem . -Recurse | Unblock-File
try {if ((Get-MpPreference).ExclusionPath -notcontains (Convert-Path .)) {Start-Process powershell -Verb runAs -ArgumentList "Add-MpPreference -ExclusionPath '$(Convert-Path .)'"}}catch {}

if ($Proxy -eq "") {$PSDefaultParameterValues.Remove("*:Proxy")}
else {$PSDefaultParameterValues["*:Proxy"] = $Proxy}


$ActiveMiners = @()

$LogFile=".\Logs\$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt"
Start-Transcript $LogFile




$ActiveMinersIdCounter=0
$Activeminers=@()
$ShowBestMinersOnly=$true
$FirstTotalExecution =$true
$StartTime=get-date



set-WindowSize 120 60


$Screen=(Get-Content config.txt | Where-Object {$_ -like '@@STARTSCREEN=*'} )-replace '@@STARTSCREEN=',''



#---Paraneters checking

if ($MiningMode -ne 'Automatic' -and $MiningMode -ne 'Manual' -and $MiningMode -ne 'Automatic24h'){
    "Parameter MiningMode not valid, valid options: Manual, Automatic, Automatic24h" |Out-host
    EXIT
   }



$PoolsChecking=Get-Pools -Querymode "info" -PoolsFilterList $PoolsName -CoinFilterList $CoinsName -Location $location -AlgoFilterList $Algorithm

$PoolsErrors=@()
switch ($MiningMode){
    "Automatic"{$PoolsErrors =$PoolsChecking |Where-Object ActiveOnAutomaticMode -eq $false}
    "Automatic24h"{$PoolsErrors =$PoolsChecking |Where-Object ActiveOnAutomatic24hMode -eq $false}
    "Manual"{$PoolsErrors =$PoolsChecking |Where-Object ActiveOnManualMode -eq $false }
    }


$PoolsErrors |ForEach-Object {
    "Selected MiningMode is not valid for pool "+$_.name |Out-host
    EXIT
}



if ($MiningMode -eq 'Manual' -and ($Coinsname | Measure-Object).count -gt 1){
    "On manual mode only one coin must be selected" |Out-host
    EXIT
   }


if ($MiningMode -eq 'Manual' -and ($Coinsname | Measure-Object).count -eq 0){
    "On manual mode must select one coin" |Out-host
    EXIT
   }

if ($MiningMode -eq 'Manual' -and ($Algorithm | measure-object).count -gt 1){
    "On manual mode only one algorithm must be selected" |Out-host
    EXIT
   }


#parameters backup


    $ParamAlgorithmBCK=$Algorithm
    $ParamPoolsNameBCK=$PoolsName
    $ParamCoinsNameBCK=$CoinsName
    $ParamMiningModeBCK=$MiningMode




#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#This loop will be runnig forever
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------

$IntervalStartAt = (Get-Date)
Clear-Host;$repaintScreen=$true

while ($true) {

    $location=@()
    $Types=@()
    $Currency=@()




    $Location=((Get-Content config.txt | Where-Object {$_ -like '@@LOCATION=*'} )-replace '@@LOCATION=','').TrimEnd()



    $Types0=(Get-Content config.txt | Where-Object {$_ -like '@@GPUGROUPS=*'}) -replace '@@GPUGROUPS=*','' |ConvertFrom-Json
     $c=0
     $Types0 | foreach-object {

                                if (((compare-object $_.Groupname $Groupnames -IncludeEqual -ExcludeDifferent  | Measure-Object).Count -gt 0) -or (($Groupnames | Measure-Object).count -eq 0)) {
                                            $_ | Add-Member Id $c
                                            $c=$c+1
                                            $_ | Add-Member GpusClayMode ($_.gpus -replace '10','A' -replace '11','B' -replace '12','C' -replace '13','D' -replace '14','E' -replace '15','F' -replace '16','G'  -replace ',','')
                                            $_ | Add-Member GpusETHMode ($_.gpus -replace ',',' ')
                                            $_ | Add-Member GpusNsgMode ("-d "+$_.gpus -replace ',',' -d ')
                                            $_ | Add-Member GpuPlatform (Get-Gpu-Platform $_.Type)

                                            $Types+=$_
                                            }
                             }



    $InitialProfitsScreenLimit=[Math]::Floor( 25 / (($Types | Measure-Object).count)) #screen adjust to number of groups
    if ($FirstTotalExecution) {$ProfitsScreenLimit=$InitialProfitsScreenLimit}


    $Currency=((Get-Content config.txt | Where-Object {$_ -like '@@CURRENCY=*'} )-replace '@@CURRENCY=','').TrimEnd()
    $BechmarkintervalTime=(Get-Content config.txt | Where-Object {$_ -like '@@BENCHMARKTIME=*'} )-replace '@@BENCHMARKTIME=',''
    $LocalCurrency=((Get-Content config.txt | Where-Object {$_ -like '@@LOCALCURRENCY=*'} )-replace '@@LOCALCURRENCY=','').TrimEnd()
    if ($LocalCurrency.length -eq 0) { #for old config.txt compatibility
        switch ($location) {
            'Europe' {$LocalCurrency="EURO"}
            'US'     {$LocalCurrency="DOLLAR"}
            'ASIA'   {$LocalCurrency="DOLLAR"}
            'GB'     {$LocalCurrency="GBP"}
            default {$LocalCurrency="DOLLAR"}
            }
        }


    #Donation
    $LastIntervalTime= (get-date) - $IntervalStartAt
    $IntervalStartAt = (Get-Date)
    $ElapsedDonationTime = [int](Get-Content Donation.ctr) + $LastIntervalTime.minutes + ($LastIntervalTime.hours *60)


    $Dt=((Get-Content config.txt | Where-Object {$_ -like '@@DONATE=*'} )-replace '@@DONATE=','')
    $DonateTime=if ($Dt -gt 0) {[int]$Dt} else {0}
    #Activate or deactivate donation
    if ($ElapsedDonationTime -gt 1440 -and $DonateTime -gt 0) { # donation interval

                $DonationInterval = $true
                $UserName = "MikeBuzz"
                $WorkerName = "Megaminer"
                $CoinsWallets=@{}
                $CoinsWallets.add("BTC","39hpJhfk5iVr97ouFFggK4k6zW5NerymxV")


                $NextInterval=$DonateTime *60

                $Algorithm=$null
                $PoolsName="mining_pool_hub"
                $CoinsName=$null
                $MiningMode="Automatic"

                0 | Set-Content  -Path Donation.ctr

            }
            else { #NOT donation interval
                    $DonationInterval = $false
                    $NextInterval=[int]((Get-Content config.txt | Where-Object {$_ -like '@@INTERVAL=*'}) -replace '@@INTERVAL=','')

                    $Algorithm=$ParamAlgorithmBCK
                    $PoolsName=$ParamPoolsNameBCK
                    $CoinsName=$ParamCoinsNameBCK
                    $MiningMode=$ParamMiningModeBCK
                    $UserName=((Get-Content config.txt | Where-Object {$_ -like '@@USERNAME=*'} )-replace '@@USERNAME=','').TrimEnd()
                    $WorkerName=((Get-Content config.txt | Where-Object {$_ -like '@@WORKERNAME=*'} )-replace '@@WORKERNAME=','').TrimEnd()
                    $CoinsWallets=@{}
                    ((Get-Content config.txt | Where-Object {$_ -like '@@WALLET_*=*'}) -replace '@@WALLET_*=*','').TrimEnd() | ForEach-Object {$CoinsWallets.add(($_ -split "=")[0],($_ -split "=")[1])}

                    $ElapsedDonationTime | Set-Content  -Path Donation.ctr

                 }


    $Rates = [pscustomObject]@{}
    try { $Currency | ForEach-Object {$Rates | Add-Member $_ (Invoke-WebRequest "https://api.cryptonator.com/api/ticker/btc-$_" -UseBasicParsing | ConvertFrom-Json).ticker.price}} catch {}



    #Load information about the Pools, only must read parameter passed files (not all as mph do), level is Pool-Algo-Coin
     do
        {
        $Pools=Get-Pools -Querymode "core" -PoolsFilterList $PoolsName -CoinFilterList $CoinsName -Location $location -AlgoFilterList $Algorithm
        if  ($Pools.Count -eq 0) {
                "NO POOLS!....retry in 10 sec" | Out-Host
                "REMEMBER, IF YOUR ARE MINING ON ANONYMOUS WITHOUT AUTOEXCHANGE POOLS LIKE YIIMP, NANOPOOL, ETC. YOU MUST SET WALLET FOR AT LEAST ONE POOL COIN IN CONFIG.TXT" | Out-Host
                Start-Sleep 10}
        }
    while ($Pools.Count -eq 0)




    #Load information about the Miner asociated to each Coin-Algo-Miner

    $Miners= @()
    $ApiInitialPort=2000



    foreach ($MinerFile in (Get-ChildItem "Miners" | Where-Object extension -eq '.json'))
        {
            try { $Miner =$MinerFile | Get-Content | ConvertFrom-Json }
            catch
                {   "-------BAD FORMED JSON: $MinerFile" | Out-host
                Exit}

            #Only want algos selected types
       #     If ($Types.Count -ne 0 -and (Compare-Object $Types.Type $Miner.types -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0)
        #        {

                    foreach ($Algo in ($Miner.Algorithms))
                        {
                            $HashrateValue= 0
                            $HashrateValueDual=0
                            $Hrs=$null

                            ##Algoname contains real name for dual and no dual miners
                            $AlgoName =  (($Algo.PSObject.Properties.Name -split ("_"))[0]).toupper()
                            $AlgoNameDual = (($Algo.PSObject.Properties.Name -split ("_"))[1])
                            if ($AlgoNameDual -ne $null) {$AlgoNameDual=$AlgoNameDual.toupper()}
                            $AlgoLabel = ($Algo.PSObject.Properties.Name -split ("_"))[2]
                            if ($AlgoNameDual -eq $null) {$Algorithms=$AlgoName} else {$Algorithms=$AlgoName+"_"+$AlgoNameDual}

                            if ($miner.ApiPort -eq $null) { #if no apiport specified, assign automatically, if port is specified, more than one group will have problems
                                        $ApiPort=$ApiInitialPort
                                        $ApiInitialPort+=10
                                        $Hrs=$null
                                        }
                            else {
                                $ApiPort=$miner.ApiPort
                                 }


                            #generate pools for each gpu group
                            ForEach ( $TypeGroup in $types) {
                              if  ((Compare-object $TypeGroup.type $Miner.Types -IncludeEqual -ExcludeDifferent | Measure-Object).count -gt 0) { #check group and miner types are the same
                                $Pools | where-object Algorithm -eq $AlgoName | ForEach-Object {   #Search pools for that algo

                                        if ((($Pools | Where-Object Algorithm -eq $AlgoNameDual) -ne  $null) -or ($Miner.Dualmining -eq $false)){
                                           $DualMiningMainCoin=$Miner.DualMiningMainCoin -replace $null,""
                                           if (((Compare-object $_.info $DualMiningMainCoin -IncludeEqual -ExcludeDifferent | Measure-Object).count -gt 0) -or $Miner.Dualmining -eq $false) {  #not allow dualmining if main coin not coincide

                                            $Hrs = Get-Hashrates -minername $Minerfile.basename -algorithm $Algorithms -GroupName $TypeGroup.GroupName -AlgoLabel  $AlgoLabel

                                            $HashrateValue=[long]($Hrs -split ("_"))[0]
                                            $HashrateValueDual=[long]($Hrs -split ("_"))[1]

                                            $ApiPort=$ApiPort+$TypeGroup.Id

                                            if (($Types | Measure-Object).Count -gt 1) {$WorkerName2=$WorkerName+'_'+$TypeGroup.GroupName} else  {$WorkerName2=$WorkerName}


                                             $Arguments = $Miner.Arguments  -replace '#PORT#',$_.Port -replace '#SERVER#',$_.Host -replace '#PROTOCOL#',$_.Protocol -replace '#LOGIN#',$_.user -replace '#PASSWORD#',$_.Pass -replace "#GpuPlatform#",$TypeGroup.GpuPlatform  -replace '#ALGORITHM#',$Algoname -replace '#ALGORITHMPARAMETERS#',$Algo.PSObject.Properties.Value -replace '#WORKERNAME#',$WorkerName2 -replace '#APIPORT#',$APIPORT  -replace '#DEVICES#',$TypeGroup.Gpus   -replace '#DEVICESCLAYMODE#',$TypeGroup.GpusClayMode -replace '#DEVICESETHMODE#',$TypeGroup.GpusETHMode -replace '#GROUPNAME#',$TypeGroup.Groupname -replace "#ETHSTMODE#",$_.EthStMode -replace "#DEVICESNSGMODE#",$TypeGroup.GpusNsgMode
                                             if ($Miner.PatternConfigFile -ne $null) {
                                                             $ConfigFileArguments = (get-content $Miner.PatternConfigFile -raw)  -replace '#PORT#',$_.Port -replace '#SERVER#',$_.Host -replace '#PROTOCOL#',$_.Protocol -replace '#LOGIN#',$_.user -replace '#PASSWORD#',$_.Pass -replace "#GpuPlatform#",$TypeGroup.GpuPlatform   -replace '#ALGORITHM#',$Algoname -replace '#ALGORITHMPARAMETERS#',$Algo.PSObject.Properties.Value -replace '#WORKERNAME#',$WorkerName2 -replace '#APIPORT#',$APIPORT -replace '#DEVICES#',$TypeGroup.Gpus -replace '#DEVICESCLAYMODE#',$TypeGroup.GpusClayMode  -replace '#DEVICESETHMODE#',$TypeGroup.GpusETHMode -replace '#GROUPNAME#',$TypeGroup.Groupname -replace "#ETHSTMODE#",$_.EthStMode -replace "#DEVICESNSGMODE#",$TypeGroup.GpusNsgMode
                                                        }


                                                if ($MiningMode -eq 'Automatic24h') {
                                                        $MinerProfit=[Double]([double]$HashrateValue * [double]$_.Price24h)

                                                        }
                                                    else {
                                                        $MinerProfit=[Double]([double]$HashrateValue * [double]$_.Price)}

                                                #apply fee to profit
                                                if ($Miner.Fee -gt 0) {$MinerProfit=$MinerProfit -($minerProfit*[double]$Miner.fee)}
                                                if ($_.Fee -gt 0) {$MinerProfit=$MinerProfit -($minerProfit*[double]$_.fee)}

                                                $PoolAbbName=$_.Abbname
                                                $PoolName = $_.name
                                                if ($_.PoolWorkers -eq $null) {$PoolWorkers=""} else {$PoolWorkers=$_.Poolworkers.tostring()}
                                                $MinerProfitDual = $null
                                                $PoolDual = $null


                                                if ($Miner.Dualmining)
                                                    {
                                                    if ($MiningMode -eq 'Automatic24h')   {
                                                        $PoolDual = $Pools |where-object Algorithm -eq $AlgoNameDual | sort-object price24h -Descending| Select-Object -First 1
                                                        $MinerProfitDual = [Double]([double]$HashrateValueDual * [double]$PoolDual.Price24h)
                                                         }

                                                         else {
                                                                $PoolDual = $Pools |where-object Algorithm -eq $AlgoNameDual | sort-object price -Descending| Select-Object -First 1
                                                                $MinerProfitDual = [Double]([double]$HashrateValueDual * [double]$PoolDual.Price)
                                                                }

                                                     #apply fee to profit
                                                     if ($Miner.Fee -gt 0) {$MinerProfitDual=$MinerProfitDual -($MinerProfitDual*[double]$Miner.fee)}
                                                     if ($PoolDual.Fee -gt 0) {$MinerProfitDual=$MinerProfitDual -($MinerProfitDual*[double]$PoolDual.fee)}

                                                    $Arguments = $Arguments -replace '#PORTDUAL#',$PoolDual.Port -replace '#SERVERDUAL#',$PoolDual.Host  -replace '#PROTOCOLDUAL#',$PoolDual.Protocol -replace '#LOGINDUAL#',$PoolDual.user -replace '#PASSWORDDUAL#',$PoolDual.Pass  -replace '#ALGORITHMDUAL#',$AlgonameDual -replace '#WORKERNAME#',$WorkerName2 -replace '#APIPORT#',$APIPORT  -replace '#DEVICES#',$TypeGroup.Gpus   -replace '#DEVICESCLAYMODE#',$TypeGroup.GpusClayMode -replace '#DEVICESETHMODE#',$TypeGroup.GpusETHMode -replace '#GROUPNAME#',$TypeGroup.Groupname -replace "#DEVICESNSGMODE#",$TypeGroup.GpusNsgMode
                                                    if ($Miner.PatternConfigFile -ne $null) {
                                                                        $ConfigFileArguments = (get-content $Miner.PatternConfigFile -raw) -replace '#PORTDUAL#',$PoolDual.Port -replace '#SERVERDUAL#',$PoolDual.Host  -replace '#PROTOCOLDUAL#',$PoolDual.Protocol -replace '#LOGINDUAL#',$PoolDual.user -replace '#PASSWORDDUAL#',$PoolDual.Pass -replace '#ALGORITHMDUAL#',$AlgonameDual -replace '#WORKERNAME#',$WorkerName2 -replace '#APIPORT#',$APIPORT  -replace '#DEVICES#',$TypeGroup.Gpus   -replace '#DEVICESCLAYMODE#',$TypeGroup.GpusClayMode -replace '#DEVICESETHMODE#',$TypeGroup.GpusETHMode -replace '#GROUPNAME#',$TypeGroup.Groupname -replace "#DEVICESNSGMODE#",$TypeGroup.GpusNsgMode
                                                                        }

                                                    $PoolAbbName += '|' + $PoolDual.Abbname
                                                    $PoolName += '|' + $PoolDual.name
                                                    if ($PoolDual.Poolworkers -ne $null) {$PoolWorkers += '|' + $PoolDual.Poolworkers.tostring()}

                                                    $AlgoNameDual=$AlgoNameDual.toupper()
                                                    $PoolDual.Info=$PoolDual.Info.tolower()
                                                    }


                                                $Miners += [pscustomobject] @{
                                                                    GroupName = $TypeGroup.GroupName
                                                                    GroupId = $TypeGroup.Id
                                                                    Algorithm = $AlgoName
                                                                    AlgorithmDual = $AlgoNameDual
                                                                    Algorithms=$Algorithms
                                                                    AlgoLabel=$AlgoLabel
                                                                    Coin = $_.Info.tolower()
                                                                    CoinDual = $PoolDual.Info
                                                                    Symbol = $_.Symbol
                                                                    SymbolDual = $PoolDual.Symbol
                                                                    Name = $Minerfile.basename
                                                                    Path = $Miner.Path
                                                                    HashRate = $HashRateValue
                                                                    HashRateDual = $HashrateValueDual
                                                                    Hashrates   = if ($Miner.Dualmining) {(ConvertTo-Hash ($HashRateValue)) + "/s|"+(ConvertTo-Hash $HashrateValueDual) + "/s"} else {(ConvertTo-Hash $HashRateValue) +"/s"}
                                                                    API = $Miner.API
                                                                    Port =$ApiPort
                                                                    Wrap =$Miner.Wrap
                                                                    URI = $Miner.URI
                                                                    Arguments=$Arguments
                                                                    Profit=$MinerProfit
                                                                    ProfitDual=$MinerProfitDual
                                                                    PoolPrice=if ($MiningMode -eq 'Automatic24h') {[double]$_.Price24h} else {[double]$_.Price}
                                                                    PoolPriceDual=if ($MiningMode -eq 'Automatic24h') {[double]$PoolDual.Price24h} else {[double]$PoolDual.Price}
                                                                    Profits  = if ($Miner.Dualmining) {$MinerProfitDual+$MinerProfit} else {$MinerProfit}
                                                                    PoolName = $PoolName
                                                                    PoolAbbName = $PoolAbbName
                                                                    PoolWorkers = $PoolWorkers
                                                                    DualMining = $Miner.Dualmining
                                                                    Username = $_.user
                                                                    WalletMode=$_.WalletMode
                                                                    WalletSymbol = $_.WalletSymbol
                                                                    Host =$_.Host
                                                                    ExtractionPath = $Miner.ExtractionPath
                                                                    GenerateConfigFile = $miner.GenerateConfigFile
                                                                    ConfigFileArguments = $ConfigFileArguments
                                                                    Location = $_.location
                                                                    PrelaunchCommand = $Miner.PrelaunchCommand
                                                                    MinerFee= if ($Miner.Fee -eq $null) {$null} else {[double]$Miner.fee}
                                                                    PoolFee = if ($_.Fee -eq $null) {$null} else {[double]$_.fee}


                                                                }

                                            }
                                         }

                            }  #end foreach pool
                        } #  end if types


                        }

                        }
               # }
        }



    #Launch download of miners
    $Miners |
        where-object URI -ne $null |
        where-object ExtractionPath -ne $null |
        where-object Path -ne $null |
        where-object URI -ne "" |
        where-object ExtractionPath -ne "" |
        where-object Path -ne "" |
        Select-Object URI, ExtractionPath,Path -Unique | ForEach-Object {Start-Downloader -URI $_.URI  -ExtractionPath $_.ExtractionPath -Path $_.Path}



    #Paint no miners message
    $Miners = $Miners | Where-Object {Test-Path $_.Path}
    if ($Miners.Count -eq 0) {"NO MINERS!" | Out-Host ; EXIT}


    #Update the active miners list which is alive for  all execution time
    $ActiveMiners | ForEach-Object {
                    #Search miner to update data

                     $Miner = $miners | Where-Object Name -eq $_.Name |
                            Where-Object Coin -eq $_.Coin |
                            Where-Object Algorithm -eq $_.Algorithm |
                            Where-Object CoinDual -eq $_.CoinDual |
                            Where-Object AlgorithmDual -eq $_.AlgorithmDual |
                            Where-Object PoolAbbName -eq $_.PoolAbbName |
                            Where-Object Arguments -eq $_.Arguments |
                            Where-Object Location -eq $_.Location |
                            Where-Object GroupId -eq $_.GroupId |
                            Where-Object AlgoLabel -eq $_.AlgoLabel




                    $_.Best = $false
                    $_.NeedBenchmark = $false
                    $_.ConsecutiveZeroSpeed=0
                    if ($_.BenchmarkedTimes -ge 2 -and $_.AnyNonZeroSpeed -eq $false) {$_.Status='Cancelled'}
                    $_.AnyNonZeroSpeed  = $false

                    $TimeActive=($_.ActiveTime.Hours*3600)+($_.ActiveTime.Minutes*60)+$_.ActiveTime.Seconds
                    if (($_.FailedTimes -gt 3) -and ($TimeActive -lt 180) -and (($ActiveMiners | Measure-Object).count -gt 1)){$_.Status='Cancelled'} #Mark as cancelled if more than 3 fails and running less than 180 secs, if no other alternative option, try forerever


                    if (($Miner | Measure-Object).count -gt 1) {
                            Clear-Host;$repaintScreen=$true
                            "DUPLICATED ALGO "+$MINER.ALGORITHM+" ON "+$MINER.NAME | Out-host
                            EXIT}

                    if ($Miner) {
                            $_.GroupId  = $Miner.GroupId
                            $_.Profit  = $Miner.Profit
                            $_.ProfitDual  = $Miner.ProfitDual
                            $_.Profits = $Miner.Profits
                            $_.PoolPrice = $Miner.PoolPrice
                            $_.PoolPriceDual = $Miner.PoolPriceDual
                            $_.HashRate  = [double]$Miner.HashRate
                            $_.HashRateDual  = [double]$Miner.HashRateDual
                            $_.Hashrates   = $miner.hashrates
                            $_.PoolWorkers = $Miner.PoolWorkers
                            $_.PoolFee= $Miner.PoolFee
                            }
                    else {
                            $_.IsValid = $false #simulates a delete

                            }

                }


    ##Add new miners to list
    $Miners | ForEach-Object {

                    $ActiveMiner = $ActiveMiners | Where-Object Name -eq $_.Name |
                            Where-Object Coin -eq $_.Coin |
                            Where-Object Algorithm -eq $_.Algorithm |
                            Where-Object CoinDual -eq $_.CoinDual |
                            Where-Object AlgorithmDual -eq $_.AlgorithmDual |
                            Where-Object PoolAbbName -eq $_.PoolAbbName |
                            Where-Object Arguments -eq $_.Arguments|
                            Where-Object Location -eq $_.Location |
                            Where-Object GroupId -eq $_.GroupId |
                            Where-Object AlgoLabel -eq $_.AlgoLabel


                    if ($ActiveMiner -eq $null) {
                        $ActiveMiners += [pscustomObject]@{
                            Id                   = $ActiveMinersIdCounter
                            GroupName            = $_.GroupName
                            GroupId              = $_.GroupId
                            Algorithm            = $_.Algorithm
                            AlgorithmDual        = $_.AlgorithmDual
                            Algorithms           = $_.Algorithms
                            Name                 = $_.Name
                            Coin                 = $_.coin
                            CoinDual             = $_.CoinDual
                            Path                 = Convert-Path $_.Path
                            Arguments            = $_.Arguments
                            Wrap                 = $_.Wrap
                            API                  = $_.API
                            Port                 = $_.Port
                            Profit               = $_.Profit
                            ProfitDual           = $_.ProfitDual
                            Profits              = $_.Profits
                            HashRate             = [double]$_.HashRate
                            HashRateDual         = [double]$_.HashRateDual
                            Hashrates            = $_.hashrates
                            PoolAbbName          = $_.PoolAbbName
                            SpeedLive            = 0
                            SpeedLiveDual        = 0
                            ProfitLive           = 0
                            ProfitLiveDual       = 0
                            PoolPrice            = $_.PoolPrice
                            PoolPriceDual        = $_.PoolPriceDual
                            Best                 = $false
                            Process              = $null
                            NewThisRoud          = $True
                            ActiveTime           = [TimeSpan]0
                            LastActiveCheck      = [TimeSpan]0
                            ActivatedTimes       = 0
                            FailedTimes          = 0
                            Status               = ""
                            BenchmarkedTimes     = 0
                            NeedBenchmark        = $false
                            IsValid              = $true
                            PoolWorkers          = $_.PoolWorkers
                            DualMining           = $_.DualMining
                            PoolName             = $_.PoolName
                            Username             = $_.Username
                            WalletMode           = $_.WalletMode
                            WalletSymbol         = $_.WalletSymbol
                            Host                 = $_.Host
                            ConfigFileArguments  = $_.ConfigFileArguments
                            GenerateConfigFile   = $_.GenerateConfigFile
                            ConsecutiveZeroSpeed = 0
                            AnyNonZeroSpeed      = $false
                            Location             = $_.Location
                            PrelaunchCommand     = $_.PrelaunchCommand
                            MinerFee             = $_.MinerFee
                            PoolFee              = $_.PoolFee
                            AlgoLabel            = $_.AlgoLabel
                            Symbol               = $_.Symbol
                            SymbolDual           = $_.SymbolDual



                        }
                        $ActiveMinersIdCounter++
                }
            }

    #update miners that need benchmarks

    $ActiveMiners | ForEach-Object {

        if ($_.BenchmarkedTimes -le 2 -and $_.isvalid -and ($_.Hashrate -eq 0 -or ($_.AlgorithmDual -ne $null -and $_.HashrateDual -eq 0)))
            {$_.NeedBenchmark=$true}
        }

    #For each type, select most profitable miner, not benchmarked has priority
    foreach ($TypeId in $Types.Id) {

        $BestId=($ActiveMiners |Where-Object IsValid | Where-Object status -ne "Canceled" | where-object GroupId -eq $TypeId | Sort-Object -Descending {if ($_.NeedBenchmark) {1} else {0}}, {$_.Profits},Algorithm | Select-Object -First 1 | Select-Object id)
        if ($BestId -ne $null) {$ActiveMiners[$BestId.PSObject.Properties.value].best=$true}
        }



    #Stop miners running if they arent best now
    $ActiveMiners | Where-Object Best -EQ $false | ForEach-Object {
        if ($_.Process -eq $null) {
            $_.Status = "Failed"
            $_.failedtimes++
        }
        elseif ($_.Process.HasExited -eq $false) {
            $_.Process.CloseMainWindow() | Out-Null
            $_.Status = "Idle"
        }

        try {$_.Process.CloseMainWindow() | Out-Null} catch {} #security closing
    }

    #$ActiveMiners | Where-Object Best -EQ $true  | Out-Host

    Start-Sleep 1 #Wait to prevent BSOD

    #Start all Miners marked as Best

    $ActiveMiners | Where-Object Best -eq $true | ForEach-Object {

        if ($_.NeedBenchmark) {$NextInterval=$BechmarkintervalTime} #if one need benchmark next interval will be short
        $_.Status = "Running"

        if ($_.Process -eq $null -or $_.Process.HasExited -ne $false) {

            $_.ActivatedTimes++

            if ($_.GenerateConfigFile -ne $null) {$_.ConfigFileArguments | Set-Content ($_.GenerateConfigFile)}

            #run prelaunch command
            if ($_.PrelaunchCommand -ne $null -and $_.PrelaunchCommand -ne "") {Start-Process -FilePath $_.PrelaunchCommand}

            if ($_.Wrap) {$_.Process = Start-Process -FilePath "PowerShell" -ArgumentList "-executionpolicy bypass -command . '$(Convert-Path ".\Wrapper.ps1")' -ControllerProcessID $PID -Id '$($_.Port)' -FilePath '$($_.Path)' -ArgumentList '$($_.Arguments)' -WorkingDirectory '$(Split-Path $_.Path)'" -PassThru}
              else {$_.Process = Start-SubProcess -FilePath $_.Path -ArgumentList $_.Arguments -WorkingDirectory (Split-Path $_.Path)}



            if ($_.Process -eq $null) {
                    $_.Status = "Failed"
                    $_.FailedTimes++
                }
            else {
                   $_.Status = "Running"
                   $_.LastActiveCheck=get-date
                }

            }

    }




         #Call api to local currency conversion
        try {
                $CDKResponse = Invoke-WebRequest "https://api.coindesk.com/v1/bpi/currentprice.json" -UseBasicParsing -TimeoutSec 2 | ConvertFrom-Json | Select-Object -ExpandProperty BPI
                Clear-Host;$repaintScreen=$true
            }

            catch {
                Clear-Host;$repaintScreen=$true
                "COINDESK API NOT RESPONDING, NOT POSSIBLE LOCAL COIN CONVERSION" | Out-host
                }

                switch ($LocalCurrency) {
                    'EURO' {$LabelProfit="EUR/Day" ; $localBTCvalue = [double]$CDKResponse.eur.rate}
                    'DOLLAR'     {$LabelProfit="USD/Day" ; $localBTCvalue = [double]$CDKResponse.usd.rate}
                    'GBP'     {$LabelProfit="GBP/Day" ; $localBTCvalue = [double]$CDKResponse.gbp.rate}
                    default {$LabelProfit="USD/Day" ; $localBTCvalue = [double]$CDKResponse.usd.rate}

                }





    $FirstLoopExecution=$True
    $IntervalStartTime=Get-Date

    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------

    while ($Host.UI.RawUI.KeyAvailable)  {$host.ui.RawUi.Flushinputbuffer()} #keyb buffer flush


    #loop to update info and check if miner is running, exit loop is forced inside
    While (1 -eq 1)
        {

        $ExitLoop = $false



        #display interval
            $TimetoNextInterval= NEW-TIMESPAN (Get-Date) ($IntervalStartTime.AddSeconds($NextInterval))
            $TimetoNextIntervalSeconds=($TimetoNextInterval.Hours*3600)+($TimetoNextInterval.Minutes*60)+$TimetoNextInterval.Seconds
            if ($TimetoNextIntervalSeconds -lt 0) {$TimetoNextIntervalSeconds = 0}

            Set-ConsolePosition 93 2
            "Next Interval:  $TimetoNextIntervalSeconds secs" | Out-host
            Set-ConsolePosition 0 0

        #display header
        "-------------------------------------------   MegaMiner 5.0 beta 4   --------------------------------------------------"| Out-host
        "-----------------------------------------------------------------------------------------------------------------------"| Out-host
        "  (E)nd Interval   (P)rofits    (C)urrent    (H)istory    (W)allets                       |" | Out-host

        #display donation message

            if ($DonationInterval) {" THIS INTERVAL YOU ARE DONATING, YOU CAN INCREASE OR DECREASE DONATION ON CONFIG.TXT, THANK YOU FOR YOUR SUPPORT !!!!"}

        #display current mining info

        "-----------------------------------------------------------------------------------------------------------------------"| Out-host

          $ActiveMiners | Where-Object Status -eq 'Running'| Sort-Object GroupId | Format-Table -Wrap  (
              @{Label = "GroupName"; Expression = {$_.GroupName}},
              @{Label = "Speed"; Expression = {if  ($_.AlgorithmDual -eq $null) {(ConvertTo-Hash  ($_.SpeedLive))+'/s'} else {(ConvertTo-Hash  ($_.SpeedLive))+'/s|'+(ConvertTo-Hash ($_.SpeedLiveDual))+'/s'} }; Align = 'right'},
              @{Label = "BTC/Day"; Expression = {$_.ProfitLive.tostring("n5")}; Align = 'right'},
              @{Label = $LabelProfit; Expression = {(([double]$_.ProfitLive + [double]$_.ProfitLiveDual) *  [double]$localBTCvalue ).tostring("n2")}; Align = 'right'},
              @{Label = "Algorithm"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Algorithm+$_.AlgoLabel       } else  {$_.Algorithm+$_.AlgoLabel+ '|' + $_.AlgorithmDual}}},
              @{Label = "Coin"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Coin} else  {($_.symbol)+ '|' + ($_.symbolDual)}}},
              @{Label = "Miner"; Expression = {$_.Name}},
              @{Label = "Pool"; Expression = {$_.PoolAbbName}},
              @{Label = "Location"; Expression = {$_.Location}},
              @{Label = "PoolWorkers"; Expression = {$_.PoolWorkers}}
<#
              @{Label = "BmkT"; Expression = {$_.BenchmarkedTimes}},
              @{Label = "FailT"; Expression = {$_.FailedTimes}},
              @{Label = "Nbmk"; Expression = {$_.NeedBenchmark}},
              @{Label = "CZero"; Expression = {$_.ConsecutiveZeroSpeed}}
              @{Label = "Port"; Expression = {$_.Port}}
 #>





          ) | Out-Host


        $XToWrite=[ref]0
        $YToWrite=[ref]0
        Get-ConsolePosition ([ref]$XToWrite) ([ref]$YToWrite)
        $YToWriteMessages=$YToWrite+1
        $YToWriteData=$YToWrite+2
        Remove-Variable XToWrite
        Remove-Variable YToWrite



        #display profits screen
        if ($Screen -eq "Profits" -and $repaintScreen) {

                    "----------------------------------------------------PROFITS------------------------------------------------------------"| Out-host


                    Set-ConsolePosition 80 $YToWriteMessages

                    "(B)est Miners/All       (T)op "+[string]$InitialProfitsScreenLimit+"/All" | Out-Host


                    Set-ConsolePosition 0 $YToWriteData


                    if ($ShowBestMinersOnly) {
                        $ProfitMiners=@()
                        $ActiveMiners | Where-Object IsValid |ForEach-Object {
                            $ExistsBest=$ActiveMiners | Where-Object GroupId -eq $_.GroupId | Where-Object Algorithm -eq $_.Algorithm | Where-Object AlgorithmDual -eq $_.AlgorithmDual | Where-Object Coin -eq $_.Coin | Where-Object CoinDual -eq $_.CoinDual | Where-Object IsValid -eq $true | Where-Object Profits -gt $_.Profits
                                           if ($ExistsBest -eq $null -and $_.Profits -eq 0) {$ExistsBest=$ActiveMiners | Where-Object GroupId -eq $_.GroupId | Where-Object Algorithm -eq $_.Algorithm | Where-Object AlgorithmDual -eq $_.AlgorithmDual | Where-Object Coin -eq $_.Coin | Where-Object CoinDual -eq $_.CoinDual | Where-Object IsValid -eq $true | Where-Object hashrate -gt $_.hashrate}
                                           if ($ExistsBest -eq $null -or $_.NeedBenchmark -eq $true) {$ProfitMiners += $_}
                                           }
                           }
                    else
                           {$ProfitMiners=$ActiveMiners}


                    $ProfitMiners2=@()
                    ForEach ( $TypeId in $types.Id) {
                            $inserted=1
                            $ProfitMiners | Where-Object IsValid |Where-Object GroupId -eq $TypeId | Sort-Object -Descending GroupName,NeedBenchmark,Profits | ForEach-Object {
                                if ($inserted -le $ProfitsScreenLimit) {$ProfitMiners2+=$_ ; $inserted++} #this can be done with select-object -first but then memory leak happens, ¿why?
                                    }
                        }



                    #Display profits  information
                    $ProfitMiners2 | Sort-Object -Descending GroupName,NeedBenchmark,Profits | Format-Table (
                        @{Label = "Algorithm"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Algorithm+$_.AlgoLabel} else  {$_.Algorithm+$_.AlgoLabel+ '|' + $_.AlgorithmDual}}},
                        @{Label = "Coin"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Coin} else  {($_.Symbol)+ '|' + ($_.SymbolDual)}}},
                        @{Label = "Miner"; Expression = {$_.Name}},
                        @{Label = "Speed"; Expression = {if ($_.NeedBenchmark) {"Benchmarking"} else {$_.Hashrates}}},
                        @{Label = "BTC/Day"; Expression = {if ($_.NeedBenchmark) {"-------"} else {$_.Profits.tostring("n5")}}; Align = 'right'},
                        @{Label = $LabelProfit; Expression = {([double]$_.Profits * [double]$localBTCvalue ).tostring("n2") } ; Align = 'right'},
                        @{Label = "PoolFee"; Expression = {if ($_.PoolFee -ne $null) {"{0:P2}" -f $_.PoolFee}}; Align = 'right'},
                        @{Label = "MinerFee"; Expression = {if ($_.MinerFee -ne $null) {"{0:P2}" -f $_.MinerFee}}; Align = 'right'},
                        @{Label = "Pool"; Expression = {$_.PoolAbbName}},
                        @{Label = "Location"; Expression = {$_.Location}}


                    )  -GroupBy GroupName  |  Out-Host


                    Remove-Variable ProfitMiners
                    Remove-Variable ProfitMiners2

                    $repaintScreen=$false
                }




        if ($Screen -eq "Current") {

                    "----------------------------------------------------CURRENT------------------------------------------------------------"| Out-host


                    Set-ConsolePosition 0 $YToWriteData

                    #Display profits  information
                    $ActiveMiners | Where-Object Status -eq 'Running' | Format-Table -Wrap  (
                        @{Label = "GroupName"; Expression = {$_.GroupName}},
                        @{Label = "Pool"; Expression = {$_.PoolAbbName}},
                        @{Label = "Algorithm"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Algorithm} else  {$_.Algorithm+ '|' + $_.AlgorithmDual}}},
                        @{Label = "Miner"; Expression = {$_.Name}},
                        @{Label = "Command"; Expression = {"$($_.Path.TrimStart((Convert-Path ".\"))) $($_.Arguments)"}}
                    ) | Out-Host

                    #Nvidia SMI-info
                    if ((Compare-Object "NVIDIA" $types.Type -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0) {
                                $NvidiaCards=@()
                                $GpuId=0
                                invoke-expression "./nvidia-smi.exe --query-gpu=gpu_name,utilization.gpu,utilization.memory,temperature.gpu,power.draw,power.limit,fan.speed,pstate,clocks.current.graphics,clocks.current.memory  --format=csv,noheader"  | ForEach-Object {

                                            $SMIresultSplit = $_ -split (",")

                                            $NvidiaCards +=[pscustomObject]@{
                                                        GpuId              = $GpuId
                                                        gpu_name           = $SMIresultSplit[0]
                                                        utilization_gpu    = $SMIresultSplit[1]
                                                        utilization_memory = $SMIresultSplit[2]
                                                        temperature_gpu    = $SMIresultSplit[3]
                                                        power_draw         = $SMIresultSplit[4]
                                                        power_limit        = $SMIresultSplit[5]
                                                        FanSpeed           = $SMIresultSplit[6]
                                                        pstate             = $SMIresultSplit[7]
                                                        ClockGpu           = $SMIresultSplit[8]
                                                        ClockMem           = $SMIresultSplit[9]
                                                    }
                                            $GpuId+=1

                                    }



                                    $NvidiaCards | Format-Table -Wrap  (
                                        @{Label = "GpuId"; Expression = {$_.gpuId}},
                                        @{Label = "Gpu"; Expression = {$_.gpu_name}},
                                        @{Label = "Gpu%"; Expression = {$_.utilization_gpu}},
                                        @{Label = "Mem%"; Expression = {$_.utilization_memory}},
                                        @{Label = "Temp"; Expression = {$_.temperature_gpu}},
                                        @{Label = "FanSpeed"; Expression = {$_.FanSpeed}},
                                        @{Label = "Power"; Expression = {$_.power_draw+" /"+$_.power_limit}},
                                        @{Label = "pstate"; Expression = {$_.pstate}},
                                        @{Label = "ClockGpu"; Expression = {$_.ClockGpu}},
                                        @{Label = "ClockMem"; Expression = {$_.ClockMem}}

                                    ) | Out-Host


                                }

                }



        if ($Screen -eq "Wallets" -or $FirstTotalExecution -eq $true) {



            if ($Screen -eq "Wallets" -and $repaintScreen) {
                             "----------------------------------------------------WALLETS (slow)-----------------------------------------------------"| Out-host

                             Set-ConsolePosition 0 $YToWriteMessages
                             "Start Time: $StartTime                                                       (U)pdate  - $WalletsUpdate  " | Out-Host

                        }


                    if ($WalletsUpdate -eq $null) { #wallets only refresh one time each interval, not each loop iteration

                            $WalletsUpdate=get-date

                            $WalletsToCheck=@()

                            $Pools  | where-object WalletMode -eq 'WALLET' | Select-Object PoolName,AbbName,User,WalletMode,WalletSymbol -unique  | ForEach-Object {
                                    $WalletsToCheck += [pscustomObject]@{
                                                PoolName   = $_.PoolName
                                                AbbName = $_.AbbName
                                                WalletMode = $_.WalletMode
                                                User       = ($_.User -split '\.')[0] #to allow payment id after wallet
                                                Coin = $null
                                                Algorithm = $null
                                                OriginalAlgorithm =$null
                                                OriginalCoin = $null
                                                Host = $null
                                                Symbol = $_.WalletSymbol
                                                }
                                }
                            $Pools  | where-object WalletMode -eq 'APIKEY' | Select-Object PoolName,AbbName,info,Algorithm,OriginalAlgorithm,OriginalCoin,Symbol,WalletMode,WalletSymbol  -unique  | ForEach-Object {


                                    $ApiKeyPattern="@@APIKEY_"+$_.PoolName+"=*"
                                    $ApiKey = (Get-Content config.txt | Where-Object {$_ -like $ApiKeyPattern} )-replace $ApiKeyPattern,''

                                    if ($Apikey -ne "") {
                                            $WalletsToCheck += [pscustomObject]@{
                                                        PoolName   = $_.PoolName
                                                        AbbName = $_.AbbName
                                                        WalletMode = $_.WalletMode
                                                        User       = $null
                                                        Coin = $_.Info
                                                        Algorithm =$_.Algorithm
                                                        OriginalAlgorithm =$_.OriginalAlgorithm
                                                        OriginalCoin = $_.OriginalCoin
                                                        Symbol = $_.WalletSymbol
                                                        ApiKey = $ApiKey
                                                        }
                                                    }
                                      }

                            $WalletStatus=@()
                            $WalletsToCheck |ForEach-Object {

                                            Set-ConsolePosition 0 $YToWriteMessages
                                            "                                                                         "| Out-host
                                            Set-ConsolePosition 0 $YToWriteMessages

                                            if ($_.WalletMode -eq "WALLET") {"Checking "+$_.Abbname+" - "+$_.symbol | Out-host}
                                               else {"Checking "+$_.Abbname+" - "+$_.coin+' ('+$_.Algorithm+')' | Out-host}



                                            $Ws = Get-Pools -Querymode $_.WalletMode -PoolsFilterList $_.Poolname -Info ($_)

                                            if ($_.WalletMode -eq "WALLET") {$Ws | Add-Member Wallet $_.User}
                                            else  {$Ws | Add-Member Wallet $_.Coin}

                                            $Ws | Add-Member PoolName $_.Poolname

                                            $Ws | Add-Member WalletSymbol $_.Symbol

                                            $WalletStatus += $Ws

                                            start-sleep 1 #no saturation of pool api
                                            Set-ConsolePosition 0 $YToWriteMessages
                                            "                                                                         "| Out-host

                                        }


                            if ($FirstTotalExecution -eq $true) {$WalletStatusAtStart= $WalletStatus}

                            $WalletStatus | Add-Member BalanceAtStart [double]$null
                            $WalletStatus | ForEach-Object{
                                    $_.BalanceAtStart = ($WalletStatusAtStart |Where-Object wallet -eq $_.Wallet |Where-Object poolname -eq $_.poolname |Where-Object currency -eq $_.currency).balance
                                    }

                         }


                         if ($Screen -eq "Wallets") {



                            $WalletStatus | where-object Balance -gt 0 | Sort-Object poolname | Format-Table -Wrap -groupby poolname (
                                @{Label = "Coin"; Expression = {$_.WalletSymbol}},
                                @{Label = "Balance"; Expression = {$_.balance.tostring("n5")}; Align = 'right'},
                                @{Label = "IncFromStart"; Expression = {($_.balance - $_.BalanceAtStart).tostring("n5")}; Align = 'right'}

                            ) | Out-Host


                            $Pools  | where-object WalletMode -eq 'NONE' | Select-Object PoolName -unique | ForEach-Object {
                                "NO EXISTS API FOR POOL "+$_.PoolName+" - NO WALLETS CHECK" | Out-host
                                }

                            }

                            $repaintScreen=$false
                        }


        if ($Screen -eq "History" ) {

                    "--------------------------------------------------HISTORY------------------------------------------------------------"| Out-host

                    Set-ConsolePosition 0 $YToWriteMessages
                    "Running Mode: $MiningMode" |out-host

                    Set-ConsolePosition 0 $YToWriteData

                    #Display activated miners list
                    $ActiveMiners | Where-Object ActivatedTimes -GT 0 | Sort-Object -Descending Status, {if ($_.Process -eq $null) {[DateTime]0}else {$_.Process.StartTime}} | Select-Object -First (1 + 6 + 6) | Format-Table -Wrap -GroupBy Status (
                        @{Label = "Speed"; Expression = {if  ($_.AlgorithmDual -eq $null) {(ConvertTo-Hash  ($_.SpeedLive))+'s'} else {(ConvertTo-Hash  ($_.SpeedLive))+'/s|'+(ConvertTo-Hash ($_.SpeedLiveDual))+'/s'} }; Align = 'right'},
                        @{Label = "Active"; Expression = {"{0:dd} Days {0:hh} Hours {0:mm} Minutes" -f $_.ActiveTime}},
                        @{Label = "Launched"; Expression = {Switch ($_.ActivatedTimes) {0 {"Never"} 1 {"Once"} Default {"$_ Times"}}}},
                        @{Label = "Command"; Expression = {"$($_.Path.TrimStart((Convert-Path ".\"))) $($_.Arguments)"}}
                    ) | Out-Host


                    $repaintScreen=$false
                }




            #Check Live Speed and record benchmark if necessary
            $ActiveMiners | Where-Object Best -eq $true | ForEach-Object {
                            if ($FirstLoopExecution -and $_.NeedBenchmark) {$_.BenchmarkedTimes++}
                            $_.SpeedLive = 0
                            $_.SpeedLiveDual = 0
                            $_.ProfitLive = 0
                            $_.ProfitLiveDual = 0
                            $Miner_HashRates = $null


                            if ($_.Process -eq $null -or $_.Process.HasExited) {
                                    if ($_.Status -eq "Running") {
                                                $_.Status = "Failed"
                                                $_.FailedTimes++
                                                $ExitLoop = $true
                                                }
                                    else
                                        { $ExitLoop = $true}
                                    }

                            else {
                                    $_.ActiveTime += (get-date) - $_.LastActiveCheck
                                    $_.LastActiveCheck=get-date

                                    $Miner_HashRates = Get-Live-HashRate $_.API $_.Port

                                    if ($Miner_HashRates -ne $null){
                                        $_.SpeedLive = [double]($Miner_HashRates[0])
                                        $_.ProfitLive = $_.SpeedLive * $_.PoolPrice


                                        if ($Miner_HashRates[0] -gt 0) {$_.ConsecutiveZeroSpeed=0;$_.AnyNonZeroSpeed = $true} else {$_.ConsecutiveZeroSpeed++}


                                        if ($_.DualMining){
                                            $_.SpeedLiveDual = [double]($Miner_HashRates[1])
                                            $_.ProfitLiveDual = $_.SpeedLiveDual * $_.PoolPriceDual
                                            }


                                        $Value=[long]($Miner_HashRates[0] * 0.95)
                                        $ValueDual=[long]($Miner_HashRates[1] * 0.95)

                                        if ($Value -gt $_.Hashrate -and $_.NeedBenchmark -and ($valueDual -gt 0 -or $_.Dualmining -eq $false)) {

                                            $_.Hashrate= $Value
                                            $_.HashrateDual= $ValueDual
                                            Set-Hashrates -algorithm $_.Algorithms -minername $_.Name -GroupName $_.GroupName -AlgoLabel $_.AlgoLabel -value  $Value -valueDual $ValueDual
                                            }
                                        }
                                }



                            if ($_.ConsecutiveZeroSpeed -gt 25) { #avoid  miner hangs and wait interval ends
                                $_.FailedTimes++
                                $_.status="Failed"
                                #$_.Best= $false
                                $ExitLoop='true'
                                }



                    }




                $FirstLoopExecution=$False

                #Loop for reading key and wait

                $KeyPressed=Timed-ReadKb 3 ('P','C','H','E','W','U','T','B')





                switch ($KeyPressed){
                    'P' {$Screen='profits'}
                    'C' {$Screen='current'}
                    'H' {$Screen='history'}
                    'E' {$ExitLoop=$true}
                    'W' {$Screen='Wallets'}
                    'U' {if ($Screen -eq "Wallets") {$WalletsUpdate=$null}}
                    'T' {if ($Screen -eq "Profits") {if ($ProfitsScreenLimit -eq $InitialProfitsScreenLimit) {$ProfitsScreenLimit=1000} else {$ProfitsScreenLimit=$InitialProfitsScreenLimit}}}
                    'B' {if ($Screen -eq "Profits") {if ($ShowBestMinersOnly -eq $true) {$ShowBestMinersOnly=$false} else {$ShowBestMinersOnly=$true}}}
                    }

                if ($KeyPressed) {Clear-host;$repaintScreen=$true}

                if (((Get-Date) -ge ($IntervalStartTime.AddSeconds($NextInterval)))  ) { #If time of interval has over, exit of main loop
                                $ActiveMiners | Where-Object Best -eq $true | ForEach-Object { #if a miner ends inteval without speed reading mark as failed
                                       if ($_.AnyNonZeroSpeed -eq $false) {$_.FailedTimes++;$_.status="Failed"}
                                    }
                                 break
                            }

                if ($ExitLoop) {break} #forced exit


        }

    Remove-variable miners
    Remove-variable pools
    Get-Job -State Completed | Remove-Job
    [GC]::Collect() #force garbage recollector for free memory
    $FirstTotalExecution =$False
}

#-----------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------end of alwais running loop--------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------





Stop-Transcript
