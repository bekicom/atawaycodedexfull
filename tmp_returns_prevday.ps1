$json = Get-Content 'C:\Users\bekzod\Desktop\savdo 27.2026.json' -Raw | ConvertFrom-Json
$rows = @()
foreach ($sale in $json) {
  $saleCreated = [datetime]$sale.createdAt.'$date'
  foreach ($ret in @($sale.returns)) {
    $retCreated = [datetime]$ret.createdAt.'$date'
    $rows += [pscustomobject]@{
      SaleCashier = $sale.cashierUsername
      SaleCreatedLocal = $saleCreated.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
      ReturnCashier = $ret.cashierUsername
      ReturnCreatedLocal = $retCreated.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
      ReturnDate = $retCreated.ToLocalTime().ToString('yyyy-MM-dd')
      Amount = [double]$ret.totalAmount
      Product = (($ret.items | ForEach-Object { $_.productName }) -join '; ')
    }
  }
}
$rows | Where-Object { $_.ReturnDate -eq '2026-04-27' -and $_.SaleCreatedLocal.Substring(0,10) -ne '2026-04-27' } | Sort-Object ReturnCreatedLocal | ConvertTo-Json -Depth 4
