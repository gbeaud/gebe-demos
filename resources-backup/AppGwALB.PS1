$ResourceGroupName = "rg-backup-as-code-tests-westeu-01"

# Back up App Gw
$AppGwID = (Get-AzApplicationGateway -Name "apgw-backup-as-code-test-westeu-01" -ResourceGroupName $ResourceGroupName).id

Export-AzResourceGroup -ResourceGroupName $resourceGroupName -SkipAllParameterization -Resource @($AppGwID) -Path "AppGW.json"

# Back up ALB
$ALBID = (Get-AzLoadBalancer -Name "alb-backup-test-westeu-01" -ResourceGroupName $ResourceGroupName).id

Export-AzResourceGroup -ResourceGroupName $resourceGroupName -SkipAllParameterization -Resource @($ALBID) -Path .\"ALB.json"