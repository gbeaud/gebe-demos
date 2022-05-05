targetScope = 'resourceGroup'

param nsgName string
param location string

// Import baseline rules from JSON file
var baselineRules = json(loadTextContent('./baseline-rules.json')).securityRules

//Import custom rules specific to this NSG from JSON file
var customRules = json(loadTextContent('./custom-rules.json')).securityRules

//Optionally, add local rules directly in the Bicep file
var localRules = [
  {
    name: 'Allow_Internet_HTTPS_Inbound'
    properties: {
      description: 'Allow inbound internet connectivity for HTTPS only.'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      priority: 400
      direction: 'Inbound'
    }
  }
]

// Define the NSG resource
resource nsg 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
  name: nsgName
  location: location
  properties: {
    // Combine shared and custom rules
    securityRules: concat(baselineRules, customRules, localRules)
  }
}
